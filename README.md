# NSE Catalyst Scanner — Web Dashboard

A live, mobile-friendly web app that scans NSE stocks for **catalyst days** — days when a stock moved significantly *beyond* what the broad market (NIFTY 50) was doing, backed by a volume spike. Deployed on PythonAnywhere so it works from any phone or laptop with no login required.

## What it does

- Strips out market-wide moves using a **rolling beta** against NIFTY 50
- Flags residual moves that are statistically abnormal (z-score) AND backed by volume
- Matches each flag to the official **NSE/BSE corporate announcement** nearest that date
- Shows per-stock **Live Intelligence**: RSI, 5-day momentum, news sentiment, and a next-day move prediction
- Lets you **manage your watchlist** from the web — add/remove any of 450+ NSE stocks

## Project files

| File | Purpose |
|------|---------|
| `catalyst_core.py` | Shared analysis engine — price loading, beta/residual/z-score, RSI, momentum, logistic direction model, NSE/BSE announcement lookup, news sentiment |
| `build_dashboard.py` | Generates `site/index.html` from fresh data. Run this to rebuild. |
| `flask_app.py` | Flask web server for PythonAnywhere. Routes: `/`, `/manage`, `/search`, `/add`, `/remove`, `/rebuild` |
| `stocks_config.json` | Your watchlist — auto-updated when you add/remove stocks via `/manage` |
| `investor_widget.py` / `.pyw` | Optional local desktop popup ("Investor's Cheat Sheet") — runs on Windows, no browser needed |
| `requirements.txt` | Python dependencies |
| `site/index.html` | The generated dashboard HTML (rebuilt by `build_dashboard.py`) |

## Live deployment (PythonAnywhere)

The app runs at: **`https://angelgarg18.pythonanywhere.com`**

- `/` — main dashboard
- `/manage` — add/remove stocks, trigger rebuild
- `/rebuild` — force rebuild with fresh NSE data

Data is fetched live from NSE using the `nse` library (bypasses Yahoo Finance IP blocking on server). The page header shows a **LIVE NSE DATA** or **OFFLINE SAMPLE DATA** badge.

---

## Setup guide — fresh installation

See **`SETUP_GUIDE.md`** in this folder for complete step-by-step instructions to deploy this on a new machine or PythonAnywhere account.

---

## Predictions & Live Intelligence

Each stock card on the dashboard shows:

| Field | What it is |
|-------|-----------|
| **Predicted move** | Next-day \|residual return\| magnitude — OLS regression on avg5 residual, 20d stdev, volume ratio, momentum, RSI |
| **Direction probability** | P(Up tomorrow) from a pure-numpy logistic regression on the same features |
| **RSI-14** | Wilder RSI — below 30 = oversold, above 70 = overbought |
| **5d momentum** | 5-day price change % |
| **News sentiment** | Keyword scoring of latest yfinance headlines (Bullish / Bearish / Neutral) |

All predictions are illustrative in-sample statistics — not a trading signal and not investment advice.

## Catalyst rule (same as Excel version)

A day is **flagged** when both of the following hold:
1. **|residual return| z-score ≥ 2.0** — the stock's beta-adjusted move is at least 2 standard deviations above its own 20-day rolling norm
2. **Volume ratio ≥ 1.5×** — traded volume is at least 1.5× the 20-day average

Residual return = actual daily return − (rolling beta × NIFTY daily return).

## Desktop widget

Double-click `investor_widget.pyw` for an always-on-top popup with two tabs:
- **Principles** — eight value-investing one-liners tied to what this project measures
- **Quick Take** — live rule-based read on any tracked stock (beta, volatility, predicted move, recent catalyst flag)
- **Manage Stocks** — add/remove stocks from your local watchlist

No extra install needed — just Python with the packages in `requirements.txt`.

---

*Not investment advice. Live figures are real exchange prices but unverified for trading. Offline figures are simulated. Announcements are from NSE/BSE official disclosures, unvetted. Predictions are illustrative in-sample estimates of move size only.*
