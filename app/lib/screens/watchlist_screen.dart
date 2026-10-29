import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import '../services/alerts.dart';
import '../state/providers.dart';
import '../widgets/common.dart';
import '../widgets/format.dart';
import '../widgets/spike_mark.dart';
import '../widgets/tiles.dart';

class WatchlistScreen extends ConsumerWidget {
  final VoidCallback onAdd;
  final VoidCallback onOpenFeed;
  const WatchlistScreen(
      {super.key, required this.onAdd, required this.onOpenFeed});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(metaProvider);
    ref.invalidate(configProvider);
    ref.invalidate(eventsProvider);
    ref.invalidate(summaryProvider);
    await ref.read(summaryProvider.future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final watch = ref.watch(watchlistProvider);
    final summary = ref.watch(summaryProvider);
    final byTicker = ref.watch(summaryByTickerProvider);
    final meta = ref.watch(metaProvider).valueOrNull;
    final cfg = ref.watch(configProvider).valueOrNull;
    final pro = ref.watch(proProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Spikewise',
            style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          if (!pro)
            TextButton.icon(
                onPressed: () => openPaywall(context),
                icon: const Icon(Icons.workspace_premium_outlined),
                label: const Text('Pro')),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: const Text('Add stock')),
      body: summary.when(
        loading: () => const SkeletonList(),
        error: (e, _) => ErrorRetry(error: e, onRetry: () => _refresh(ref)),
        data: (_) => RefreshIndicator(
          onRefresh: () => _refresh(ref),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
            children: [
              if (cfg?.notice != null)
                Card(
                    child: ListTile(
                        leading: const Icon(Icons.campaign_outlined),
                        title: Text(cfg!.notice!))),
              if (meta != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                      'Closing prices for ${prettyDate(meta.lastMarketDate)} · updated ${istTime(meta.generated)}',
                      style: Theme.of(context).textTheme.bodySmall),
                ),
              if (meta != null)
                _TonightCard(
                  day: meta.lastMarketDate,
                  events: ref.watch(eventsProvider).valueOrNull,
                  watch: watch.toSet(),
                  onOpenFeed: onOpenFeed,
                ),
              if (watch.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                      'No stocks yet. Add the stocks you own and we\'ll show you when one moves on its own.',
                      textAlign: TextAlign.center),
                ),
              for (final (i, t) in watch.indexed)
                FadeRiseIn(
                  index: i,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Dismissible(
                      key: ValueKey(t),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 24),
                        child: const Icon(Icons.delete_outline),
                      ),
                      onDismissed: (_) {
                        ref.read(watchlistProvider.notifier).remove(t);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('Removed $t'),
                          action: SnackBarAction(
                              label: 'Undo',
                              onPressed: () =>
                                  ref.read(watchlistProvider.notifier).add(t)),
                        ));
                      },
                      child: byTicker[t] != null
                          ? StockTile(s: byTicker[t]!)
                          : Card(
                              child: ListTile(
                                title: Text(t),
                                subtitle: const Text(
                                    'Not in the daily scan · tap to analyse now'),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => openStock(context, t),
                              ),
                            ),
                    ),
                  ),
                ),
              if (!pro && cfg != null && watch.length >= cfg.freeWatchlistLimit)
                ProLock(
                    label: 'Track more than ${cfg.freeWatchlistLimit} stocks',
                    child: const SizedBox()),
              const Disclaimer(),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Tonight": the one-glance answer to "did anything unusual happen?" (growth review).
class _TonightCard extends ConsumerWidget {
  final String day;
  final List<SpikeEvent>? events;
  final Set<String> watch;
  final VoidCallback onOpenFeed;
  const _TonightCard(
      {required this.day,
      required this.events,
      required this.watch,
      required this.onOpenFeed});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ev = events;
    if (ev == null) return const SizedBox.shrink();
    final todays = ev.where((e) => e.date == day).toList();
    final yours = todays
        .where((e) => watch.contains(e.ticker))
        .map((e) => e.ticker)
        .toList();
    final filed = todays.where((e) => e.announcement != null).length;
    final digestOn = ref.watch(boolPrefProvider(Alerts.digestKey));
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onOpenFeed,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(prettyDate(day).toUpperCase(),
                  style: tt.labelSmall?.copyWith(letterSpacing: 0.8)),
              const SizedBox(height: 4),
              Text(
                  todays.isEmpty
                      ? 'A quiet day: no stock moved much more than NIFTY.'
                      : '${todays.length} stocks moved on their own · $filed near a filing',
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                  yours.isEmpty
                      ? 'Your stocks moved with the market.'
                      : 'Yours: ${yours.join(', ')}',
                  style: tt.bodyMedium),
              if (!digestOn) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  icon: const Icon(Icons.nights_stay_outlined, size: 18),
                  label: const Text('Get this every evening (free)'),
                  onPressed: () async {
                    final ok = await Alerts.set(Alerts.digestKey, true, day);
                    ref.invalidate(boolPrefProvider(Alerts.digestKey));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(ok
                              ? 'Done. You\'ll get a short summary after market close.'
                              : 'Allow notifications for Spikewise in Android settings.')));
                    }
                  },
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
