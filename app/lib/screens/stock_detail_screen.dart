import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import '../learn/explainers.dart';
import '../motion.dart';
import '../state/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/format.dart';
import '../widgets/spike_mark.dart';
import '../widgets/tiles.dart';

class StockDetailScreen extends ConsumerWidget {
  final String ticker;

  /// Spike date to scroll to and highlight on open (e.g. from a notification).
  final String? focusDate;
  const StockDetailScreen({super.key, required this.ticker, this.focusDate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(detailProvider(ticker));
    final inList = ref.watch(watchlistProvider).contains(ticker);

    return Scaffold(
      appBar: AppBar(
        title: Hero(
          tag: 'ticker-$ticker',
          child: Material(
              type: MaterialType.transparency,
              child:
                  Text(ticker, style: Theme.of(context).textTheme.titleLarge)),
        ),
        actions: [
          IconButton(
            tooltip: inList ? 'Remove from watchlist' : 'Add to watchlist',
            icon: AnimatedSwitcher(
              duration: Motion.of(context, Motion.micro),
              transitionBuilder: (c, a) => ScaleTransition(
                  scale: Tween(begin: 0.8, end: 1.0).animate(a), child: c),
              child: Icon(inList ? Icons.star : Icons.star_outline,
                  key: ValueKey(inList)),
            ),
            onPressed: () async {
              final wl = ref.read(watchlistProvider.notifier);
              if (inList) {
                await wl.remove(ticker);
              } else if (await wl.add(ticker) == AddResult.limit &&
                  context.mounted) {
                openPaywall(context);
              }
            },
          ),
        ],
      ),
      body: detail.when(
        loading: () =>
            const Center(child: SpikeMarkLoader(label: 'Loading analysis…')),
        error: (e, _) => ErrorRetry(
            error: e, onRetry: () => ref.invalidate(detailProvider(ticker))),
        data: (d) => _DetailBody(d: d, focusDate: focusDate),
      ),
    );
  }
}

class _DetailBody extends ConsumerStatefulWidget {
  final StockDetail d;
  final String? focusDate;
  const _DetailBody({required this.d, this.focusDate});

  @override
  ConsumerState<_DetailBody> createState() => _DetailBodyState();
}

class _DetailBodyState extends ConsumerState<_DetailBody> {
  static const _ranges = {
    '1M': 22,
    '3M': 64,
    '6M': 126,
    '1Y': 252,
    '2Y': 100000
  };
  String _range = '6M';
  String? _focus;
  final _keys = <String, GlobalKey>{};
  final _lockKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.focusDate != null) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _jumpTo(widget.focusDate!));
    }
  }

  Future<void> _jumpTo(String date) async {
    final ctx = (_keys[date] ?? _lockKey).currentContext;
    if (ctx == null) return;
    setState(() => _focus = _keys.containsKey(date) ? date : null);
    await Scrollable.ensureVisible(ctx,
        duration: Motion.of(context, const Duration(milliseconds: 400)),
        curve: Curves.easeInOutCubic,
        alignment: 0.15);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (mounted && _focus == date) setState(() => _focus = null);
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.d;
    final s = d.summary;
    final tt = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final pro = ref.watch(proProvider);
    final cfg = ref.watch(configProvider).valueOrNull ?? const RemoteConfig();

    var events = d.events;
    var lockedEvents = 0;
    if (!pro && d.dates.isNotEmpty) {
      final last = DateTime.parse(d.dates.last);
      final cutoff = last
          .subtract(Duration(days: cfg.freeHistoryDays))
          .toIso8601String()
          .substring(0, 10);
      events = d.events.where((e) => e.date.compareTo(cutoff) >= 0).toList();
      lockedEvents = d.events.length - events.length;
    }
    for (final e in events) {
      _keys.putIfAbsent(e.date, GlobalKey.new);
    }

    // Bounded content (≤ ~60 spikes), so a non-lazy column keeps every card's
    // key mounted for scroll-to from the chart.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(s.name, style: tt.titleMedium, maxLines: 2),
        const SizedBox(height: 4),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(inr(s.lastClose),
              style: tt.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700, fontFeatures: tabular)),
          const SizedBox(width: 10),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(pct(s.chg1d, digits: 2),
                style: tt.titleMedium
                    ?.copyWith(color: signColor(context, s.chg1d))),
          ),
        ]),
        Text(
            'Closing price · ${prettyDate(s.lastDate)}${d.onDemand ? ' · analysed on demand' : ''}',
            style: tt.bodySmall),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
            child: Column(children: [
              SizedBox(
                height: 220,
                child: _PriceChart(
                    d: d, days: _ranges[_range]!, onSpikeTap: _jumpTo),
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  for (final r in _ranges.keys)
                    ButtonSegment(value: r, label: Text(r))
                ],
                selected: {_range},
                onSelectionChanged: (v) => setState(() => _range = v.first),
              ),
              const SizedBox(height: 4),
              Text(
                  '▲ / ▼ spike days (did better / worse than NIFTY explains). Tap one to see that day. '
                  'Dashed line: 20-day average.',
                  style: tt.bodySmall,
                  textAlign: TextAlign.center),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        _TodayCard(s: s),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(runSpacing: 14, children: [
              _Stat('1 month', pct(s.ret1m), signColor(context, s.ret1m)),
              _Stat('3 months', pct(s.ret3m), signColor(context, s.ret3m)),
              _Stat('1 week', pct(d.mom5), signColor(context, d.mom5)),
              _Stat('Moves with NIFTY',
                  d.beta == null ? '—' : '${num2(d.beta)}×', null,
                  hint: 'for each 1% NIFTY move', explainer: 'beta'),
              _Stat('Typical yearly swing',
                  pct(d.annVol, digits: 0).replaceFirst('+', ''), null),
              _Stat('Spike days (2 yrs)', '${d.events.length}', null,
                  explainer: 'spike_rule'),
            ]),
          ),
        ),
        if (d.headlines.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            child: Column(children: [
              const ListTile(
                title: Text('Recent headlines'),
                subtitle:
                    Text('From public news feeds. Not checked by Spikewise.'),
              ),
              for (final h in d.headlines)
                ListTile(
                  dense: true,
                  title: Text(h.title,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(h.age),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: h.link.isEmpty ? null : () => openUrl(h.link),
                ),
            ]),
          ),
        ],
        const SizedBox(height: 20),
        Text(
            pro || lockedEvents == 0
                ? 'Spike days (${d.events.length} in 2 years)'
                : 'Spike days: ${events.length} in last ${cfg.freeHistoryDays} days',
            style: tt.titleMedium),
        Text(
            'Company filings are matched for recent spikes only (last 30 days).',
            style: tt.bodySmall?.copyWith(color: muted)),
        for (final e in events)
          Padding(
            key: _keys[e.date],
            padding: const EdgeInsets.only(top: 10),
            child: EventTile(
                e: e,
                showTicker: false,
                onOpenLink: openUrl,
                highlight: _focus == e.date),
          ),
        if (events.isEmpty)
          const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                  'No spike days in this period. This stock mostly moved with the market.')),
        if (lockedEvents > 0) ...[
          const SizedBox(height: 10),
          ProLock(
              key: _lockKey,
              label: '$lockedEvents older spike days (2 years of history)',
              child: const SizedBox()),
        ],
        const Disclaimer(),
      ]),
    );
  }
}

class _TodayCard extends StatelessWidget {
  final StockSummary s;
  const _TodayCard({required this.s});

  @override
  Widget build(BuildContext context) {
    final z = s.zLast;
    final text = s.spikedToday
        ? 'Latest session: ${vsMarket(z)} (${moveSize(z).toLowerCase()}), on ${volumeText(s.vrLast)}.'
        : 'Latest session: moved roughly in line with the market. No spike.';
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: s.spikedToday ? 0.18 : 0),
      duration: Motion.of(context, Motion.medium),
      builder: (_, a, child) => Card(
          color: s.spikedToday ? kSpike.withValues(alpha: a) : null,
          child: child),
      child: ListTile(
        leading: Icon(s.spikedToday ? Icons.bolt : Icons.check_circle_outline,
            color: s.spikedToday ? spikeText(context) : null),
        title: Text(text),
        trailing: IconButton(
          tooltip: 'How spikes are decided',
          icon: const Icon(Icons.info_outline),
          onPressed: () => showExplainer(context, 'spike_rule'),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  final String? hint;
  final String? explainer;
  const _Stat(this.label, this.value, this.color, {this.hint, this.explainer});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final body =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Flexible(child: Text(label, style: tt.bodySmall)),
        if (explainer != null)
          const Padding(
              padding: EdgeInsets.only(left: 2),
              child: Icon(Icons.help_outline, size: 12)),
      ]),
      Text(value,
          style: tt.titleMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
              fontFeatures: tabular)),
      if (hint != null) Text(hint!, style: tt.bodySmall),
    ]);
    return LayoutBuilder(builder: (context, _) {
      final w = (MediaQuery.sizeOf(context).width - 64) / 3;
      return SizedBox(
        width: w,
        child: explainer == null
            ? body
            : InkWell(
                onTap: () => showExplainer(context, explainer!), child: body),
      );
    });
  }
}

class _PriceChart extends StatefulWidget {
  final StockDetail d;
  final int days;
  final void Function(String date) onSpikeTap;
  const _PriceChart(
      {required this.d, required this.days, required this.onSpikeTap});

  @override
  State<_PriceChart> createState() => _PriceChartState();
}

class _PriceChartState extends State<_PriceChart> {
  late final List<FlSpot> _price, _ma;
  late final Map<int, bool> _spikeUp; // index -> did better than NIFTY explains

  @override
  void initState() {
    super.initState();
    final d = widget.d;
    // Full series once; ranges only change minX/maxX so switching zooms smoothly.
    _price = [
      for (var i = 0; i < d.close.length; i++)
        if (d.close[i] != null) FlSpot(i.toDouble(), d.close[i]!)
    ];
    _ma = [
      for (var i = 0; i < d.ma20.length; i++)
        if (d.ma20[i] != null) FlSpot(i.toDouble(), d.ma20[i]!)
    ];
    final zByDate = {for (final e in d.events) e.date: e.z ?? 0};
    _spikeUp = {
      for (var i = 0; i < d.eventFlags.length; i++)
        if (d.eventFlags[i] && i < d.dates.length)
          i: (zByDate[d.dates[i]] ?? 0) >= 0
    };
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.d;
    final n = d.close.length;
    if (_price.length < 2) {
      return const Center(child: Text('Not enough price history'));
    }
    final start = math.max(0, n - widget.days);
    var lo = double.infinity, hi = -double.infinity;
    for (final s in [..._price, ..._ma]) {
      if (s.x >= start) {
        lo = math.min(lo, s.y);
        hi = math.max(hi, s.y);
      }
    }
    final pad = (hi - lo) * 0.06 + 0.01;
    final grid = Theme.of(context).colorScheme.outlineVariant;
    final line = Theme.of(context).colorScheme.onSurface;

    final chart = LineChart(
      duration: Motion.of(context, Motion.medium),
      curve: Motion.emphasized,
      LineChartData(
        minX: start.toDouble(),
        maxX: (n - 1).toDouble(),
        minY: lo - pad,
        maxY: hi + pad,
        clipData: const FlClipData.all(),
        gridData: FlGridData(
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: grid, strokeWidth: 0.5)),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          bottomTitles: const AxisTitles(),
          leftTitles: AxisTitles(
              sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 48,
                  getTitlesWidget: (v, meta) => Text(compactNum(v),
                      style: const TextStyle(fontSize: 11)))),
        ),
        lineTouchData: LineTouchData(
          touchSpotThreshold: 16,
          touchCallback: (event, resp) {
            if (event is! FlTapUpEvent) return;
            final spot =
                resp?.lineBarSpots?.where((s) => s.barIndex == 0).firstOrNull;
            final idx = spot?.x.toInt();
            if (idx != null && _spikeUp.containsKey(idx)) {
              widget.onSpikeTap(d.dates[idx]);
            }
          },
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots.map((sp) {
              if (sp.barIndex != 0) return null;
              final idx = sp.x.toInt();
              final tag =
                  _spikeUp.containsKey(idx) ? '\nSpike day · tap to see' : '';
              return LineTooltipItem(
                  '${prettyDate(d.dates[idx])}\n${inr(sp.y)}$tag',
                  const TextStyle(color: Colors.white, fontSize: 12));
            }).toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: _price,
            color: line,
            barWidth: 1.6,
            dotData: FlDotData(
              show: true,
              checkToShowDot: (spot, _) =>
                  spot.x >= start && _spikeUp.containsKey(spot.x.toInt()),
              getDotPainter: (spot, _, __, ___) {
                final up = _spikeUp[spot.x.toInt()] ?? true;
                return _TrianglePainter(
                    up: up, color: up ? upColor(context) : downColor(context));
              },
            ),
          ),
          LineChartBarData(
            spots: _ma,
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
            barWidth: 1,
            dashArray: [4, 4],
            dotData: const FlDotData(show: false),
          ),
        ],
      ),
    );

    // One-time left-to-right reveal on open; the y-axis labels stay visible.
    return RepaintBoundary(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: Motion.reduced(context) ? 1 : 0, end: 1),
        duration: Motion.of(context, Motion.long),
        curve: Motion.curve,
        builder: (_, t, child) =>
            ClipRect(clipper: _RevealClipper(t), child: child),
        child: Semantics(
          label:
              'Price chart, ${widget.days > n ? 'all' : widget.days} trading days, '
              '${_spikeUp.keys.where((i) => i >= start).length} spike days marked',
          child: chart,
        ),
      ),
    );
  }
}

class _RevealClipper extends CustomClipper<Rect> {
  final double t;
  _RevealClipper(this.t);

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, 48 + (size.width - 48) * t, size.height);

  @override
  bool shouldReclip(_RevealClipper old) => old.t != t;
}

/// Spike markers: ▲ for up, ▼ for down, so the meaning doesn't depend on colour.
class _TrianglePainter extends FlDotPainter {
  final bool up;
  final Color color;
  _TrianglePainter({required this.up, required this.color});

  static const double _r = 5;

  @override
  void draw(Canvas canvas, FlSpot spot, Offset offsetInCanvas) {
    final c = offsetInCanvas;
    final path = up
        ? (Path()
          ..moveTo(c.dx, c.dy - _r)
          ..lineTo(c.dx + _r, c.dy + _r * 0.8)
          ..lineTo(c.dx - _r, c.dy + _r * 0.8))
        : (Path()
          ..moveTo(c.dx, c.dy + _r)
          ..lineTo(c.dx + _r, c.dy - _r * 0.8)
          ..lineTo(c.dx - _r, c.dy - _r * 0.8));
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  Size getSize(FlSpot spot) => const Size(_r * 2, _r * 2);

  @override
  Color get mainColor => color;

  @override
  FlDotPainter lerp(FlDotPainter a, FlDotPainter b, double t) => b;

  @override
  List<Object?> get props => [up, color];
}
