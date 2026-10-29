"""Engine tests on deterministic offline sample prices (no network)."""
import catalyst_core as core


def _sample():
    stocks = {"AAA": ("Alpha", 1000.0, 0.05, 0.02), "BBB": ("Beta", 500.0, -0.1, 0.015)}
    return core._sample_prices(stocks)


def test_analyze_stock_shapes_and_parity():
    prices, nifty = _sample()
    s, ev = core.analyze_stock("AAA", "Alpha", prices["AAA"], nifty["Close"].pct_change(),
                               with_news=False, with_announcements=False)
    n = len(prices["AAA"])
    assert len(s["dates"]) == len(s["close"]) == len(s["volume"]) == len(s["event_flags"]) == n
    # every flagged day must appear exactly once in the event list
    assert s["cat_count"] == len(ev) == sum(s["event_flags"])
    assert s["last_date"] == s["dates"][-1]
    for e in ev:
        assert e["direction"] in ("Up", "Down")
        # z and vr are rounded to 2 dp in the output, so compare with >=
        assert abs(e["z"]) >= core.Z_THRESHOLD and e["vr"] >= core.VOL_RATIO_THRESHOLD


def test_sample_data_has_planted_catalysts():
    prices, nifty = _sample()
    s, ev = core.analyze_stock("BBB", "Beta", prices["BBB"], nifty["Close"].pct_change(),
                               with_news=False, with_announcements=False)
    assert s["cat_count"] >= 1


def test_forecast_outputs_are_bounded():
    prices, nifty = _sample()
    s, _ = core.analyze_stock("AAA", "Alpha", prices["AAA"], nifty["Close"].pct_change(),
                              with_news=False, with_announcements=False)
    assert s["pred_dir"] is None or 0.0 <= s["pred_dir"] <= 1.0
    assert s["pred_move"] is None or s["pred_move"] >= 0.0
    assert s["rsi"] is None or 0.0 <= s["rsi"] <= 100.0


def test_ann_lookup_is_used_before_network():
    prices, nifty = _sample()
    calls = []

    def lookup(tic, d):
        calls.append(d)
        return ("Cat", "Text", "NSE", None)

    _, ev = core.analyze_stock("AAA", "Alpha", prices["AAA"], nifty["Close"].pct_change(),
                               with_news=False, with_announcements=True, ann_lookup=lookup)
    assert len(calls) == len(ev)
    assert all(e["announcement"] == "Text" for e in ev)


def test_align_to_nifty_inner_joins():
    prices, nifty = _sample()
    df = prices["AAA"].iloc[5:]
    out, nret = core.align_to_nifty(df, nifty)
    assert len(out) == len(df) == len(nret)
