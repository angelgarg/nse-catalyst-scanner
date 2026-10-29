import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import '../state/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/format.dart';
import '../widgets/tiles.dart';

class StockDetailScreen extends ConsumerWidget {
  final String ticker;
  const StockDetailScreen({super.key, required this.ticker});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(detailProvider(ticker));
    final inList = ref.watch(watchlistProvider).contains(ticker);

    return Scaffold(
      appBar: AppBar(
        title: Text(ticker),
        actions: [
          IconButton(
            tooltip: inList ? 'Remove from watchlist' : 'Add to watchlist',
            icon: Icon(inList ? Icons.star : Icons.star_outline),
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
        loading: () => const Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Loading analysis…'),
          ]),
        ),
        error: (e, _) => ErrorRetry(
            error: e, onRetry: () => ref.invalidate(detailProvider(ticker))),
        data: (d) => _DetailBody(d: d),
      ),
    );
  }
}

class _DetailBody extends ConsumerStatefulWidget {
  final StockDetail d;
  const _DetailBody({required this.d});

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

  @override
  Widget build(BuildContext context) {
    final d = widget.d;
    final s = d.summary;
    final tt = Theme.of(context).textTheme;
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

    return ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
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
                    child: _PriceChart(d: d, days: _ranges[_range]!)),
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
                    '▲ / ▼ mark spike days (rose / fell on their own). Dashed line: 20-day average.',
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
                    hint: 'for each 1% NIFTY move'),
                _Stat('Typical yearly swing',
                    pct(d.annVol, digits: 0).replaceFirst('+', ''), null),
                _Stat('Spike days (2 yrs)', '${d.events.length}', null),
              ]),
            ),
          ),
          if (d.headlines.isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(
              child: Column(children: [
                ListTile(
                  title: const Text('Recent headlines'),
                  subtitle: Text('Keyword tone: ${d.sentimentLabel}'),
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
              style: tt.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          for (final e in events)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: EventTile(e: e, showTicker: false, onOpenLink: openUrl),
            ),
          if (events.isEmpty)
            const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No spikes in this period.')),
          if (lockedEvents > 0) ...[
            const SizedBox(height: 10),
            ProLock(
                label: '$lockedEvents older spike days (2 years of history)',
                child: const SizedBox()),
          ],
          const Disclaimer(),
        ]);
  }
}

class _TodayCard extends StatelessWidget {
  final StockSummary s;
  const _TodayCard({required this.s});

  @override
  Widget build(BuildContext context) {
    final z = s.zLast;
    final dir = (z ?? 0) >= 0 ? 'rose' : 'fell';
    final text = s.spikedToday
        ? 'Latest session: $dir more than NIFTY explains (${moveSize(z).toLowerCase()}), '
            'on ${volumeText(s.vrLast)}.'
        : 'Latest session: moved roughly in line with the market. No spike.';
    return Card(
      color: s.spikedToday ? kSpike.withValues(alpha: 0.18) : null,
      child: ListTile(
        leading: Icon(s.spikedToday ? Icons.bolt : Icons.check_circle_outline,
            color: s.spikedToday ? spikeText(context) : null),
        title: Text(text),
        trailing: IconButton(
          tooltip: 'How spikes are decided',
          icon: const Icon(Icons.info_outline),
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            showDragHandle: true,
            builder: (_) => const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 28),
              child: Text(
                'Each day we estimate how much of a stock\'s move NIFTY 50 explains, using how the two moved '
                'together over the previous 20 sessions. A day is a spike when the move left over is unusually '
                'large for that stock (more than 1.5× its normal size) and trading volume is at least 1.25× its '
                '20-day average.\n\nBig move: 1.5–2× normal · Very big: 2–3× · Rare: over 3×.',
              ),
            ),
          ),
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
  const _Stat(this.label, this.value, this.color, {this.hint});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return SizedBox(
      width: (MediaQuery.of(context).size.width - 64) / 3,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: tt.bodySmall),
        Text(value,
            style: tt.titleMedium
                ?.copyWith(color: color, fontWeight: FontWeight.w600)),
        if (hint != null) Text(hint!, style: tt.bodySmall),
      ]),
    );
  }
}

class _PriceChart extends StatelessWidget {
  final StockDetail d;
  final int days;
  const _PriceChart({required this.d, required this.days});

  @override
  Widget build(BuildContext context) {
    final n = d.close.length;
    final start = math.max(0, n - days);
    final price = <FlSpot>[];
    final ma = <FlSpot>[];
    for (var i = start; i < n; i++) {
      final c = d.close[i];
      if (c != null) price.add(FlSpot((i - start).toDouble(), c));
      final m = i < d.ma20.length ? d.ma20[i] : null;
      if (m != null) ma.add(FlSpot((i - start).toDouble(), m));
    }
    if (price.length < 2) {
      return const Center(child: Text('Not enough price history'));
    }

    final up = <int>{};
    for (var i = start; i < n; i++) {
      if (i < d.eventFlags.length && d.eventFlags[i] && i > 0) {
        final prev = d.close[i - 1], cur = d.close[i];
        if (prev != null && cur != null && cur >= prev) up.add(i - start);
      }
    }
    final grid = Theme.of(context).colorScheme.outlineVariant;
    final line = Theme.of(context).colorScheme.onSurface;

    return LineChart(LineChartData(
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
                getTitlesWidget: (v, meta) =>
                    Text(compactNum(v), style: const TextStyle(fontSize: 11)))),
      ),
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipItems: (spots) => spots.map((sp) {
            if (sp.barIndex != 0) return null;
            final idx = start + sp.x.toInt();
            return LineTooltipItem('${prettyDate(d.dates[idx])}\n${inr(sp.y)}',
                const TextStyle(color: Colors.white, fontSize: 12));
          }).toList(),
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: price,
          color: line,
          barWidth: 1.6,
          dotData: FlDotData(
            show: true,
            checkToShowDot: (spot, _) {
              final idx = start + spot.x.toInt();
              return idx < d.eventFlags.length && d.eventFlags[idx];
            },
            getDotPainter: (spot, _, __, ___) => _TrianglePainter(
              up: up.contains(spot.x.toInt()),
              color: up.contains(spot.x.toInt())
                  ? upColor(context)
                  : downColor(context),
            ),
          ),
        ),
        LineChartBarData(
          spots: ma,
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
          barWidth: 1,
          dashArray: [4, 4],
          dotData: const FlDotData(show: false),
        ),
      ],
    ));
  }
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
