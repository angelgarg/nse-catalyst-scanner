import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import '../widgets/common.dart';
import '../widgets/format.dart';
import '../widgets/tiles.dart';

class WatchlistScreen extends ConsumerWidget {
  final VoidCallback onAdd;
  const WatchlistScreen({super.key, required this.onAdd});

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
        title: const Text('Spikewise', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          if (!pro)
            TextButton.icon(
                onPressed: () => openPaywall(context),
                icon: const Icon(Icons.workspace_premium_outlined),
                label: const Text('Pro')),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('Add stock')),
      body: summary.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorRetry(error: e, onRetry: () => _refresh(ref)),
        data: (_) => RefreshIndicator(
          onRefresh: () => _refresh(ref),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
            children: [
              if (cfg?.notice != null)
                Card(child: ListTile(leading: const Icon(Icons.campaign_outlined), title: Text(cfg!.notice!))),
              if (meta != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('Closing data for ${prettyDate(meta.lastMarketDate)} · ${meta.stocks} NSE stocks scanned',
                      style: Theme.of(context).textTheme.bodySmall),
                ),
              if (watch.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('Your watchlist is empty. Add stocks to see when they move on their own news.',
                      textAlign: TextAlign.center),
                ),
              for (final t in watch)
                Padding(
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
                            label: 'Undo', onPressed: () => ref.read(watchlistProvider.notifier).add(t)),
                      ));
                    },
                    child: byTicker[t] != null
                        ? StockTile(s: byTicker[t]!)
                        : Card(
                            child: ListTile(
                              title: Text(t),
                              subtitle: const Text('Not in the daily scan · tap to analyse now'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => openStock(context, t),
                            ),
                          ),
                  ),
                ),
              if (!pro && cfg != null && watch.length >= cfg.freeWatchlistLimit)
                ProLock(label: 'Track more than ${cfg.freeWatchlistLimit} stocks', child: const SizedBox()),
              const Disclaimer(),
            ],
          ),
        ),
      ),
    );
  }
}
