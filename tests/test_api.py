"""API tests with the CDN mocked out (no network)."""
import pytest

import flask_app

SUMMARY = [{"ticker": "INFY", "name": "Infosys", "sentiment": "neutral", "last_close": 1.0},
           {"ticker": "M&M", "name": "Mahindra & Mahindra", "sentiment": "bullish"}]
EVENTS = [{"ticker": "INFY", "date": "2026-10-16"}, {"ticker": "TCS", "date": "2026-10-15"}]
FILES = {"summary.json": SUMMARY, "events.json": EVENTS,
         "universe.json": [{"ticker": "INFY", "name": "Infosys", "key": "INFY"},
                           {"ticker": "M&M", "name": "Mahindra & Mahindra", "key": "M_M"}],
         "meta.json": {"last_market_date": "2026-10-29", "stocks": 2},
         "stocks/M_M.json": {"ticker": "M&M"}}


@pytest.fixture
def client(monkeypatch):
    def fake_cdn(path, ttl=600):
        if path not in FILES:
            raise flask_app.requests.HTTPError("404")
        return FILES[path]
    monkeypatch.setattr(flask_app, "cdn", fake_cdn)
    monkeypatch.setattr(flask_app, "FEEDBACK_TOKEN", None)
    flask_app._hits.clear()
    return flask_app.app.test_client()


def test_health(client):
    r = client.get("/api/health")
    assert r.status_code == 200
    j = r.get_json()
    assert j["status"] == "ok" and j["data"]["last_market_date"] == "2026-10-29"


def test_legacy_stocks_and_events(client):
    j = client.get("/api/stocks").get_json()
    assert j["count"] == 2 and j["stocks"][0]["sentiment"]["label"] == "neutral"
    assert client.get("/api/events?ticker=infy").get_json()["count"] == 1


def test_stock_detail_ampersand_key(client):
    assert client.get("/api/stock/M_M").get_json()["ticker"] == "M&M"
    assert client.get("/api/stock/NOPE").status_code == 404
    assert client.get("/api/stock/bad$tick").status_code == 400


def test_search(client):
    assert [x["ticker"] for x in client.get("/api/search?q=mah").get_json()] == ["M&M"]


def test_feedback_validation_and_rate_limit(client):
    assert client.post("/api/v1/feedback", json={"message": "x"}).status_code == 400
    for _ in range(4):
        r = client.post("/api/v1/feedback", json={"message": "great app", "kind": "idea"})
        assert r.status_code == 200 and r.get_json()["stored"] == "log"
    assert client.post("/api/v1/feedback", json={"message": "again"}).status_code == 429


def test_cors_header(client):
    assert client.get("/api/health").headers["Access-Control-Allow-Origin"] == "*"


def test_removed_mutating_routes(client):
    for path in ("/add", "/remove", "/rebuild", "/manage"):
        assert client.post(path).status_code in (404, 405)
