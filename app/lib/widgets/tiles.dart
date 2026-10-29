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
  final Widget? trailing;
  const StockTile({super.key, required this.s, this.trailing});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final c = signColor(context, s.chg1d);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => openStock(context, s.ticker),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(s.ticker, style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  if (s.spikedToday) ...[const SizedBox(width: 8), const SpikeBadge()],
                ]),
                Text(s.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodySmall
                        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                const SizedBox(height: 4),
                Text(
                  s.lastCatDate == null
                      ? 'No spikes in 2 years'
                      : '${s.catCount} spikes · last ${prettyDate(s.lastCatDate)}',
                  style: tt.bodySmall,
                ),
              ]),
            ),
            Sparkline(values: s.spark, color: c),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(inr(s.lastClose), style: tt.titleSmall),
              Text(pct(s.chg1d, digits: 2), style: tt.bodySmall?.copyWith(color: c)),
            ]),
            if (trailing != null) trailing!,
          ]),
        ),
      ),
    );
  }
}

class SpikeBadge extends StatelessWidget {
  const SpikeBadge({super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(color: kBrand, borderRadius: BorderRadius.circular(6)),
        child: const Text('SPIKE TODAY',
            style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
      );
}

class EventTile extends StatelessWidget {
  final SpikeEvent e;
  final bool showTicker;
  final void Function(String url)? onOpenLink;
  const EventTile({super.key, required this.e, this.showTicker = true, this.onOpenLink});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final c = e.up ? kUp : kDown;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: showTicker ? () => openStock(context, e.ticker) : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(e.up ? Icons.trending_up : Icons.trending_down, color: c, size: 20),
              const SizedBox(width: 8),
              if (showTicker)
                Text(e.ticker, style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              if (showTicker) const SizedBox(width: 8),
              Text(pct(e.ret, digits: 2),
                  style: tt.titleSmall?.copyWith(color: c, fontWeight: FontWeight.w700)),
              const Spacer(),
              Text(prettyDate(e.date), style: tt.bodySmall),
            ]),
            const SizedBox(height: 6),
            Text('${num2(e.z?.abs(), digits: 1)}σ beyond market · volume ${num2(e.vr, digits: 1)}× normal',
                style: tt.bodySmall),
            if (e.announcement != null) ...[
              const SizedBox(height: 8),
              if (e.category != null)
                Text('${e.exchange ?? ''} filing: ${e.category}',
                    style: tt.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
              Text(e.announcement!, maxLines: 3, overflow: TextOverflow.ellipsis, style: tt.bodySmall),
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
              Text('No exchange filing found near this date.',
                  style: tt.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
            ],
          ]),
        ),
      ),
    );
  }
}
