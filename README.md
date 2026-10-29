# Spikewise

Spots NSE stocks that moved on **their own news**, not just with the market, and shows the official NSE/BSE filing
behind each move. Android app + free static CDN + a thin API, built and deployed automatically.

```
 GitHub Actions (daily)            GitHub Pages (CDN)              Android app (Flutter)
 pipeline.py ── 450 stocks ──▶  data/v1/*.json, privacy, terms ◀── reads data, works offline
                                                                     │ feedback / on-demand analyse
 Render (auto-deploy on push) ◀──────────────────────────────────────┘
 flask_app.py ── feedback ──▶ GitHub issues ──▶ AI agents ──▶ PRs ──▶ CI ──▶ auto-merge ──▶ deploy
```

## The rule
A day is a **spike** when the stock's residual return (its return minus rolling-20-day beta × NIFTY 50 return) is more
than 1.5σ from its own 20-day norm **and** volume is above 1.25× its 20-day average.

## Pieces
| Path | What |
|---|---|
| `catalyst_core.py` | Engine: prices (Yahoo batch, NSE fallback), features, model, announcements, headlines |
| `pipeline.py` | Daily build of `data/v1` JSON with a data-quality gate |
| `flask_app.py` | Render API: `/api/health`, `/api/v1/analyze/<t>`, `/api/v1/feedback`, legacy `/api/*` |
| `web/` | Landing, privacy policy, terms (Play Store needs these URLs) |
| `app/` | Flutter app: watchlist, spike feed, search, charts, alerts, Play Billing, feedback |
| `build_dashboard.py`, `investor_widget.py` | Original single-page dashboard and desktop widget (local use) |
| `AGENTS.md` | Rules every AI agent follows (auto-merge safety net) |

## URLs
- Data/CDN: https://angelgarg.github.io/nse-catalyst-scanner/data/v1/meta.json
- Privacy: https://angelgarg.github.io/nse-catalyst-scanner/privacy.html
- API: https://nse-catalyst-scanner.onrender.com/api/health

## Automation
| Workflow | When | Does |
|---|---|---|
| `ci` | every PR / push | pytest, flutter analyze + test, release APK compiles |
| `data` | 17:45 + 09:00 IST weekdays | rebuild data → Pages; failure keeps old data + opens `ops` issue |
| `deploy-verify` | push touching backend | waits for Render to serve the commit; reverts it if unhealthy |
| `android` | push touching `app/`, tags `v*` | signed AAB + APK; Play internal track when credentials are set |
| `monitor` | hourly | checks data freshness + API; opens `ops` issue |

*Educational statistics only. Not investment advice. Not SEBI-registered.*
