import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../config.dart';
import '../services/alerts.dart';
import '../state/providers.dart';
import '../widgets/common.dart';
import '../widgets/format.dart';
import '../learn/explainers.dart';
import 'feedback_screen.dart';
import 'onboarding_screen.dart';

final _versionProvider = FutureProvider((_) => PackageInfo.fromPlatform());

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  Future<void> _toggle(
      BuildContext context, WidgetRef ref, String key, bool on) async {
    final meta = await ref.read(metaProvider.future);
    final ok = await Alerts.set(key, on, meta.lastMarketDate);
    if (ok) {
      ref.invalidate(boolPrefProvider(key));
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Allow notifications for Spikewise in Android settings to get alerts.')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pro = ref.watch(proProvider);
    final alerts = ref.watch(boolPrefProvider(Alerts.namedKey));
    final digest = ref.watch(boolPrefProvider(Alerts.digestKey));
    final meta = ref.watch(metaProvider).valueOrNull;
    final version = ref.watch(_versionProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(children: [
        ListTile(
          leading: const Icon(Icons.workspace_premium_outlined),
          title: Text(pro ? 'Spikewise Pro: active' : 'Upgrade to Pro'),
          subtitle: Text(pro
              ? 'Manage in Google Play → Subscriptions'
              : 'Unlimited watchlist, alerts, full history'),
          onTap: () => openPaywall(context),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.nights_stay_outlined),
          title: const Text('Evening summary'),
          subtitle: const Text(
              'Free · after market close: how many stocks moved on their own, and whether yours did'),
          value: digest,
          onChanged: (v) => _toggle(context, ref, Alerts.digestKey, v),
        ),
        if (!pro)
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('Spike alerts'),
            subtitle: const Text(
                'Evening alert when a stock you follow spikes · Pro'),
            trailing: const Icon(Icons.lock_outline),
            onTap: () => openPaywall(context),
          )
        else
          SwitchListTile(
            secondary: const Icon(Icons.notifications_active_outlined),
            title: const Text('Spike alerts'),
            subtitle: Text(pro
                ? 'Evening alert after market close when a stock you follow spikes'
                : 'Pro feature'),
            value: pro && alerts,
            onChanged: pro
                ? (v) => _toggle(context, ref, Alerts.namedKey, v)
                : (_) => openPaywall(context),
          ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.feedback_outlined),
          title: const Text('Send feedback'),
          subtitle: const Text('Ideas, bugs and wrong data'),
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const FeedbackScreen())),
        ),
        ListTile(
          leading: const Icon(Icons.star_rate_outlined),
          title: const Text('Rate on Google Play'),
          onTap: () => openUrl(kPlayUrl),
        ),
        ListTile(
          leading: const Icon(Icons.menu_book_outlined),
          title: const Text('Learn the basics'),
          subtitle: const Text('Short explainers in English and हिन्दी'),
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const LearnScreen())),
        ),
        ListTile(
          leading: const Icon(Icons.school_outlined),
          title: const Text('How Spikewise works'),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const OnboardingScreen(replay: true))),
        ),
        ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy policy'),
            onTap: () => openUrl(kPrivacyUrl)),
        ListTile(
            leading: const Icon(Icons.gavel_outlined),
            title: const Text('Terms & disclaimer'),
            onTap: () => openUrl(kTermsUrl)),
        const Divider(),
        ListTile(
          dense: true,
          title: Text(
              'Version ${version?.version ?? ''} (${version?.buildNumber ?? ''})'),
          subtitle: Text(meta == null
              ? ''
              : 'Data: ${prettyDate(meta.lastMarketDate)} close · updated ${istTime(meta.generated)}'),
        ),
        const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16), child: Disclaimer()),
      ]),
    );
  }
}
