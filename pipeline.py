#!/usr/bin/env python3
"""
Daily data build for the Spikewise app.

Analyses every stock in nse_universe.json with the shared engine
(catalyst_core.analyze_stock) and writes static JSON to public/data/v1/,
which GitHub Actions publishes to GitHub Pages (free CDN, no cold starts).

Layout written (all compact JSON):
  data/v1/meta.json              build time, last market date, counts
  data/v1/summary.json           one light row per stock (+30-day sparkline)
  data/v1/events.json            catalyst events of the last 120 days, newest first
  data/v1/stocks/<KEY>.json      full detail for one stock (series + all events)
  data/v1/universe.json          ticker/name list for search
  data/v1/config.json            remote app config (copied from app_config.json)
  data/v1/ann_cache.json         announcement lookups, reused by the next run

<KEY> is the ticker with '&' replaced by '_' (M&M -> M_M) -- see file_key().

Run:  python pipeline.py                  -> full universe
      python pipeline.py --limit 20       -> quick local test
Exit code is non-zero when the data-quality gate fails, so a bad build never
replaces the published data.
"""
import argparse
import json
import os
import sys
import time
import warnings
from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime, timedelta, timezone

warnings.filterwarnings("ignore")

import pandas as pd
import requests

import catalyst_core as core

HERE = os.path.dirname(os.path.abspath(__file__))
SCHEMA = 1
EVENT_FEED_DAYS = 120
ANN_RECENT_DAYS = 30          # only look up announcements for events this recent
ANN_BUDGET_SECS = 600         # stop new announcement lookups after this long
NEWS_RECENT_DAYS = 10         # fetch headlines for stocks with an event this recent
NEWS_MAX = 150
MIN_OK_FRACTION = 0.8
MAX_STALE_DAYS = 6
STOCK_STALE_DAYS = 6          # drop stocks (suspended/delisted) this far behind NIFTY
ANN_CACHE_VERSION = "v2"      # bump when filing selection rules change
IST = timezone(timedelta(hours=5, minutes=30))
CLOSE_SETTLED_IST = (16, 15)  # before this, today's Yahoo bar is still intraday
# Model outputs are in-sample with very low fit; they are not published.
PRIVATE_FIELDS = ("pred_move", "pred_dir", "pred_r2", "pred_n")


def file_key(ticker):
    return ticker.replace("&", "_")


def _dump(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(obj, f, separators=(",", ":"), ensure_ascii=False)


def load_prev_ann_cache(prev_url):
    """Announcement lookups from the previously published build (saves NSE calls)."""
    if not prev_url:
        return {}
    try:
        r = requests.get(prev_url.rstrip("/") + "/ann_cache.json", timeout=20)
        if r.ok:
            return r.json()
    except Exception as err:
        print(f"[pipeline] no previous ann_cache: {err}")
    return {}


def light_row(s):
    return {
        "ticker": s["ticker"], "name": s["name"],
        "last_close": s["last_close"], "last_date": s["last_date"],
        "chg_1d": s["chg_1d"], "ret_1m": s["ret_1m"], "ret_3m": s["ret_3m"],
        "ann_vol": s["ann_vol"], "beta": s["beta"],
        "cat_count": s["cat_count"], "last_cat_date": s["last_cat_date"],
        "z_last": s["z_last"], "vr_last": s["vr_last"],
        "rsi": s["rsi"], "mom5": s["mom5"],
        "sentiment": s["sentiment"]["label"],
        "spark": s["close"][-30:],
    }


def drop_partial_session(frames, nifty, now=None):
    """Remove today's bar while the session is still open or settling, so
    intraday prices are never published (or alerted on) as closes."""
    now = (now or datetime.now(timezone.utc)).astimezone(IST)
    if (now.hour, now.minute) >= CLOSE_SETTLED_IST:
        return frames, nifty
    today = pd.Timestamp(now.date())
    nifty = nifty[nifty["Date"] < today].reset_index(drop=True)
    frames = {t: f[f["Date"] < today].reset_index(drop=True) for t, f in frames.items()}
    return frames, nifty


def public_detail(s, ev):
    out = {k: v for k, v in s.items() if k not in PRIVATE_FIELDS}
    out["events"] = sorted(ev, key=lambda e: e["date"], reverse=True)
    return out


def run(out_dir, limit=None, prev_url=None):
    t0 = time.time()
    universe = json.load(open(os.path.join(HERE, "nse_universe.json"), encoding="utf-8"))
    if limit:
        universe = universe[:limit]
    names = {u["ticker"]: u["name"] for u in universe}
    data_dir = os.path.join(out_dir, "data", "v1")

    frames, nifty, failed = core.fetch_prices_batch(list(names))
    print(f"[pipeline] prices: {len(frames)}/{len(names)} in {time.time() - t0:.0f}s")
    frames, nifty = drop_partial_session(frames, nifty)
    last_mkt_ts = nifty["Date"].max()
    stale = []
    for tic in list(frames):
        if frames[tic].empty or (last_mkt_ts - frames[tic]["Date"].max()).days > STOCK_STALE_DAYS:
            stale.append(tic)
            del frames[tic]
    if stale:
        print(f"[pipeline] dropped {len(stale)} stale stocks: {stale[:20]}")

    ann_cache = {k: v for k, v in load_prev_ann_cache(prev_url).items()
                 if k.startswith(ANN_CACHE_VERSION + "|")}
    ann_since = pd.Timestamp(date.today() - timedelta(days=ANN_RECENT_DAYS))
    ann_deadline = time.time() + ANN_BUDGET_SECS

    def ann_lookup(tic, date_s):
        hit = ann_cache.get(f"{ANN_CACHE_VERSION}|{tic}|{date_s}")
        if hit is not None:
            return tuple(hit)
        if time.time() > ann_deadline:
            return (None, None, None, None)
        return None

    stocks, events = {}, []
    for tic, df in frames.items():
        try:
            sdf, nret = core.align_to_nifty(df, nifty)
            if len(sdf) < 40:
                raise ValueError(f"only {len(sdf)} aligned rows")
            s, ev = core.analyze_stock(tic, names[tic], sdf, nret, with_news=False,
                                       with_announcements=core.USE_ANNOUNCEMENTS,
                                       ann_since=ann_since, ann_lookup=ann_lookup)
        except Exception as err:
            print(f"[pipeline] {tic} analysis failed: {err}")
            failed.append(tic)
            continue
        for e in ev:
            if e["announcement"] or pd.Timestamp(e["date"]) < ann_since:
                ann_cache[f"{ANN_CACHE_VERSION}|{tic}|{e['date']}"] = [
                    e["category"], e["announcement"], e["exchange"], e["link"],
                    e["filed"], e["routine"]]
        stocks[tic] = (s, ev)
        events.extend(ev)
    print(f"[pipeline] analysed {len(stocks)} stocks, {len(events)} events "
          f"in {time.time() - t0:.0f}s")

    # Headlines only where something just happened -- keeps Yahoo calls bounded.
    recent = (date.today() - timedelta(days=NEWS_RECENT_DAYS)).isoformat()
    news_for = sorted((t for t, (s, _) in stocks.items()
                       if (s["last_cat_date"] or "") >= recent),
                      key=lambda t: stocks[t][0]["last_cat_date"], reverse=True)[:NEWS_MAX]
    with ThreadPoolExecutor(max_workers=6) as pool:
        for tic, sent in zip(news_for, pool.map(core.fetch_news_sentiment, news_for)):
            stocks[tic][0]["sentiment"] = sent
    print(f"[pipeline] headlines for {len(news_for)} stocks")

    # ---- quality gate ----
    last_mkt = nifty["Date"].max().date()
    ok_frac = len(stocks) / max(1, len(names) - len(stale))
    nifty_age = (date.today() - last_mkt).days
    problems = []
    if ok_frac < MIN_OK_FRACTION:
        problems.append(f"only {ok_frac:.0%} of stocks analysed")
    if nifty_age > MAX_STALE_DAYS:
        problems.append(f"NIFTY data is {nifty_age} days old ({last_mkt})")
    if problems:
        print("[pipeline] QUALITY GATE FAILED: " + "; ".join(problems))
        return 1

    # ---- write ----
    for tic, (s, ev) in stocks.items():
        _dump(os.path.join(data_dir, "stocks", file_key(tic) + ".json"), public_detail(s, ev))

    summary = sorted((light_row(s) for s, _ in stocks.values()), key=lambda r: r["ticker"])
    _dump(os.path.join(data_dir, "summary.json"), summary)

    cutoff = (last_mkt - timedelta(days=EVENT_FEED_DAYS)).isoformat()
    feed = sorted((e for e in events if e["date"] >= cutoff),
                  key=lambda e: (e["date"], abs(e["z"] or 0)), reverse=True)
    _dump(os.path.join(data_dir, "events.json"), feed)

    _dump(os.path.join(data_dir, "universe.json"),
          [{"ticker": t, "name": n, "key": file_key(t)} for t, n in names.items()
           if t in stocks])
    _dump(os.path.join(data_dir, "ann_cache.json"), ann_cache)
    with open(os.path.join(HERE, "app_config.json"), encoding="utf-8") as f:
        _dump(os.path.join(data_dir, "config.json"), json.load(f))

    meta = {
        "schema": SCHEMA,
        "generated": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "last_market_date": last_mkt.isoformat(),
        "stocks": len(stocks), "universe": len(names),
        "failed": sorted(set(failed)), "stale": sorted(stale), "events_feed": len(feed),
        "announcements_matched": sum(1 for e in events if e["announcement"]),
        "z_threshold": core.Z_THRESHOLD, "vol_threshold": core.VOL_RATIO_THRESHOLD,
        "build_secs": round(time.time() - t0, 1),
    }
    _dump(os.path.join(data_dir, "meta.json"), meta)
    print(f"[pipeline] wrote {out_dir} -- {json.dumps(meta)[:400]}")
    return 0


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="Build Spikewise static data.")
    ap.add_argument("--out", default=os.path.join(HERE, "public"))
    ap.add_argument("--limit", type=int, default=None)
    ap.add_argument("--prev-url", default=os.environ.get("PREV_DATA_URL"))
    a = ap.parse_args()
    sys.exit(run(a.out, a.limit, a.prev_url))
