#!/usr/bin/env python3
"""
Builds a single self-contained index.html -- a static web dashboard version of the
NSE Catalyst Scanner. Same beta-adjusted residual-return catalyst rule, same
official NSE/BSE corporate-announcement lookups -- just rendered as a webpage
(Chart.js via CDN) instead of an Excel workbook.

Stock selection (in priority order):
  1. --stocks CLI flag:  python build_dashboard.py --stocks RELIANCE TCS WIPRO
  2. stocks_config.json: edit your watchlist via the desktop widget or directly
  3. Built-in defaults:  INFY, RELIANCE, HDFCBANK, TMPV, SUNPHARMA

Run:  python3 build_dashboard.py            -> uses saved watchlist
      python3 build_dashboard.py --stocks RELIANCE TCS INFY
"""
import argparse
import json
import math
from datetime import datetime, timezone

import numpy as np
import pandas as pd
from jinja2 import Template

import catalyst_core as core

OUT_DIR = "site"


def fnum(x, nd=2):
    if x is None or (isinstance(x, float) and (math.isnan(x) or math.isinf(x))):
        return None
    return round(float(x), nd)


def build(stock_override=None):
    """Build the dashboard.
    stock_override: list of NSE ticker strings (e.g. ['RELIANCE','TCS']).
    If None, uses core.STOCKS (loaded from stocks_config.json or defaults)."""

    # If user passed --stocks on CLI, validate and override the stock list
    if stock_override:
        stock_override = [s.upper().strip() for s in stock_override]
        missing = [s for s in stock_override if s not in core.STOCKS]
        if missing:
            # Try to fetch info for unknown tickers so we can use them this run
            for sym in missing:
                try:
                    name, anchor, drift6m, sigma = core.validate_ticker(sym)
                    core.STOCKS[sym] = (name, anchor, drift6m, sigma)
                    print(f"  Loaded {sym}: {name}")
                except ValueError as e:
                    print(f"  WARNING: skipping {sym} -- {e}")
        # Keep only the requested tickers (in requested order)
        active_stocks = {s: core.STOCKS[s] for s in stock_override
                         if s in core.STOCKS}
    else:
        active_stocks = core.STOCKS

    prices, nifty, mode = core.load_prices(
        use_live=True,
        stock_list=active_stocks if stock_override else None
    )
    nifty_ret = nifty["Close"].pct_change()

    stocks_ctx = []
    all_events = []
    ret_cols = {}

    for tic, (name, *_rest) in active_stocks.items():
        d = core.compute_features(prices[tic], nifty_ret)
        ret_cols[tic] = d.set_index("Date")["ret"]

        dates = d["Date"].dt.strftime("%Y-%m-%d").tolist()
        close = [fnum(v) for v in d["Close"]]
        ma20 = [fnum(v) for v in d["ma20"]]
        volume = [int(v) if not pd.isna(v) else 0 for v in d["Volume"]]
        event_flags = [bool(v) for v in d["event"].fillna(False)]

        n = len(d)
        last_close = d["Close"].iloc[-1]
        ret_1m = (d["Close"].iloc[-1] / d["Close"].iloc[-22] - 1) if n >= 22 else None
        ret_3m = (d["Close"].iloc[-1] / d["Close"].iloc[-64] - 1) if n >= 64 else None
        ann_vol = d["ret"].std() * math.sqrt(252) if d["ret"].notna().any() else None
        beta_series = d["beta20"].dropna()
        beta_last = beta_series.iloc[-1] if len(beta_series) else None
        idx_big = d["ret"].abs().idxmax() if d["ret"].notna().any() else None
        big_move = d.loc[idx_big, "ret"] if idx_big is not None else None
        cat_count = int(d["event"].fillna(False).sum())
        ev_dates = d.loc[d["event"].fillna(False), "Date"]
        last_cat_date = ev_dates.max().strftime("%Y-%m-%d") if len(ev_dates) else None
        pred_move, pred_dir, pred_r2, pred_n = core.forecast_next_move(d)

        # latest RSI and 5-day momentum for display
        rsi_series  = d["rsi"].dropna()
        rsi_last    = float(rsi_series.iloc[-1]) if len(rsi_series) else None
        mom5_series = d["mom5"].dropna()
        mom5_last   = float(mom5_series.iloc[-1]) if len(mom5_series) else None

        sentiment = core.fetch_news_sentiment(tic)

        stocks_ctx.append({
            "ticker": tic, "name": name,
            "dates": dates, "close": close, "ma20": ma20, "volume": volume,
            "event_flags": event_flags,
            "last_close": fnum(last_close), "ret_1m": fnum(ret_1m, 4),
            "ret_3m": fnum(ret_3m, 4), "ann_vol": fnum(ann_vol, 4),
            "beta": fnum(beta_last, 2), "big_move": fnum(big_move, 4),
            "cat_count": cat_count, "last_cat_date": last_cat_date,
            "pred_move": fnum(pred_move, 4), "pred_dir": fnum(pred_dir, 3),
            "pred_r2": fnum(pred_r2, 3), "pred_n": pred_n,
            "rsi": fnum(rsi_last, 1), "mom5": fnum(mom5_last, 4),
            "sentiment": sentiment,
        })

        for _, row in d.loc[d["event"].fillna(False)].iterrows():
            category, announcement, exchange, link = core.fetch_announcement_for_event(tic, row["Date"])[:4]
            all_events.append({
                "date": row["Date"].strftime("%Y-%m-%d"), "ticker": tic, "name": name,
                "ret": fnum(row["ret"], 4), "z": fnum(row["z"], 2), "vr": fnum(row["vr"], 2),
                "direction": "Up" if row["ret"] >= 0 else "Down",
                "category": category, "announcement": announcement,
                "exchange": exchange, "link": link,
            })

    all_events.sort(key=lambda e: e["date"], reverse=True)
    cat_impact = core.summarize_announcement_impact(all_events)

    ret_df = pd.DataFrame(ret_cols)
    corr = ret_df.corr()
    tickers = list(core.STOCKS.keys())
    corr_matrix = [[fnum(corr.loc[a, b], 2) for b in tickers] for a in tickers]

    assert sum(s["cat_count"] for s in stocks_ctx) == len(all_events), \
        "dashboard catalyst-day count must equal flagged-events row count"

    ann_on = core.USE_ANNOUNCEMENTS
    matched = sum(1 for e in all_events if e["announcement"])

    ctx = {
        "generated": datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC"),
        "mode": mode,
        "ann_on": ann_on,
        "ann_matched": matched,
        "ann_total": len(all_events),
        "stocks": stocks_ctx,
        "tickers": tickers,
        "corr_matrix": corr_matrix,
        "events": all_events,
        "cat_impact": cat_impact,
        "z_threshold": core.Z_THRESHOLD,
        "vol_threshold": core.VOL_RATIO_THRESHOLD,
        "min_train_rows": core.MIN_TRAIN_ROWS,
    }

    tmpl = Template(TEMPLATE)
    # Escape "</" so a headline/URL containing "</script>" can never break out of the
    # inline <script> block this gets embedded in.
    safe_json = json.dumps(ctx).replace("</", "<\\/")
    html = tmpl.render(ctx=ctx, data_json=safe_json)

    import os
    os.makedirs(OUT_DIR, exist_ok=True)
    with open(os.path.join(OUT_DIR, "index.html"), "w") as f:
        f.write(html)
    print(f"[build] wrote {OUT_DIR}/index.html  ({len(html)/1024:.0f} KB)")
    print(f"[build] data source: {mode}")
    print(f"[build] catalyst events: {len(all_events)}  (dashboard total: "
          f"{sum(s['cat_count'] for s in stocks_ctx)})  -- parity OK")
    print(f"[build] announcements: {'on' if ann_on else 'off'} -- {matched}/{len(all_events)} matched")


TEMPLATE = r"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>NSE Catalyst Scanner</title>
<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.4/dist/chart.umd.min.js"></script>
<style>
  :root{ --bg:#0b1220; --panel:#121a2c; --panel2:#0f1830; --line:#243049;
         --text:#e7ecf6; --muted:#93a1bd; --accent:#4f8cff; --up:#22c55e; --down:#ef4444; }
  *{box-sizing:border-box}
  body{margin:0;font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;
       background:var(--bg);color:var(--text);}
  header{padding:28px 32px 18px;border-bottom:1px solid var(--line);
         display:flex;justify-content:space-between;align-items:flex-end;flex-wrap:wrap;gap:12px;}
  header h1{margin:0;font-size:22px;font-weight:700;}
  header p{margin:4px 0 0;color:var(--muted);font-size:13px;}
  .badge{display:inline-block;padding:3px 9px;border-radius:20px;font-size:11px;
         font-weight:600;letter-spacing:.02em;}
  .badge.live{background:#103a23;color:#4ade80;}
  .badge.sample{background:#3a2d10;color:#fbbf24;}
  main{padding:24px 32px 60px;max-width:1320px;margin:0 auto;}
  .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:14px;margin-bottom:28px;}
  .card{background:var(--panel);border:1px solid var(--line);border-radius:12px;padding:16px 18px;}
  .card h3{margin:0 0 10px;font-size:14px;color:var(--muted);font-weight:600;}
  .card .row{display:flex;justify-content:space-between;font-size:13px;padding:3px 0;}
  .card .row span:first-child{color:var(--muted);}
  .up{color:var(--up);font-weight:600;} .down{color:var(--down);font-weight:600;}
  section{margin-bottom:36px;}
  h2{font-size:16px;border-left:3px solid var(--accent);padding-left:10px;margin:0 0 14px;}
  .stockblock{background:var(--panel);border:1px solid var(--line);border-radius:12px;
              padding:18px 20px;margin-bottom:18px;}
  .stockblock .charts{display:grid;grid-template-columns:2fr 1fr;gap:16px;margin-top:14px;}
  canvas{max-height:230px;}
  table{width:100%;border-collapse:collapse;font-size:13px;}
  th,td{padding:8px 10px;text-align:left;border-bottom:1px solid var(--line);}
  th{color:var(--muted);font-weight:600;font-size:12px;text-transform:uppercase;letter-spacing:.03em;}
  tr:hover td{background:#16203a;}
  a{color:var(--accent);text-decoration:none;} a:hover{text-decoration:underline;}
  .corr-table td{text-align:center;font-weight:600;}
  .pill{font-size:11px;padding:2px 7px;border-radius:10px;background:#1c2a4a;color:var(--muted);}
  footer{padding:20px 32px 40px;color:var(--muted);font-size:12px;max-width:1320px;margin:0 auto;
         border-top:1px solid var(--line);}
  .news-off{color:var(--muted);font-style:italic;}
  .intel-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:16px;margin-bottom:28px;}
  .intel-card{background:var(--panel);border:1px solid var(--line);border-radius:14px;padding:18px 20px;}
  .intel-header{display:flex;align-items:baseline;gap:10px;margin-bottom:12px;}
  .intel-ticker{font-size:17px;font-weight:700;color:var(--fg);}
  .intel-row{display:flex;align-items:center;gap:8px;font-size:13px;padding:2px 0;}
  .intel-label{color:var(--muted);min-width:130px;font-size:12px;}
  .intel-headline{font-size:12px;color:var(--muted);margin:4px 0 0 0;line-height:1.5;padding-left:2px;}
</style>
</head>
<body>
<header>
  <div>
    <h1>NSE Catalyst Scanner</h1>
    <p>Market-adjusted catalyst-day detection across 5 NSE stocks &middot; generated {{ ctx.generated }}</p>
  </div>
  <div style="display:flex;align-items:center;gap:12px;">
    <span class="badge {{ 'live' if ctx.mode == 'live' else 'sample' }}">
      {{ 'LIVE NSE DATA' if ctx.mode == 'live' else 'OFFLINE SAMPLE DATA' }}
    </span>
    <a href="/manage"
       style="display:inline-flex;align-items:center;gap:6px;background:#4f8cff;
              color:#fff;border:none;padding:8px 16px;border-radius:8px;
              font-size:12px;font-weight:700;text-decoration:none;letter-spacing:.04em;
              box-shadow:0 0 12px #4f8cff55;transition:background .15s,box-shadow .15s;"
       onmouseover="this.style.background='#6aa0ff';this.style.boxShadow='0 0 20px #4f8cffaa'"
       onmouseout="this.style.background='#4f8cff';this.style.boxShadow='0 0 12px #4f8cff55'">
      &#9881; Manage Stocks
    </a>
  </div>
</header>
<main>

<section>
  <h2>Dashboard</h2>
  <div class="grid">
    {% for s in ctx.stocks %}
    <div class="card">
      <h3>{{ s.ticker }} &middot; {{ s.name }}</h3>
      <div class="row"><span>Last close</span><span>&#8377;{{ s.last_close }}</span></div>
      <div class="row"><span>1M return</span>
        <span class="{{ 'up' if (s.ret_1m or 0) >= 0 else 'down' }}">
          {{ '%+.1f'|format((s.ret_1m or 0)*100) }}%</span></div>
      <div class="row"><span>3M return</span>
        <span class="{{ 'up' if (s.ret_3m or 0) >= 0 else 'down' }}">
          {{ '%+.1f'|format((s.ret_3m or 0)*100) }}%</span></div>
      <div class="row"><span>Ann. volatility</span><span>{{ '%.1f'|format((s.ann_vol or 0)*100) }}%</span></div>
      <div class="row"><span>Beta vs NIFTY</span><span>{{ s.beta }}</span></div>
      <div class="row"><span>Biggest 1-day move</span>
        <span class="{{ 'up' if (s.big_move or 0) >= 0 else 'down' }}">
          {{ '%+.1f'|format((s.big_move or 0)*100) }}%</span></div>
      <div class="row"><span>Catalyst days</span><span>{{ s.cat_count }}</span></div>
      <div class="row"><span>Last catalyst</span><span>{{ s.last_cat_date or '—' }}</span></div>
    </div>
    {% endfor %}
  </div>
</section>

<section>
  <h2>Per-stock charts</h2>
  {% for s in ctx.stocks %}
  <div class="stockblock">
    <strong>{{ s.ticker }}</strong> &middot; {{ s.name }}
    <span class="pill">{{ s.cat_count }} catalyst day{{ 's' if s.cat_count != 1 else '' }}</span>
    <div class="charts">
      <canvas id="price-{{ s.ticker }}"></canvas>
      <canvas id="vol-{{ s.ticker }}"></canvas>
    </div>
  </div>
  {% endfor %}
</section>

<section>
  <h2>Flagged catalyst events
    <span class="pill">{{ ctx.events|length }} total &middot;
      {% if ctx.ann_on %}{{ ctx.ann_matched }}/{{ ctx.ann_total }} matched to an NSE/BSE announcement{% else %}announcement lookup off{% endif %}</span>
  </h2>
  <div style="display:flex;flex-wrap:wrap;gap:8px;margin-bottom:14px;align-items:center;">
    <span style="color:var(--muted);font-size:13px;margin-right:4px;">Filter:</span>
    <button class="evt-filter-btn active" data-ticker="ALL"
      onclick="filterEvents(this)"
      style="padding:4px 14px;border-radius:20px;border:1px solid var(--accent);background:var(--accent);color:#fff;cursor:pointer;font-size:13px;font-weight:600;">
      All
    </button>
    {% for t in ctx.tickers %}
    <button class="evt-filter-btn" data-ticker="{{ t }}"
      onclick="filterEvents(this)"
      style="padding:4px 14px;border-radius:20px;border:1px solid var(--accent);background:transparent;color:var(--accent);cursor:pointer;font-size:13px;">
      {{ t }}
    </button>
    {% endfor %}
  </div>
  <table id="events-table">
    <tr><th>Date</th><th>Stock</th><th>Move</th><th>Z-score</th><th>Vol ratio</th><th>Dir</th><th>Category</th><th>Announcement</th><th>Exchange</th></tr>
    {% for e in ctx.events %}
    <tr data-ticker="{{ e.ticker }}">
      <td>{{ e.date }}</td>
      <td>{{ e.ticker }}</td>
      <td class="{{ 'up' if e.ret >= 0 else 'down' }}">{{ '%+.1f'|format(e.ret*100) }}%</td>
      <td>{{ e.z }}</td>
      <td>{{ e.vr }}x</td>
      <td class="{{ 'up' if e.direction == 'Up' else 'down' }}">{{ e.direction }}</td>
      <td>{{ e.category or '—' }}</td>
      <td>{% if e.announcement %}<a href="{{ e.link }}" target="_blank" rel="noopener">{{ e.announcement }}</a>{% else %}<span class="news-off">(no announcement match)</span>{% endif %}</td>
      <td>{{ e.exchange or '—' }}</td>
    </tr>
    {% endfor %}
  </table>
</section>

<section>
  <h2>Live Intelligence <span class="pill">news sentiment + technicals + model forecast &middot; not a trading signal</span></h2>
  <p style="color:var(--muted);font-size:13px;margin:-6px 0 18px;max-width:920px;">
    Three independent signals combined per stock.
    <strong>News sentiment</strong>: keyword score of recent Yahoo Finance headlines (live at build time).
    <strong>Technicals</strong>: RSI-14 (overbought &gt;70, oversold &lt;30) and 5-day price momentum.
    <strong>Model forecast</strong>: OLS magnitude + logistic direction probability trained on this stock's own
    trailing history (features: avg 5-day residual vol, 20-day residual vol, volume ratio, z-score, 5-day momentum,
    RSI). All in-sample &mdash; illustrative only, not investment advice.
  </p>
  <div class="intel-grid">
  {% for s in ctx.stocks %}
  {% set sent = s.sentiment %}
  {% set sent_color = '#4caf7d' if sent.label == 'bullish' else ('#e05c5c' if sent.label == 'bearish' else '#93a1bd') %}
  {% set sent_icon  = '&#9650;' if sent.label == 'bullish' else ('&#9660;' if sent.label == 'bearish' else '&#9644;') %}
  {% set rsi_zone   = 'Overbought' if s.rsi and s.rsi > 70 else ('Oversold' if s.rsi and s.rsi < 30 else 'Neutral') %}
  {% set rsi_color  = '#e05c5c' if rsi_zone == 'Overbought' else ('#4caf7d' if rsi_zone == 'Oversold' else '#93a1bd') %}
  {% set mom_color  = '#4caf7d' if s.mom5 and s.mom5 > 0 else '#e05c5c' %}
  {% set dir_pct    = (s.pred_dir * 100)|round(0)|int if s.pred_dir is not none else none %}
  {% set dir_color  = '#4caf7d' if dir_pct and dir_pct >= 55 else ('#e05c5c' if dir_pct and dir_pct <= 45 else '#93a1bd') %}
  <div class="intel-card">
    <div class="intel-header">
      <span class="intel-ticker">{{ s.ticker }}</span>
      <span style="color:var(--muted);font-size:12px;">{{ s.name }}</span>
    </div>

    <div class="intel-row">
      <span class="intel-label">News</span>
      <span style="color:{{ sent_color }};font-weight:700;">{{ sent_icon }} {{ sent.label|capitalize }}</span>
      <span style="color:var(--muted);font-size:11px;">({{ sent.count }} headlines)</span>
    </div>
    {% if sent.headlines %}
    <div class="intel-headline">
      {% set h = sent.headlines[0] %}
      {% if h.link %}<a href="{{ h.link }}" target="_blank" rel="noopener" style="color:#4f8cff;text-decoration:none;">{{ h.title }}</a>{% else %}{{ h.title }}{% endif %}
      {% if h.age %}<span style="color:var(--muted);font-size:10px;"> &mdash; {{ h.age }}</span>{% endif %}
    </div>
    {% endif %}

    <div class="intel-row" style="margin-top:10px;">
      <span class="intel-label">RSI-14</span>
      {% if s.rsi is not none %}
      <span style="color:{{ rsi_color }};font-weight:700;">{{ s.rsi }}</span>
      <span class="pill" style="background:{{ rsi_color }}22;color:{{ rsi_color }};border:1px solid {{ rsi_color }}44;">{{ rsi_zone }}</span>
      {% else %}<span style="color:var(--muted);">n/a</span>{% endif %}
    </div>

    <div class="intel-row">
      <span class="intel-label">5-day momentum</span>
      {% if s.mom5 is not none %}
      <span style="color:{{ mom_color }};font-weight:700;">{{ '%+.1f'|format(s.mom5*100) }}%</span>
      {% else %}<span style="color:var(--muted);">n/a</span>{% endif %}
    </div>

    <div class="intel-row" style="margin-top:10px;padding-top:10px;border-top:1px solid #1c2a4a;">
      <span class="intel-label">Predicted move</span>
      {% if s.pred_move is not none %}
      <span style="font-weight:700;">{{ '%.1f'|format(s.pred_move*100) }}%</span>
      {% else %}<span style="color:var(--muted);">n/a ({{ s.pred_n }}/{{ ctx.min_train_rows }} days)</span>{% endif %}
    </div>
    <div class="intel-row">
      <span class="intel-label">Direction probability</span>
      {% if dir_pct is not none %}
      <span style="color:{{ dir_color }};font-weight:700;">{{ dir_pct }}% Up</span>
      <span style="color:var(--muted);font-size:11px;">({{ 100 - dir_pct }}% Down)</span>
      {% else %}<span style="color:var(--muted);">n/a</span>{% endif %}
    </div>
    {% if s.pred_r2 is not none %}
    <div style="color:var(--muted);font-size:10px;margin-top:6px;">in-sample R&sup2; {{ s.pred_r2 }} &middot; {{ s.pred_n }} training days</div>
    {% endif %}
  </div>
  {% endfor %}
  </div>
</section>

</main>
<footer>
  Catalyst rule: residual return (return minus rolling 20-day beta &times; NIFTY return) more than
  {{ ctx.z_threshold }} standard deviations from its own trailing 20-day residual volatility,
  AND volume above {{ ctx.vol_threshold }}&times; its 20-day average.
  Not investment advice. {{ 'Live exchange prices, unverified for trading purposes.' if ctx.mode == 'live' else 'Offline run -- figures are simulated.' }}
  Announcements (when shown) are sourced directly from NSE/BSE official corporate disclosures, matched by nearest date -- not vetted or summarized by this tool.
  Predictions are an illustrative, in-sample statistical estimate of move SIZE only (not direction) and are not a trading signal.
</footer>

<script>
const DATA = {{ data_json | safe }};
const palette = { close: '#4f8cff', ma20: '#93a1bd', vol: '#2d3a5c', event: '#ef4444' };

DATA.stocks.forEach(s => {
  const pointBg = s.event_flags.map(e => e ? palette.event : 'rgba(0,0,0,0)');
  const pointR  = s.event_flags.map(e => e ? 4 : 0);

  new Chart(document.getElementById('price-' + s.ticker), {
    type: 'line',
    data: { labels: s.dates, datasets: [
      { label: 'Close', data: s.close, borderColor: palette.close, borderWidth: 1.5,
        pointBackgroundColor: pointBg, pointBorderColor: pointBg, pointRadius: pointR, tension: 0.15 },
      { label: 'MA20', data: s.ma20, borderColor: palette.ma20, borderWidth: 1, borderDash: [3,3],
        pointRadius: 0, tension: 0.15 },
    ]},
    options: { responsive: true, maintainAspectRatio: false, animation: false,
      interaction: { intersect: false, mode: 'index' },
      plugins: { legend: { labels: { color: '#93a1bd', font: { size: 10 } } } },
      scales: { x: { ticks: { color: '#93a1bd', maxTicksLimit: 8, font: { size: 9 } }, grid: { color: '#1c2a4a' } },
                y: { ticks: { color: '#93a1bd', font: { size: 9 } }, grid: { color: '#1c2a4a' } } } }
  });

  const volColors = s.event_flags.map(e => e ? palette.event : palette.vol);
  new Chart(document.getElementById('vol-' + s.ticker), {
    type: 'bar',
    data: { labels: s.dates, datasets: [{ label: 'Volume', data: s.volume, backgroundColor: volColors }] },
    options: { responsive: true, maintainAspectRatio: false, animation: false,
      plugins: { legend: { display: false } },
      scales: { x: { ticks: { display: false }, grid: { display: false } },
                y: { ticks: { color: '#93a1bd', font: { size: 9 } }, grid: { color: '#1c2a4a' } } } }
  });
});

function filterEvents(btn) {
  const ticker = btn.getAttribute('data-ticker');
  document.querySelectorAll('.evt-filter-btn').forEach(b => {
    const active = b === btn;
    b.style.background = active ? 'var(--accent)' : 'transparent';
    b.style.color = active ? '#fff' : 'var(--accent)';
    b.style.fontWeight = active ? '600' : 'normal';
  });
  document.querySelectorAll('#events-table tr[data-ticker]').forEach(row => {
    row.style.display = (ticker === 'ALL' || row.getAttribute('data-ticker') === ticker)
      ? '' : 'none';
  });
}
</script>
</body>
</html>
"""

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Build the NSE Catalyst Scanner web dashboard."
    )
    parser.add_argument(
        "--stocks", nargs="+", metavar="TICKER",
        help="NSE ticker symbols to analyse (e.g. --stocks RELIANCE TCS WIPRO). "
             "Overrides stocks_config.json for this run only."
    )
    args = parser.parse_args()
    build(stock_override=args.stocks)
