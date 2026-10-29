import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import '../widgets/common.dart';
import '../widgets/tiles.dart';

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  bool _watchOnly = false;
  bool? _up; // null = both
  bool _filedOnly = false;

  @override
  Widget build(BuildContext context) {
    final events = ref.watch(eventsProvider);
    final watch = ref.watch(watchlistProvider).toSet();
    final pro = ref.watch(proProvider);
    final cfg = ref.watch(configProvider).valueOrNull;
    final meta = ref.watch(metaProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Spike feed')),
      body: events.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorRetry(error: e, onRetry: () => ref.invalidate(eventsProvider)),
        data: (all) {
          var cutoff = '';
          final last = DateTime.tryParse(meta?.lastMarketDate ?? '');
          if (!pro && last != null) {
            cutoff = last
                .subtract(Duration(days: cfg?.freeHistoryDays ?? 30))
                .toIso8601String()
                .substring(0, 10);
          }
          final list = all
              .where((e) => e.date.compareTo(cutoff) >= 0)
              .where((e) => !_watchOnly || watch.contains(e.ticker))
              .where((e) => _up == null || e.up == _up)
              .where((e) => !_filedOnly || e.announcement != null)
              .toList();
          final hidden = all.length - all.where((e) => e.date.compareTo(cutoff) >= 0).length;
          return RefreshIndicator(
            onRefresh: () => ref.refresh(eventsProvider.future),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              itemCount: list.length + 2,
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Wrap(spacing: 8, children: [
                    FilterChip(label: const Text('My watchlist'), selected: _watchOnly,
                        onSelected: (v) => setState(() => _watchOnly = v)),
                    FilterChip(label: const Text('Up'), selected: _up == true,
                        onSelected: (v) => setState(() => _up = v ? true : null)),
                    FilterChip(label: const Text('Down'), selected: _up == false,
                        onSelected: (v) => setState(() => _up = v ? false : null)),
                    FilterChip(label: const Text('With filing'), selected: _filedOnly,
                        onSelected: (v) => setState(() => _filedOnly = v)),
                  ]);
                }
                if (i == list.length + 1) {
                  return Column(children: [
                    if (list.isEmpty)
                      const Padding(padding: EdgeInsets.all(32), child: Text('No spikes match these filters.')),
                    if (!pro && hidden > 0)
                      ProLock(label: '$hidden older spikes (up to 120 days)', child: const SizedBox()),
                    const Disclaimer(),
                  ]);
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: EventTile(e: list[i - 1], onOpenLink: openUrl),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
