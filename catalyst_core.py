"""
Shared analysis core for the NSE Catalyst Scanner -- used by BOTH the Excel pipeline
(catalyst_scanner.py) and the static web dashboard (build_dashboard.py), so the two
outputs always agree on exactly which days are flagged.

Same rule as the Excel version: a day is a "catalyst day" when its residual return
(stock return minus a rolling 20-day beta vs NIFTY times NIFTY's return that day) is
more than Z_THRESHOLD standard deviations from that stock's own trailing 20-day
residual volatility, AND volume is more than VOL_RATIO_THRESHOLD x its 20-day average.

STOCKS are now fully dynamic -- stored in stocks_config.json next to this file.
Use add_stock() / remove_stock() to manage them, or edit the JSON directly.
"""
import json
import os
import tempfile
import warnings

import numpy as np
import pandas as pd

try:
    from nse import NSE
    _HAS_NSE = True
except Exception:
    _HAS_NSE = False

try:
    from bse import BSE
    _HAS_BSE = True
except Exception:
    _HAS_BSE = False

LIVE_PERIOD = "6mo"
N_DAYS = 120
Z_THRESHOLD = 1.5
VOL_RATIO_THRESHOLD = 1.25
SEED = 7

USE_ANNOUNCEMENTS = _HAS_NSE or _HAS_BSE
ANNOUNCE_LOOKBACK_DAYS = 7
ANNOUNCE_FORWARD_DAYS = 1

# ------------------------------------------------------------------ stock config

_HERE = os.path.dirname(os.path.abspath(__file__))
_CONFIG_PATH = os.path.join(_HERE, "stocks_config.json")

# Default stocks (used when no config file exists yet)
_DEFAULT_STOCKS = {
    "INFY":       ("Infosys",                        1040.0, -0.24, 0.018),
    "RELIANCE":   ("Reliance Industries",            1309.0, -0.16, 0.014),
    "HDFCBANK":   ("HDFC Bank",                       780.0, -0.05, 0.013),
    "TMPV":       ("Tata Motors Passenger Vehicles",  359.0,  0.04, 0.022),
    "SUNPHARMA":  ("Sun Pharma",                     1840.0,  0.05, 0.015),
}


def _config_to_stocks(cfg: dict) -> dict:
    """Convert the JSON config dict → STOCKS tuple format."""
    out = {}
    for sym, info in cfg.items():
        out[sym] = (
            info.get("name", sym),
            float(info.get("anchor", 1000.0)),
            float(info.get("drift6m", 0.0)),
            float(info.get("sigma", 0.018)),
        )
    return out


def _stocks_to_config(stocks: dict) -> dict:
    """Convert STOCKS tuple format → JSON-serialisable dict."""
    out = {}
    for sym, (name, anchor, drift6m, sigma) in stocks.items():
        out[sym] = {"name": name, "anchor": anchor,
                    "drift6m": drift6m, "sigma": sigma}
    return out


def load_stocks_config() -> dict:
    """Load STOCKS from stocks_config.json; fall back to defaults if missing."""
    if os.path.exists(_CONFIG_PATH):
        try:
            with open(_CONFIG_PATH, "r", encoding="utf-8") as f:
                cfg = json.load(f)
            if cfg:
                return _config_to_stocks(cfg)
        except Exception:
            pass
    return dict(_DEFAULT_STOCKS)


def save_stocks_config(stocks: dict) -> None:
    """Persist current STOCKS dict to stocks_config.json."""
    with open(_CONFIG_PATH, "w", encoding="utf-8") as f:
        json.dump(_stocks_to_config(stocks), f, indent=2)


def reload_stocks() -> None:
    """Re-read stocks_config.json and update the module-level STOCKS dict in place."""
    global STOCKS
    STOCKS = load_stocks_config()


def search_tickers(query: str, max_results: int = 8) -> list:
    """Search for NSE stocks by company name or partial ticker.
    E.g. 'Axis Bank' or 'AXIS' both return [('AXISBANK', 'Axis Bank Ltd'), ...].
    Returns list of (ticker, display_name) tuples. Empty list on failure.
    Uses Yahoo Finance search — real NSE data, no dummy results."""
    if not query or len(query) < 2:
        return []
    try:
        import yfinance as yf
        search = yf.Search(query, max_results=max_results * 3, news_count=0)
        results, seen = [], set()
        for q in search.quotes:
            sym = q.get("symbol", "")
            exch = q.get("exchange", "")
            qtype = q.get("quoteType", "")
            # Only equity stocks on NSE (exchange code NSI); skip indices (^) and ETFs
            if sym.startswith("^") or qtype in ("INDEX", "MUTUALFUND", "ETF"):
                continue
            if exch == "NSI" or sym.endswith(".NS"):
                clean = sym.replace(".NS", "")
                if clean not in seen:
                    name = q.get("shortname") or q.get("longname") or clean
                    results.append((clean, name))
                    seen.add(clean)
                    if len(results) >= max_results:
                        break
        return results
    except Exception:
        return []


def validate_ticker(ticker: str) -> tuple:
    """Fetch recent price data for <ticker> via NSE library (works on PythonAnywhere).
    Returns (display_name, anchor_price, drift6m, sigma) on success,
    raises ValueError with a human-readable message on failure."""
    import datetime, numpy as np
    ticker = ticker.upper().strip()
    end = datetime.date.today()
    start = end - datetime.timedelta(days=200)
    try:
        import tempfile
        from nse import NSE
        nse_obj = NSE(download_folder=tempfile.gettempdir())
        rows = nse_obj.fetch_equity_historical_data(
            symbol=ticker,
            from_date=start,
            to_date=end,
        )
    except Exception as e:
        raise ValueError(f"Could not fetch data for {ticker}: {e}")

    if not rows:
        raise ValueError(f"No data found for {ticker}. Check the NSE ticker symbol.")
    if len(rows) < 30:
        raise ValueError(f"Only {len(rows)} days of data for {ticker} — too short to analyse.")

    closes = [float(r["chClosingPrice"]) for r in rows if r.get("chClosingPrice")]
    if len(closes) < 2:
        raise ValueError(f"Not enough price data for {ticker}.")

    closes = np.array(closes)
    anchor = float(closes[-1])
    rets = np.diff(closes) / closes[:-1]
    drift6m = float((closes[-1] / closes[0]) - 1)
    sigma = float(np.std(rets))
    return ticker, anchor, drift6m, sigma


def add_stock(ticker: str, display_name: str = None) -> str:
    """Validate ticker via NSE, add it to the config, reload STOCKS.
    Returns the display name on success; raises ValueError on failure.
    display_name: optional human-readable name (from search); overrides ticker-as-name."""
    ticker = ticker.upper().strip()
    if ticker in STOCKS:
        raise ValueError(f"{ticker} is already in your watchlist.")
    _name, anchor, drift6m, sigma = validate_ticker(ticker)
    name = display_name or _name
    STOCKS[ticker] = (name, anchor, drift6m, sigma)
    save_stocks_config(STOCKS)
    return name


def remove_stock(ticker: str) -> None:
    """Remove ticker from config and reload STOCKS. Raises ValueError if not found."""
    ticker = ticker.upper().strip()
    if ticker not in STOCKS:
        raise ValueError(f"{ticker} is not in your watchlist.")
    if len(STOCKS) <= 1:
        raise ValueError("You must keep at least one stock in your watchlist.")
    del STOCKS[ticker]
    save_stocks_config(STOCKS)


# Module-level STOCKS — loaded from config at import time
STOCKS = load_stocks_config()


# ------------------------------------------------------------------ price loading

def _make_yf_session():
    """Return a browser-impersonating session for yfinance.
    Uses curl_cffi if available (best); falls back to requests with headers."""
    try:
        from curl_cffi import requests as _cr
        return _cr.Session(impersonate="chrome")
    except ImportError:
        pass
    try:
        import requests as _req
        s = _req.Session()
        s.headers.update({
            "User-Agent": (
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/124.0.0.0 Safari/537.36"
            ),
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.5",
        })
        return s
    except ImportError:
        return None


def _live_prices_nse(stocks):
    """Fetch prices directly from NSE using fetch_equity_historical_data /
    fetch_historical_index_data -- authoritative, no bot-blocking."""
    from nse import NSE as _NSE
    from datetime import date, timedelta
    import tempfile

    nse_obj = _NSE(tempfile.gettempdir())
    end   = date.today()
    start = end - timedelta(days=600)

    def _parse_equity(records):
        rows = []
        for r in records:
            try:
                vol_raw = r.get("chTotTradedQty") or r.get("totalTradedVolume") or 0
                vol = int(str(vol_raw).replace(",", "").split(".")[0] or 0)
                rows.append({
                    "Date":   pd.to_datetime(r["mtimestamp"], dayfirst=True),
                    "Close":  float(str(r["chClosingPrice"]).replace(",", "")),
                    "Volume": vol,
                })
            except Exception:
                continue
        if not rows:
            return pd.DataFrame(columns=["Date", "Close", "Volume"])
        return pd.DataFrame(rows).dropna().sort_values("Date").reset_index(drop=True)

    def _parse_index(records):
        rows = []
        for r in records:
            try:
                rows.append({
                    "Date":   pd.to_datetime(r["EOD_TIMESTAMP"], dayfirst=True),
                    "Close":  float(r["EOD_CLOSE_INDEX_VAL"]),
                    "Volume": int(r.get("HIT_TRADED_QTY", 0)),
                })
            except Exception:
                continue
        if not rows:
            return pd.DataFrame(columns=["Date", "Close", "Volume"])
        return pd.DataFrame(rows).dropna().sort_values("Date").reset_index(drop=True)

    # NSE silently truncates long date ranges, which left an 8-month hole in
    # the data. Fetch in short windows and stitch them together instead.
    CHUNK_DAYS = 60

    def _windows():
        s = start
        while s <= end:
            e = min(s + timedelta(days=CHUNK_DAYS - 1), end)
            yield s, e
            s = e + timedelta(days=1)

    def _as_list(res):
        if isinstance(res, dict):  # some nse versions wrap rows in a dict
            for k in ("data", "price", "records"):
                if isinstance(res.get(k), list):
                    return res[k]
            return []
        return res or []

    def _fetch_chunked(fn, parser, **kw):
        parts = []
        for s, e in _windows():
            try:
                parts.append(parser(_as_list(fn(from_date=s, to_date=e, **kw))))
            except Exception as err:
                print(f"[NSE] chunk {s}..{e} failed: {err}")
        parts = [p for p in parts if not p.empty]
        if not parts:
            return pd.DataFrame(columns=["Date", "Close", "Volume"])
        df = pd.concat(parts, ignore_index=True)
        df["Date"] = df["Date"].dt.normalize()
        return (df.drop_duplicates("Date", keep="last")
                  .sort_values("Date").reset_index(drop=True))

    frames = {}
    for tic in stocks:
        df = _fetch_chunked(nse_obj.fetch_equity_historical_data,
                            _parse_equity, symbol=tic)
        if df.empty or len(df) < 30:
            raise RuntimeError(f"NSE: insufficient data for {tic} ({len(df)} rows)")
        frames[tic] = _adjust_corporate_actions(df)

    # NIFTY 50 index
    nifty = _fetch_chunked(nse_obj.fetch_historical_index_data,
                           _parse_index, index="NIFTY 50")
    if nifty.empty or len(nifty) < 30:
        raise RuntimeError(f"NSE: insufficient NIFTY data ({len(nifty)} rows)")

    return frames, nifty


# Ratios a split/bonus produces (new price / old price): 1:1 bonus = 0.5,
# 1:2 split = 0.5, 1:5 = 0.2, 1:10 = 0.1, 2:1 bonus = 0.333, 3:2 = 0.4 etc.
_CA_RATIOS = [1/2, 1/3, 2/3, 1/4, 1/5, 2/5, 1/10, 1/20]


def _adjust_corporate_actions(df):
    """NSE historical prices are NOT split/bonus adjusted, so a 1:1 bonus shows
    up as a fake -50% crash. Detect one-day drops that sit on a standard split
    ratio and back-adjust all earlier prices (and volumes) so the series is
    continuous. Genuine crashes rarely land within 4% of these exact ratios."""
    d = df.copy().reset_index(drop=True)
    d["Close"] = d["Close"].astype(float)
    d["Volume"] = d["Volume"].astype(float)
    for i in range(1, len(d)):
        prev, cur = d.at[i - 1, "Close"], d.at[i, "Close"]
        if prev <= 0:
            continue
        ratio = cur / prev
        if ratio > 0.7:
            continue
        match = min(_CA_RATIOS, key=lambda r: abs(ratio / r - 1))
        if abs(ratio / match - 1) <= 0.04:
            d.loc[:i - 1, "Close"] *= match
            d.loc[:i - 1, "Volume"] /= match
            print(f"[NSE] corporate action on {d.at[i, 'Date'].date()}: "
                  f"adjusted earlier prices x{match:.3f}")
    d["Close"] = d["Close"].round(2)
    d["Volume"] = d["Volume"].round().astype(int)
    return d


def _live_prices(stock_list=None):
    stocks = stock_list or STOCKS

    # --- Try NSE direct (authoritative, no bot-blocking) ---
    try:
        frames, nifty_df = _live_prices_nse(stocks)
        common = set(nifty_df["Date"])
        for df in frames.values():
            common &= set(df["Date"])
        common = sorted(common)
        if len(common) < 30:
            raise RuntimeError(f"only {len(common)} common trading days")
        out = {}
        for tic, df in frames.items():
            d = df[df["Date"].isin(common)].sort_values("Date").reset_index(drop=True)
            d["Volume"] = d["Volume"].fillna(0).astype(int)
            out[tic] = d
        nifty = nifty_df[nifty_df["Date"].isin(common)].sort_values("Date").reset_index(drop=True)
        nifty["Volume"] = 0
        return out, nifty
    except Exception as nse_err:
        print(f"[NSE direct failed: {nse_err}] -- trying yfinance fallback")

    # --- yfinance fallback ---
    import yfinance as yf
    session = _make_yf_session()
    frames = {}
    for tic in stocks:
        yt = tic + ".NS"
        h = yf.Ticker(yt, session=session).history(
            period=LIVE_PERIOD, interval="1d", auto_adjust=True)
        if h is None or h.empty:
            raise RuntimeError(f"no data returned for {yt}")
        h = h.reset_index()[["Date", "Close", "Volume"]]
        h["Date"] = pd.to_datetime(h["Date"]).dt.tz_localize(None)
        frames[tic] = h
    nh = yf.Ticker("^NSEI", session=session).history(
        period=LIVE_PERIOD, interval="1d", auto_adjust=True)
    if nh is None or nh.empty:
        raise RuntimeError("no data returned for ^NSEI")
    nh = nh.reset_index()[["Date", "Close", "Volume"]]
    nh["Date"] = pd.to_datetime(nh["Date"]).dt.tz_localize(None)
    common = set(nh["Date"])
    for df in frames.values():
        common &= set(df["Date"])
    common = sorted(common)
    if len(common) < 30:
        raise RuntimeError(f"only {len(common)} common trading days returned -- too few")
    out = {}
    for tic, df in frames.items():
        d = df[df["Date"].isin(common)].sort_values("Date").reset_index(drop=True)
        d["Volume"] = d["Volume"].fillna(0).astype(int)
        out[tic] = d
    nifty = nh[nh["Date"].isin(common)].sort_values("Date").reset_index(drop=True)
    nifty["Volume"] = 0
    return out, nifty


def _sample_prices(stock_list=None):
    rng = np.random.default_rng(SEED)
    stocks = stock_list or STOCKS
    dates = pd.bdate_range(end="2026-06-19", periods=N_DAYS)
    out = {}
    stock_rets = {}
    for tic, (_, anchor, drift6m, sigma) in stocks.items():
        daily_drift = (1 + drift6m) ** (1 / N_DAYS) - 1
        rets = rng.normal(daily_drift, sigma, N_DAYS)
        rets[0] = 0.0
        n_events = rng.integers(2, 4)
        ev_idx = rng.choice(np.arange(25, N_DAYS - 2), size=n_events, replace=False)
        for i in ev_idx:
            rets[i] = rng.choice([-1, 1]) * rng.uniform(0.04, 0.07)
        price = 100 * np.cumprod(1 + rets)
        price *= anchor / price[-1]
        rets = np.concatenate([[0.0], np.diff(price) / price[:-1]])
        base_vol = rng.uniform(4e6, 9e6)
        noise = rng.lognormal(0, 0.35, N_DAYS)
        volume = base_vol * noise * (1 + 3 * np.abs(rets))
        for i in ev_idx:
            volume[i] *= rng.uniform(2.5, 4.0)
        volume = volume.round().astype(int)
        out[tic] = pd.DataFrame({"Date": dates, "Close": price.round(2), "Volume": volume})
        stock_rets[tic] = rets
    basket = np.mean(np.column_stack(list(stock_rets.values())), axis=1)
    nifty_ret = 0.5 * basket + rng.normal(0, 0.008, N_DAYS)
    nifty_ret[0] = 0.0
    nifty_price = 23500 * np.cumprod(1 + nifty_ret)
    nifty = pd.DataFrame({"Date": dates, "Close": nifty_price.round(2),
                          "Volume": np.zeros(N_DAYS, dtype=int)})
    return out, nifty


def load_prices(use_live=True, stock_list=None):
    """Load price data. Pass stock_list to override the current STOCKS dict."""
    if use_live:
        try:
            out, nifty = _live_prices(stock_list)
            return out, nifty, "live"
        except Exception:
            pass
    out, nifty = _sample_prices(stock_list)
    return out, nifty, "offline sample"


# ------------------------------------------------------------------ analysis

def _compute_rsi(series, period=14):
    """Wilder RSI.  Returns a Series aligned to series."""
    delta = series.diff()
    gain  = delta.clip(lower=0)
    loss  = (-delta).clip(lower=0)
    avg_g = gain.ewm(com=period - 1, min_periods=period).mean()
    avg_l = loss.ewm(com=period - 1, min_periods=period).mean()
    rs    = avg_g / avg_l.replace(0, np.nan)
    return 100 - 100 / (1 + rs)


def compute_features(df, nifty_ret):
    """Returns df with ret, beta20, resid, vavg20, vr, rstd20, z, event,
    rsi, mom5 columns added."""
    d = df.copy().reset_index(drop=True)
    d["ret"] = d["Close"].pct_change()
    d["ma20"] = d["Close"].rolling(20).mean()
    d["vavg20"] = d["Volume"].rolling(20).mean()
    d["vr"] = d["Volume"] / d["vavg20"]
    d["nret"] = nifty_ret.reset_index(drop=True)
    cov = d["ret"].rolling(20).cov(d["nret"])
    var = d["nret"].rolling(20).var()
    d["beta20"] = cov / var
    d["resid"] = d["ret"] - d["beta20"] * d["nret"]
    d["rstd20"] = d["resid"].rolling(20).std()
    d["z"] = d["resid"] / d["rstd20"]
    d["event"] = (d["z"].abs() > Z_THRESHOLD) & (d["vr"] > VOL_RATIO_THRESHOLD)
    # new signals
    d["rsi"]  = _compute_rsi(d["Close"])
    d["mom5"] = d["Close"].pct_change(5)
    return d


# ------------------------------------------------------------------ predictions
MIN_TRAIN_ROWS = 20


def _sigmoid(x):
    return 1.0 / (1.0 + np.exp(-np.clip(x, -20.0, 20.0)))


def _logistic_fit(X, y, lr=0.05, epochs=400):
    """Gradient-descent logistic regression (pure numpy, no sklearn)."""
    coefs = np.zeros(X.shape[1])
    for _ in range(epochs):
        pred = _sigmoid(X @ coefs)
        grad = X.T @ (pred - y) / len(y)
        coefs -= lr * grad
    return coefs


def forecast_next_move(d):
    """Enhanced two-model forecast.

    Model A (OLS):    predicts magnitude of tomorrow's |residual return|.
    Model B (Logit):  predicts P(tomorrow's residual return > 0) = direction prob.

    Features used:
      - avg5_abs_resid  (recent volatility regime)
      - rstd20           (20-day residual vol)
      - vr               (volume ratio)
      - z                (today's z-score; mean-reversion signal)
      - mom5_norm        (5-day price momentum / rstd20)
      - rsi_centered     (RSI - 50, oversold/overbought)

    Returns (predicted_move, direction_prob, r2, n_obs).
    predicted_move and direction_prob are None if history is insufficient.
    """
    d = d.copy()
    d["abs_resid"]      = d["resid"].abs()
    d["avg5_abs_resid"] = d["abs_resid"].rolling(5).mean()
    d["mom5_norm"]      = d["mom5"] / d["rstd20"].replace(0, np.nan)
    d["rsi_centered"]   = d["rsi"] - 50.0

    feat_cols = ["avg5_abs_resid", "rstd20", "vr", "z", "mom5_norm", "rsi_centered"]

    mag_target = d["abs_resid"].shift(-1)
    dir_target = (d["resid"].shift(-1) > 0).astype(float)

    feat = d[feat_cols]
    valid = feat.notna().all(axis=1) & mag_target.notna()
    n_obs = int(valid.sum())
    if n_obs < MIN_TRAIN_ROWS:
        return None, None, None, n_obs

    Xv = feat.loc[valid].to_numpy()
    X  = np.column_stack([np.ones(n_obs), Xv])
    ym = mag_target.loc[valid].to_numpy()
    yd = dir_target.loc[valid].to_numpy()

    # --- OLS for magnitude ---
    coefs_m, *_ = np.linalg.lstsq(X, ym, rcond=None)
    fitted       = X @ coefs_m
    ss_res = np.sum((ym - fitted) ** 2)
    ss_tot = np.sum((ym - ym.mean()) ** 2)
    r2 = float(1 - ss_res / ss_tot) if ss_tot > 0 else None

    # --- Logistic for direction ---
    coefs_d = _logistic_fit(X, yd)

    # --- Predict from last row ---
    last = feat.iloc[-1]
    if last.isna().any():
        return None, None, r2, n_obs

    x_new      = np.array([1.0, *last[feat_cols].to_numpy()])
    mag_pred   = float(max(0.0, coefs_m @ x_new))
    dir_prob   = float(_sigmoid(coefs_d @ x_new))

    return mag_pred, dir_prob, r2, n_obs


# ------------------------------------------------------------------ news sentiment

_BULLISH_WORDS = {
    "beat", "beats", "exceed", "exceeds", "exceeded", "record", "growth", "profit",
    "acquire", "acquisition", "expansion", "win", "wins", "award", "contract",
    "order", "launch", "upgrade", "upgraded", "outperform", "strong", "rise",
    "surge", "surges", "rally", "rallies", "dividend", "partnership", "positive",
    "bullish", "gain", "gains", "opportunity", "approval", "approved", "cleared",
    "breakthrough", "high", "best", "top",
}
_BEARISH_WORDS = {
    "miss", "misses", "missed", "loss", "losses", "decline", "declines", "fall",
    "falls", "drop", "drops", "fraud", "probe", "penalty", "fine", "fined", "cut",
    "cuts", "downgrade", "downgraded", "underperform", "default", "debt", "bankrupt",
    "bankruptcy", "warning", "concern", "negative", "bearish", "weak", "weakens",
    "slump", "slumps", "crash", "crashes", "scandal", "risk", "delay", "delayed",
    "reject", "rejected", "cancel", "cancelled", "layoff", "trouble", "troubles",
    "low", "worst", "down",
}


def fetch_news_sentiment(ticker: str) -> dict:
    """Fetches the latest yfinance news headlines for ``ticker`` (NSE),
    scores them with a keyword approach, and returns::

        {
            "score":     float (-1..1, avg sentiment),
            "label":     "bullish" | "bearish" | "neutral",
            "headlines": [{"title": str, "link": str, "age": str, "score": float}, ...],
            "count":     int,
        }

    Falls back to a neutral dict on any error (no internet, no news, etc.).
    """
    import time

    try:
        import yfinance as yf
        t    = yf.Ticker(ticker + ".NS")
        news = t.news or []
    except Exception:
        return {"score": 0.0, "label": "neutral", "headlines": [], "count": 0}

    total, items = 0.0, []
    now = time.time()
    for item in news[:12]:
        # yfinance may nest content under "content" key in newer versions
        if "content" in item and isinstance(item["content"], dict):
            item = item["content"]
        title = item.get("title", "").strip()
        if not title:
            continue
        link  = (item.get("canonicalUrl", {}).get("url", "")
                 or item.get("link", "")
                 or item.get("url", ""))
        ts    = (item.get("pubDate")
                 or item.get("providerPublishTime", 0))
        # pubDate can be an ISO string
        if isinstance(ts, str):
            try:
                from datetime import datetime as _dt
                ts = _dt.fromisoformat(ts.rstrip("Z")).timestamp()
            except Exception:
                ts = 0
        age_h = (now - float(ts)) / 3600 if ts else None
        age_s = ("%.0fh ago" % age_h if age_h and age_h < 48
                 else ("%.0fd ago" % (age_h / 24)) if age_h else "")

        words = title.lower().split()
        pos   = sum(1 for w in words if w in _BULLISH_WORDS)
        neg   = sum(1 for w in words if w in _BEARISH_WORDS)
        score = (pos - neg) / (pos + neg + 1)   # shrunk toward 0
        total += score
        items.append({"title": title, "link": link, "age": age_s, "score": round(score, 2)})

    if not items:
        return {"score": 0.0, "label": "neutral", "headlines": [], "count": 0}

    avg   = total / len(items)
    label = "bullish" if avg > 0.06 else ("bearish" if avg < -0.06 else "neutral")
    return {
        "score":     round(avg, 3),
        "label":     label,
        "headlines": items[:3],
        "count":     len(items),
    }


def summarize_announcement_impact(events):
    """Ranks NSE/BSE announcement categories by historical average |move|."""
    buckets = {}
    for e in events:
        cat, ret = e.get("category"), e.get("ret")
        if not cat or ret is None:
            continue
        buckets.setdefault(cat, []).append(ret)

    out = []
    for cat, rets in buckets.items():
        arr = np.array(rets, dtype=float)
        out.append({
            "category": cat,
            "count": len(arr),
            "avg_abs_move": float(np.abs(arr).mean()),
            "pct_up": float((arr > 0).mean()),
        })
    out.sort(key=lambda r: r["avg_abs_move"], reverse=True)
    return out


# ------------------------------------------------------------------ announcements

_DL_DIR = os.path.join(tempfile.gettempdir(), "nse_catalyst_scanner_cache")
os.makedirs(_DL_DIR, exist_ok=True)

_nse_client, _nse_dead = None, not _HAS_NSE
_bse_client, _bse_dead = None, not _HAS_BSE


def _nse_handle():
    global _nse_client, _nse_dead
    if _nse_dead:
        return None
    if _nse_client is None:
        try:
            _nse_client = NSE(download_folder=_DL_DIR)
        except Exception:
            _nse_dead = True
            return None
    return _nse_client


def _bse_handle():
    global _bse_client, _bse_dead
    if _bse_dead:
        return None
    if _bse_client is None:
        try:
            _bse_client = BSE(download_folder=_DL_DIR)
        except Exception:
            _bse_dead = True
            return None
    return _bse_client


_scripcode_cache = {}
_ann_cache = {}


def fetch_announcement_for_event(symbol, event_date):
    """Looks up the official NSE (primary) or BSE (fallback) corporate announcement
    nearest a flagged catalyst date. Returns (category, announcement, exchange, link);
    all None if unavailable or nothing falls in the date window."""
    if not USE_ANNOUNCEMENTS:
        return None, None, None, None
    key = (symbol, str(event_date))
    if key in _ann_cache:
        return _ann_cache[key]

    result = (None, None, None, None)
    try:
        ev_ts = pd.Timestamp(event_date)
        d_from = (ev_ts - pd.Timedelta(days=ANNOUNCE_LOOKBACK_DAYS)).to_pydatetime()
        d_to = (ev_ts + pd.Timedelta(days=ANNOUNCE_FORWARD_DAYS)).to_pydatetime()

        rows, exch = None, "NSE"
        nse_client = _nse_handle()
        if nse_client is not None:
            try:
                rows = nse_client.announcements(symbol=symbol, from_date=d_from, to_date=d_to)
            except Exception:
                rows = None

        if not rows:
            bse_client = _bse_handle()
            if bse_client is not None:
                try:
                    code = _scripcode_cache.get(symbol)
                    if code is None:
                        code = bse_client.getScripCode(symbol)
                        _scripcode_cache[symbol] = code
                    data = bse_client.announcements(from_date=d_from, to_date=d_to, scripcode=code)
                    rows = (data or {}).get("Table") or None
                    exch = "BSE"
                except Exception:
                    rows = None

        if rows:
            best, best_gap = None, None
            for row in rows:
                raw_dt = (row.get("sort_date") or row.get("an_dt") or row.get("NEWS_DT")
                          or row.get("News_dt") or row.get("DissemDT") or row.get("dt"))
                with warnings.catch_warnings():
                    warnings.simplefilter("ignore", UserWarning)
                    ann_ts = pd.to_datetime(raw_dt, errors="coerce", dayfirst=True)
                if pd.isna(ann_ts):
                    continue
                gap = abs((ev_ts - ann_ts).total_seconds())
                if best_gap is None or gap < best_gap:
                    best, best_gap = row, gap

            if best is not None:
                if exch == "NSE":
                    category = best.get("desc")
                    text = best.get("attchmntText") or category
                    link = best.get("attchmntFile")
                else:
                    category = (best.get("CATEGORYNAME") or best.get("ANNOUNCEMENT_TYPE")
                                or best.get("SUBCATNAME"))
                    text = (best.get("HEADLINE") or best.get("NEWSSUB")
                            or best.get("News_sub") or category)
                    fname = best.get("ATTACHMENTNAME") or best.get("Attachmentname")
                    link = (f"https://www.bseindia.com/xml-data/corpfiling/AttachLive/{fname}"
                            if fname else best.get("NSURL"))
                if text:
                    result = (category, text, exch, link)
    except Exception:
        pass

    _ann_cache[key] = result
    return result
