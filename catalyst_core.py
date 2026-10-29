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
ANNOUNCE_LOOKBACK_DAYS = 3
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
    # Every baseline uses the 20 sessions BEFORE the day being scored (.shift(1)).
    # Including the day itself let a big move inflate its own baseline, which
    # capped |z| near 4.47 (= sqrt(20)) and understated volume spikes.
    d["vavg20"] = d["Volume"].rolling(20).mean().shift(1)
    d["vr"] = d["Volume"] / d["vavg20"]
    d["nret"] = nifty_ret.reset_index(drop=True)
    cov = d["ret"].rolling(20).cov(d["nret"])
    var = d["nret"].rolling(20).var()
    d["beta20"] = (cov / var).shift(1)
    d["resid"] = d["ret"] - d["beta20"] * d["nret"]
    d["rstd20"] = d["resid"].rolling(20).std().shift(1)
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


# Filing categories that are paperwork, never a reason for a price move.
_BLOCKED_FILINGS = (
    "trading window", "certificate under sebi", "newspaper", "link of recording",
    "audio recording", "transcript", "investor meet", "con. call", "conference call",
    "loss of share", "duplicate share", "share certificate", "registrar", "esop", "esos",
    "closure of trading", "compliance certificate", "reg. 74", "regulation 74",
)
# Catch-all categories: shown only if nothing more specific exists, and flagged routine.
_ROUTINE_FILINGS = ("updates", "general updates", "shareholders meeting", "agm", "egm",
                    "change in director", "change in management", "appointment", "resignation")


def filing_tier(category):
    """0 = specific (results, orders, M&A, ...), 1 = routine catch-all, 2 = blocked."""
    c = (category or "").strip().lower()
    if any(b in c for b in _BLOCKED_FILINGS):
        return 2
    if c in _ROUTINE_FILINGS or any(c.startswith(r) for r in _ROUTINE_FILINGS[3:]):
        return 1
    return 0


def _row_fields(row, exch):
    if exch == "NSE":
        category = row.get("desc")
        text = row.get("attchmntText") or category
        link = row.get("attchmntFile")
    else:
        category = (row.get("CATEGORYNAME") or row.get("ANNOUNCEMENT_TYPE")
                    or row.get("SUBCATNAME"))
        text = (row.get("HEADLINE") or row.get("NEWSSUB") or row.get("News_sub") or category)
        fname = row.get("ATTACHMENTNAME") or row.get("Attachmentname")
        link = (f"https://www.bseindia.com/xml-data/corpfiling/AttachLive/{fname}"
                if fname else row.get("NSURL"))
    if text:
        text = " ".join(str(text).split())
    return category, text, link


def pick_announcement(rows, ev_ts, exch):
    """Choose the filing to show for a spike on ev_ts: the most specific category
    first (blocked paperwork never), then the nearest in time. Returns
    (category, text, exchange, link, filed_date, routine) or None."""
    best_key, best = None, None
    for row in rows:
        raw_dt = (row.get("sort_date") or row.get("an_dt") or row.get("NEWS_DT")
                  or row.get("News_dt") or row.get("DissemDT") or row.get("dt"))
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", UserWarning)
            ann_ts = pd.to_datetime(raw_dt, errors="coerce", dayfirst=True)
        if pd.isna(ann_ts):
            continue
        category, text, link = _row_fields(row, exch)
        tier = filing_tier(category)
        if tier == 2 or not text:
            continue
        key = (tier, abs((ev_ts - ann_ts).total_seconds()))
        if best_key is None or key < best_key:
            best_key = key
            best = (category, text, exch, link, ann_ts.strftime("%Y-%m-%d"), tier == 1)
    return best


def fetch_announcement_for_event(symbol, event_date):
    """Looks up the official NSE (primary) or BSE (fallback) corporate announcement
    nearest a flagged catalyst date. Returns (category, announcement, exchange, link,
    filed_date, routine); all None if unavailable or nothing relevant is in the window."""
    if not USE_ANNOUNCEMENTS:
        return (None,) * 6
    key = (symbol, str(event_date))
    if key in _ann_cache:
        return _ann_cache[key]

    result = (None,) * 6
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
            picked = pick_announcement(rows, ev_ts, exch)
            if picked:
                result = picked
    except Exception:
        pass

    _ann_cache[key] = result
    return result


# ------------------------------------------------------------------ batch pipeline helpers
# Used by pipeline.py (daily CDN data build) and flask_app.py (on-demand analysis).

def _fnum(x, nd=2):
    import math
    if x is None:
        return None
    try:
        x = float(x)
    except (TypeError, ValueError):
        return None
    if math.isnan(x) or math.isinf(x):
        return None
    return round(x, nd)


def _yf_frame(h):
    """Normalise a yfinance history frame to Date/Close/Volume."""
    h = h.reset_index()
    h = h.rename(columns={h.columns[0]: "Date"})[["Date", "Close", "Volume"]]
    h["Date"] = pd.to_datetime(h["Date"]).dt.tz_localize(None).dt.normalize()
    h = h.dropna(subset=["Close"])
    h["Volume"] = h["Volume"].fillna(0).astype("int64")
    return h.sort_values("Date").reset_index(drop=True)


def fetch_prices_batch(tickers, period="2y", chunk=100):
    """Fetch daily prices for many NSE tickers at once.

    Yahoo batch download first (one request per `chunk` tickers, split-adjusted),
    then NSE direct for anything Yahoo missed. Returns (frames, nifty, failed)
    where frames maps ticker -> DataFrame[Date, Close, Volume] aligned to NIFTY dates.
    """
    import yfinance as yf

    tickers = list(dict.fromkeys(t.upper() for t in tickers))
    frames, failed = {}, []

    nifty = None
    try:
        nh = yf.Ticker("^NSEI").history(period=period, interval="1d", auto_adjust=True)
        if nh is not None and len(nh) >= 30:
            nifty = _yf_frame(nh)
    except Exception as err:
        print(f"[batch] yahoo NIFTY failed: {err}")

    for i in range(0, len(tickers), chunk):
        part = tickers[i:i + chunk]
        try:
            raw = yf.download([t + ".NS" for t in part], period=period, interval="1d",
                              auto_adjust=True, group_by="ticker", progress=False,
                              threads=True)
        except Exception as err:
            print(f"[batch] yahoo chunk {i} failed: {err}")
            continue
        for t in part:
            try:
                h = raw[t + ".NS"] if len(part) > 1 else raw
                if isinstance(h.columns, pd.MultiIndex):
                    h = h.droplevel(0, axis=1)
                h = _yf_frame(h)
                if len(h) >= 30:
                    frames[t] = h
            except Exception:
                pass

    missing = [t for t in tickers if t not in frames]
    if missing or nifty is None:
        print(f"[batch] yahoo missed {len(missing)} tickers -- trying NSE direct")
        for t in missing:
            try:
                f, n = _live_prices_nse([t])
                frames[t] = f[t]
                if nifty is None:
                    nifty = n
            except Exception as err:
                print(f"[batch] NSE {t} failed: {err}")
                failed.append(t)
    if nifty is None:
        raise RuntimeError("no NIFTY 50 data from Yahoo or NSE")

    nifty = nifty[["Date", "Close", "Volume"]].copy()
    nifty["Date"] = pd.to_datetime(nifty["Date"]).dt.normalize()
    nifty = nifty.drop_duplicates("Date").sort_values("Date").reset_index(drop=True)
    return frames, nifty, failed


def align_to_nifty(df, nifty):
    """Inner-join a stock frame onto NIFTY dates; returns (stock_df, nifty_ret)."""
    m = df.merge(nifty[["Date", "Close"]].rename(columns={"Close": "NClose"}),
                 on="Date", how="inner").sort_values("Date").reset_index(drop=True)
    nifty_ret = m["NClose"].pct_change()
    return m[["Date", "Close", "Volume"]], nifty_ret


def analyze_stock(tic, name, df, nifty_ret, with_news=True, with_announcements=True,
                  ann_since=None, ann_lookup=None):
    """Full per-stock analysis -- the single source of truth for the dashboard,
    the CDN data build and the API. Returns (stock_dict, events).

    ann_since:  only query exchange announcements for events on/after this date
                (older events keep whatever ann_lookup returns).
    ann_lookup: callable(ticker, date_str) -> announcement tuple (see
                fetch_announcement_for_event) or None, to reuse earlier lookups.
    """
    import math
    d = compute_features(df, nifty_ret)
    n = len(d)
    ev_mask = d["event"].fillna(False)

    ret_1m = d["Close"].iloc[-1] / d["Close"].iloc[-22] - 1 if n >= 22 else None
    ret_3m = d["Close"].iloc[-1] / d["Close"].iloc[-64] - 1 if n >= 64 else None
    ann_vol = d["ret"].std() * math.sqrt(252) if d["ret"].notna().any() else None
    beta_series = d["beta20"].dropna()
    idx_big = d["ret"].abs().idxmax() if d["ret"].notna().any() else None
    ev_dates = d.loc[ev_mask, "Date"]
    pred_move, pred_dir, pred_r2, pred_n = forecast_next_move(d)
    rsi_series, mom5_series = d["rsi"].dropna(), d["mom5"].dropna()
    z_last = d["z"].iloc[-1] if n else None
    vr_last = d["vr"].iloc[-1] if n else None

    stock = {
        "ticker": tic, "name": name,
        "dates": d["Date"].dt.strftime("%Y-%m-%d").tolist(),
        "close": [_fnum(v) for v in d["Close"]],
        "ma20": [_fnum(v) for v in d["ma20"]],
        "volume": [int(v) if not pd.isna(v) else 0 for v in d["Volume"]],
        "event_flags": [bool(v) for v in ev_mask],
        "last_close": _fnum(d["Close"].iloc[-1]),
        "last_date": d["Date"].iloc[-1].strftime("%Y-%m-%d"),
        "chg_1d": _fnum(d["ret"].iloc[-1], 4),
        "ret_1m": _fnum(ret_1m, 4), "ret_3m": _fnum(ret_3m, 4),
        "ann_vol": _fnum(ann_vol, 4),
        "beta": _fnum(beta_series.iloc[-1], 2) if len(beta_series) else None,
        "big_move": _fnum(d.loc[idx_big, "ret"], 4) if idx_big is not None else None,
        "cat_count": int(ev_mask.sum()),
        "last_cat_date": ev_dates.max().strftime("%Y-%m-%d") if len(ev_dates) else None,
        "z_last": _fnum(z_last, 2), "vr_last": _fnum(vr_last, 2),
        "pred_move": _fnum(pred_move, 4), "pred_dir": _fnum(pred_dir, 3),
        "pred_r2": _fnum(pred_r2, 3), "pred_n": pred_n,
        "rsi": _fnum(rsi_series.iloc[-1], 1) if len(rsi_series) else None,
        "mom5": _fnum(mom5_series.iloc[-1], 4) if len(mom5_series) else None,
        "sentiment": (fetch_news_sentiment(tic) if with_news
                      else {"score": 0.0, "label": "neutral", "headlines": [], "count": 0}),
    }

    events = []
    used_links = set()
    since = pd.Timestamp(ann_since) if ann_since is not None else None
    for _, row in d.loc[ev_mask].iterrows():
        date_s = row["Date"].strftime("%Y-%m-%d")
        ann = ann_lookup(tic, date_s) if ann_lookup else None
        if ann is None and with_announcements and (since is None or row["Date"] >= since):
            ann = fetch_announcement_for_event(tic, row["Date"])
        category, announcement, exchange, link, filed, routine = \
            (tuple(ann or ()) + (None,) * 6)[:6]
        # One filing explains at most one spike (the first one on/after it).
        if link and link in used_links:
            category = announcement = exchange = link = filed = routine = None
        elif link:
            used_links.add(link)
        events.append({
            "date": date_s, "ticker": tic, "name": name,
            "ret": _fnum(row["ret"], 4), "z": _fnum(row["z"], 2), "vr": _fnum(row["vr"], 2),
            "direction": "Up" if row["ret"] >= 0 else "Down",
            "category": category, "announcement": announcement,
            "exchange": exchange, "link": link, "filed": filed, "routine": bool(routine),
        })
    return stock, events
