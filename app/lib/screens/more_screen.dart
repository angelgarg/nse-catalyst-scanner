import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../config.dart';
import '../services/alerts.dart';
import '../state/providers.dart';
import '../widgets/common.dart';
import '../widgets/format.dart';
import 'feedback_screen.dart';
import 'onboarding_screen.dart';

final _versionProvider = FutureProvider((_) => PackageInfo.fromPlatform());

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  Future<void> _toggleAlerts(BuildContext context, WidgetRef ref, bool on) async {
    final pref = ref.read(boolPrefProvider(kAlertsKey).notifier);
    if (!on) {
      await Alerts.disable();
      await pref.set(false);
      return;
    }
    final meta = await ref.read(metaProvider.future);
    final ok = await Alerts.enable(meta.lastMarketDate);
    if (ok) {
      await pref.set(true);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Allow notifications for Spikewise in Android settings to get alerts.')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pro = ref.watch(proProvider);
    final alerts = ref.watch(boolPrefProvider(kAlertsKey));
    final meta = ref.watch(metaProvider).valueOrNull;
    final version = ref.watch(_versionProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(children: [
        ListTile(
          leading: const Icon(Icons.workspace_premium_outlined),
          title: Text(pro ? 'Spikewise Pro: active' : 'Upgrade to Pro'),
          subtitle: Text(pro ? 'Manage in Google Play → Subscriptions' : 'Unlimited watchlist, alerts, full history'),
          onTap: () => openPaywall(context),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.notifications_active_outlined),
          title: const Text('Spike alerts'),
          subtitle: Text(pro ? 'Notify me when a watchlist stock spikes' : 'Pro feature'),
          value: pro && alerts,
          onChanged: pro ? (v) => _toggleAlerts(context, ref, v) : (_) => openPaywall(context),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.feedback_outlined),
          title: const Text('Send feedback'),
          subtitle: const Text('Ideas and bugs go straight to the build queue'),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FeedbackScreen())),
        ),
        ListTile(
          leading: const Icon(Icons.star_rate_outlined),
          title: const Text('Rate on Google Play'),
          onTap: () => openUrl(kPlayUrl),
        ),
        ListTile(
          leading: const Icon(Icons.school_outlined),
          title: const Text('How Spikewise works'),
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const OnboardingScreen(replay: true))),
        ),
        ListTile(leading: const Icon(Icons.privacy_tip_outlined), title: const Text('Privacy policy'), onTap: () => openUrl(kPrivacyUrl)),
        ListTile(leading: const Icon(Icons.gavel_outlined), title: const Text('Terms & disclaimer'), onTap: () => openUrl(kTermsUrl)),
        const Divider(),
        ListTile(
          dense: true,
          title: Text('Version ${version?.version ?? ''} (${version?.buildNumber ?? ''})'),
          subtitle: Text(meta == null
              ? ''
              : 'Data: ${prettyDate(meta.lastMarketDate)} close · generated ${meta.generated}'),
        ),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Disclaimer()),
      ]),
    );
  }
}
