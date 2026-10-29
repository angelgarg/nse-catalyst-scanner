import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:package_info_plus/package_info_plus.dart';

import '../config.dart';
import '../services/billing.dart';
import '../state/providers.dart';
import '../widgets/common.dart';
import 'feed_screen.dart';
import 'more_screen.dart';
import 'search_screen.dart';
import 'watchlist_screen.dart';

final _buildProvider = FutureProvider<int>((_) async =>
    int.tryParse((await PackageInfo.fromPlatform()).buildNumber) ?? 0);

/// Remote kill switch: config.json `min_app_build` blocks builds that must not run.
class _UpdateRequired extends StatelessWidget {
  const _UpdateRequired();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.system_update, size: 64),
              const SizedBox(height: 16),
              Text('Please update Spikewise',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              const Text(
                  'This version is no longer supported. Update from Google Play to keep using the app.',
                  textAlign: TextAlign.center),
              const SizedBox(height: 20),
              FilledButton(
                  onPressed: () => openUrl(kPlayUrl),
                  child: const Text('Update')),
            ]),
          ),
        ),
      );
}

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    ref.watch(billingProvider); // start billing + restore entitlement on launch
    final minBuild = ref.watch(configProvider).valueOrNull?.minAppBuild ?? 0;
    final build = ref.watch(_buildProvider).valueOrNull;
    if (build != null && build < minBuild) return const _UpdateRequired();
    final pages = [
      WatchlistScreen(onAdd: () => setState(() => _tab = 2)),
      const FeedScreen(),
      const SearchScreen(),
      const MoreScreen(),
    ];
    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.star_outline),
              selectedIcon: Icon(Icons.star),
              label: 'Watchlist'),
          NavigationDestination(
              icon: Icon(Icons.bolt_outlined),
              selectedIcon: Icon(Icons.bolt),
              label: 'Spikes'),
          NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
          NavigationDestination(icon: Icon(Icons.menu), label: 'More'),
        ],
      ),
    );
  }
}
