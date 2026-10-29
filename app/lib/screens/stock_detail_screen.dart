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
              } else if (await wl.add(ticker) == AddResult.limit && context.mounted) {
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
        error: (e, _) => ErrorRetry(error: e, onRetry: () => ref.invalidate(detailProvider(ticker))),
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
  static const _ranges = {'1M': 22, '3M': 64, '6M': 126, '1Y': 252, '2Y': 100000};
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
      final cutoff =
          last.subtract(Duration(days: cfg.freeHistoryDays)).toIso8601String().substring(0, 10);
      events = d.events.where((e) => e.date.compareTo(cutoff) >= 0).toList();
      lockedEvents = d.events.length - events.length;
    }

    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
      Text(s.name, style: tt.titleMedium),
      const SizedBox(height: 4),
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(inr(s.lastClose), style: tt.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(width: 10),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(pct(s.chg1d, digits: 2),
              style: tt.titleMedium?.copyWith(color: signColor(context, s.chg1d))),
        ),
      ]),
      Text('Close on ${prettyDate(s.lastDate)}${d.onDemand ? ' · analysed on demand' : ''}',
          style: tt.bodySmall),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
          child: Column(children: [
            SizedBox(height: 220, child: _PriceChart(d: d, days: _ranges[_range]!)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [for (final r in _ranges.keys) ButtonSegment(value: r, label: Text(r))],
              selected: {_range},
              onSelectionChanged: (v) => setState(() => _range = v.first),
            ),
            const SizedBox(height: 4),
            Text('Dots mark spike days: green up, red down. Dashed line is the 20-day average.',
                style: tt.bodySmall, textAlign: TextAlign.center),
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
            _Stat('5-day momentum', pct(d.mom5), signColor(context, d.mom5)),
            _Stat('RSI (14)', num2(s.rsi, digits: 0), null,
                hint: s.rsi == null ? null : (s.rsi! > 70 ? 'overbought' : s.rsi! < 30 ? 'oversold' : 'neutral')),
            _Stat('Beta vs NIFTY', num2(d.beta), null),
            _Stat('Volatility (yr)', pct(d.annVol, digits: 0).replaceFirst('+', ''), null),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      ProLock(label: 'Model view: expected move size and up-day tendency', child: _ModelCard(d: d)),
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
                title: Text(h.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(h.age),
                trailing: const Icon(Icons.open_in_new, size: 18),
                onTap: h.link.isEmpty ? null : () => openUrl(h.link),
              ),
          ]),
        ),
      ],
      const SizedBox(height: 20),
      Text('Spike days (${d.events.length} in 2 years)', style: tt.titleMedium),
      const SizedBox(height: 4),
      for (final e in events)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: EventTile(e: e, showTicker: false, onOpenLink: openUrl),
        ),
      if (events.isEmpty)
        const Padding(padding: EdgeInsets.all(16), child: Text('No spikes in this period.')),
      if (lockedEvents > 0) ...[
        const SizedBox(height: 10),
        ProLock(label: '$lockedEvents older spike days with filings', child: const SizedBox()),
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
    final z = s.zLast?.abs();
    final text = s.spikedToday
        ? 'Spike today: moved ${num2(z, digits: 1)}σ beyond what NIFTY explains, on ${num2(s.vrLast, digits: 1)}× normal volume.'
        : 'Latest session: ${num2(z, digits: 1)}σ beyond the market on ${num2(s.vrLast, digits: 1)}× normal volume. '
            'A spike needs both above 1.5σ and 1.25×.';
    return Card(
      color: s.spikedToday ? kBrand.withValues(alpha: 0.15) : null,
      child: ListTile(
        leading: Icon(s.spikedToday ? Icons.bolt : Icons.info_outline, color: s.spikedToday ? kBrand : null),
        title: Text(text),
      ),
    );
  }
}

class _ModelCard extends StatelessWidget {
  final StockDetail d;
  const _ModelCard({required this.d});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Model view', style: tt.titleMedium),
          const SizedBox(height: 10),
          Wrap(runSpacing: 14, children: [
            _Stat('Expected move size', pct(d.predMove, digits: 2).replaceFirst('+', '±'), null),
            _Stat('Up-day tendency', d.predDir == null ? '—' : '${(d.predDir! * 100).round()}%', null),
            _Stat('Fit (R²)', num2(d.predR2), null, hint: '${d.predN} days'),
          ]),
          const SizedBox(height: 10),
          Text(
            'In-sample statistics fitted on this stock\'s own history. A low R² means the model explains '
            'little. Treat this as context, not a forecast or a signal to trade.',
            style: tt.bodySmall,
          ),
        ]),
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
        Text(value, style: tt.titleMedium?.copyWith(color: color, fontWeight: FontWeight.w600)),
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
    if (price.length < 2) return const Center(child: Text('Not enough price history'));

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
          drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: grid, strokeWidth: 0.5)),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(),
        rightTitles: const AxisTitles(),
        bottomTitles: const AxisTitles(),
        leftTitles: AxisTitles(
            sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 48,
                getTitlesWidget: (v, meta) => Text(v.toStringAsFixed(0), style: const TextStyle(fontSize: 10)))),
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
            getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
              radius: 3.5,
              color: up.contains(spot.x.toInt()) ? kUp : kDown,
              strokeWidth: 0,
            ),
          ),
        ),
        LineChartBarData(
          spots: ma,
          color: kBrand.withValues(alpha: 0.7),
          barWidth: 1,
          dashArray: [4, 4],
          dotData: const FlDotData(show: false),
        ),
      ],
    ));
  }
}
