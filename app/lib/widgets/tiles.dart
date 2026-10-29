import 'package:flutter/material.dart';

import '../data/models.dart';
import '../screens/stock_detail_screen.dart';
import '../theme.dart';
import 'format.dart';
import 'sparkline.dart';

void openStock(BuildContext context, String ticker) => Navigator.of(context)
    .push(MaterialPageRoute(builder: (_) => StockDetailScreen(ticker: ticker)));

class StockTile extends StatelessWidget {
  final StockSummary s;
  const StockTile({super.key, required this.s});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final c = signColor(context, s.chg1d);
    final status = s.spikedToday
        ? '${moveSize(s.zLast)} on its own · ${volumeText(s.vrLast)}'
        : 'Moved with the market today';
    return Card(
      child: Semantics(
        label:
            '${s.ticker}, ${s.name}, ${inr(s.lastClose)}, ${pct(s.chg1d, digits: 2)} today'
            '${s.spikedToday ? ', spiked today' : ''}',
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => openStock(context, s.ticker),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Row(children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.ticker,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      Text(s.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.bodySmall?.copyWith(color: muted)),
                      const SizedBox(height: 4),
                      Row(children: [
                        if (s.spikedToday) ...[
                          const SpikeBadge(),
                          const SizedBox(width: 6)
                        ],
                        Flexible(
                          child: Text(status,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tt.bodySmall?.copyWith(
                                  color: s.spikedToday ? null : muted)),
                        ),
                      ]),
                    ]),
              ),
              ExcludeSemantics(child: Sparkline(values: s.spark, color: c)),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(inr(s.lastClose),
                    style: tt.titleSmall?.copyWith(fontFeatures: tabular)),
                Text(pct(s.chg1d, digits: 2),
                    style: tt.bodySmall
                        ?.copyWith(color: c, fontFeatures: tabular)),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

class SpikeBadge extends StatelessWidget {
  const SpikeBadge({super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
            color: kSpike, borderRadius: BorderRadius.circular(6)),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.bolt, size: 12, color: kOnSpike),
          Text('SPIKE',
              style: TextStyle(
                  color: kOnSpike,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5)),
        ]),
      );
}

class EventTile extends StatelessWidget {
  final SpikeEvent e;
  final bool showTicker;
  final void Function(String url)? onOpenLink;
  const EventTile(
      {super.key, required this.e, this.showTicker = true, this.onOpenLink});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final c = e.up ? upColor(context) : downColor(context);
    final verb = e.up ? 'rose' : 'fell';
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: showTicker ? () => openStock(context, e.ticker) : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(prettyDate(e.date),
                style: tt.labelSmall?.copyWith(color: muted)),
            const SizedBox(height: 2),
            Row(children: [
              Icon(e.up ? Icons.arrow_upward : Icons.arrow_downward,
                  color: c, size: 18, semanticLabel: e.up ? 'Up' : 'Down'),
              const SizedBox(width: 6),
              if (showTicker) ...[
                Flexible(
                  child: Text(e.ticker,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 8),
              ],
              Text(pct(e.ret, digits: 2),
                  style: tt.titleSmall?.copyWith(
                      color: c,
                      fontWeight: FontWeight.w700,
                      fontFeatures: tabular)),
            ]),
            const SizedBox(height: 4),
            Text(
                '${moveSize(e.z)}: $verb more than NIFTY explains · ${volumeText(e.vr)}',
                style: tt.bodySmall),
            if (e.announcement != null) ...[
              const SizedBox(height: 8),
              Text(
                [
                  e.routine
                      ? 'Routine filing near this date'
                      : 'Filing near this date',
                  if (e.exchange != null)
                    '(${e.exchange}${e.filedRelative != null ? ', ${e.filedRelative}' : ''})',
                ].join(' '),
                style: tt.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: e.routine ? muted : null),
              ),
              if (e.category != null)
                Text(e.category!, style: tt.bodySmall?.copyWith(color: muted)),
              Text(e.announcement!,
                  maxLines: e.routine ? 2 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodySmall),
              Text('May not be the cause of the move.',
                  style: tt.labelSmall?.copyWith(color: muted)),
              if (e.link != null && onOpenLink != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    onPressed: () => onOpenLink!(e.link!),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('Read the filing'),
                  ),
                ),
            ] else ...[
              const SizedBox(height: 6),
              Text('No company filing found near this date.',
                  style: tt.bodySmall
                      ?.copyWith(fontStyle: FontStyle.italic, color: muted)),
            ],
          ]),
        ),
      ),
    );
  }
}
