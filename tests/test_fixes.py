"""Regression tests for the launch-blocker fixes (expert review, 2026-10-29)."""
from datetime import datetime, timezone

import numpy as np
import pandas as pd

import catalyst_core as core
import pipeline


def _flat_market(n=80, spike_at=60, spike=0.15, vol_mult=10):
    rng = np.random.default_rng(1)
    dates = pd.bdate_range("2026-01-01", periods=n)
    nret = rng.normal(0, 0.008, n)
    ret = 0.8 * nret + rng.normal(0, 0.01, n)
    ret[spike_at] = spike
    close = 100 * np.cumprod(1 + ret)
    vol = np.full(n, 1_000_000)
    vol[spike_at] *= vol_mult
    df = pd.DataFrame({"Date": dates, "Close": close, "Volume": vol})
    nclose = 20000 * np.cumprod(1 + nret)
    return df, pd.Series(nclose).pct_change()


def test_spike_is_not_absorbed_by_its_own_baseline():
    df, nret = _flat_market()
    d = core.compute_features(df, nret)
    # With the day excluded from its own 20-day baseline, a 15% move on a ~1% vol
    # stock scores far above the old sqrt(20) ~ 4.47 ceiling, and volume reads ~10x.
    assert d["z"].iloc[60] > 6
    assert d["vr"].iloc[60] > 9
    assert bool(d["event"].iloc[60])


def test_filing_tiers():
    assert core.filing_tier("Trading Window") == 2
    assert core.filing_tier("Certificate under SEBI (Depositories and Participants) Regulations, 2018") == 2
    assert core.filing_tier("Copy of Newspaper Publication") == 2
    assert core.filing_tier("Updates") == 1
    assert core.filing_tier("Outcome of Board Meeting") == 0
    assert core.filing_tier("Financial Result Updates") == 0


def test_pick_prefers_specific_filing_and_skips_paperwork():
    ev = pd.Timestamp("2026-10-23")
    rows = [
        {"sort_date": "2026-10-23 10:00:00", "desc": "Trading Window", "attchmntText": "closure", "attchmntFile": "a"},
        {"sort_date": "2026-10-23 11:00:00", "desc": "Updates", "attchmntText": "foundation news", "attchmntFile": "b"},
        {"sort_date": "2026-10-21 18:00:00", "desc": "Outcome of Board Meeting", "attchmntText": "Q2   results", "attchmntFile": "c"},
    ]
    cat, text, exch, link, filed, routine = core.pick_announcement(rows, ev, "NSE")
    assert (cat, link, filed, routine) == ("Outcome of Board Meeting", "c", "2026-10-21", False)
    assert text == "Q2 results"  # whitespace collapsed
    only_paper = rows[:1]
    assert core.pick_announcement(only_paper, ev, "NSE") is None
    cat, *_rest, routine = core.pick_announcement(rows[:2], ev, "NSE")
    assert cat == "Updates" and routine is True


def test_one_filing_explains_at_most_one_spike():
    stocks = {"AAA": ("Alpha", 1000.0, 0.05, 0.02)}
    prices, nifty = core._sample_prices(stocks)
    same = ("Updates", "same text", "NSE", "same-link", "2026-01-01", True)
    _, ev = core.analyze_stock("AAA", "Alpha", prices["AAA"], nifty["Close"].pct_change(),
                               with_news=False, with_announcements=True,
                               ann_lookup=lambda t, d: same)
    assert len(ev) >= 2
    assert sum(1 for e in ev if e["link"] == "same-link") == 1


def test_partial_session_dropped_before_close():
    dates = pd.to_datetime(["2026-10-28", "2026-10-29"])
    frames = {"X": pd.DataFrame({"Date": dates, "Close": [1, 2], "Volume": [1, 1]})}
    nifty = pd.DataFrame({"Date": dates, "Close": [1, 2], "Volume": [0, 0]})
    morning = datetime(2026, 10, 29, 5, 0, tzinfo=timezone.utc)   # 10:30 IST
    f, n = pipeline.drop_partial_session(frames, nifty, now=morning)
    assert n["Date"].max() == pd.Timestamp("2026-10-28") and len(f["X"]) == 1
    evening = datetime(2026, 10, 29, 12, 0, tzinfo=timezone.utc)  # 17:30 IST
    f, n = pipeline.drop_partial_session(frames, nifty, now=evening)
    assert len(n) == 2 and len(f["X"]) == 2


def test_model_fields_never_published():
    s = {"ticker": "X", "pred_move": 0.1, "pred_dir": 0.9, "pred_r2": 0.05, "pred_n": 300, "close": [1]}
    s["sentiment"] = {"label": "bullish", "score": 0.4, "headlines": [{"title": "t"}], "count": 1}
    out = pipeline.public_detail(s, [])
    assert not any(k.startswith("pred_") for k in out)
    assert "label" not in out["sentiment"] and out["sentiment"]["headlines"]
