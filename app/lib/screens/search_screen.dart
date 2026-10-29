import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import '../widgets/common.dart';
import '../widgets/tiles.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  String _q = '';

  Future<void> _toggle(String ticker) async {
    final wl = ref.read(watchlistProvider.notifier);
    if (ref.read(watchlistProvider).contains(ticker)) {
      await wl.remove(ticker);
      return;
    }
    final res = await wl.add(ticker);
    if (!mounted) return;
    if (res == AddResult.limit) {
      openPaywall(context);
    } else if (res == AddResult.added) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Added $ticker to watchlist')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final uni = ref.watch(universeProvider);
    final watch = ref.watch(watchlistProvider).toSet();
    final q = _q.trim().toLowerCase();
    final raw = _q.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9&-]'), '');

    return Scaffold(
      appBar: AppBar(title: const Text('Search NSE stocks')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            autofocus: false,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Company or ticker, e.g. Tata or SBIN',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        Expanded(
          child: uni.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorRetry(
                error: e, onRetry: () => ref.invalidate(universeProvider)),
            data: (all) {
              final hits = q.isEmpty
                  ? all
                  : all
                      .where((u) =>
                          u.ticker.toLowerCase().contains(q) ||
                          u.name.toLowerCase().contains(q))
                      .toList();
              final exact = all.any((u) => u.ticker == raw);
              return ListView.builder(
                itemCount: hits.length + 1,
                itemBuilder: (context, i) {
                  if (i == hits.length) {
                    // Only offer on-demand analysis when nothing matched.
                    if (raw.length < 3 || exact || hits.isNotEmpty) {
                      return const SizedBox(height: 24);
                    }
                    return ListTile(
                      leading: const Icon(Icons.travel_explore),
                      title: Text('Analyse "$raw" now'),
                      subtitle: const Text(
                          'Not in the daily scan. Takes up to a minute.'),
                      onTap: () => openStock(context, raw),
                    );
                  }
                  final u = hits[i];
                  final inList = watch.contains(u.ticker);
                  return ListTile(
                    title: Text(u.ticker,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(u.name),
                    onTap: () => openStock(context, u.ticker),
                    trailing: IconButton(
                      tooltip:
                          inList ? 'Remove from watchlist' : 'Add to watchlist',
                      icon: Icon(inList ? Icons.star : Icons.star_outline),
                      onPressed: () => _toggle(u.ticker),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}
