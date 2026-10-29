import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../config.dart';
import '../services/billing.dart';
import '../state/providers.dart';
import '../widgets/common.dart';

class PaywallScreen extends ConsumerWidget {
  const PaywallScreen({super.key});

  static const _features = [
    (Icons.all_inclusive, 'Unlimited watchlist', 'Track as many NSE stocks as you like'),
    (Icons.notifications_active_outlined, 'Spike alerts', 'A notification when a watched stock spikes'),
    (Icons.history, 'Full history', '2 years of spike days and 120-day spike feed'),
    (Icons.insights_outlined, 'Model view', 'Expected move size and up-day tendency, with fit quality'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pro = ref.watch(proProvider);
    final billing = ref.watch(billingProvider);
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Spikewise Pro')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text(pro ? 'You have Pro. Thank you!' : 'See every spike, the moment it happens.',
            style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        for (final f in _features)
          ListTile(contentPadding: EdgeInsets.zero, leading: Icon(f.$1), title: Text(f.$2), subtitle: Text(f.$3)),
        const SizedBox(height: 16),
        if (!pro) ...[
          if (billing.loading)
            const Center(child: CircularProgressIndicator())
          else if (!billing.available || billing.products.isEmpty)
            const Card(
              child: ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Subscriptions are not available right now'),
                subtitle: Text('Make sure Google Play is installed and you are signed in, then try again.'),
              ),
            )
          else
            for (final p in billing.products)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _PlanButton(p: p, onTap: () => ref.read(billingProvider.notifier).buy(p)),
              ),
          if (billing.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(billing.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          TextButton(
            onPressed: () => ref.read(billingProvider.notifier).refreshEntitlement(),
            child: const Text('Restore purchase'),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          'Subscriptions renew automatically through Google Play until cancelled. Manage or cancel any time '
          'in Google Play → Payments & subscriptions. Pro adds features; it does not make the analysis advice.',
          style: tt.bodySmall,
        ),
        Row(children: [
          TextButton(onPressed: () => openUrl(kTermsUrl), child: const Text('Terms')),
          TextButton(onPressed: () => openUrl(kPrivacyUrl), child: const Text('Privacy')),
        ]),
      ]),
    );
  }
}

class _PlanButton extends StatelessWidget {
  final ProductDetails p;
  final VoidCallback onTap;
  const _PlanButton({required this.p, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final yearly = p.id == kProYearly;
    return FilledButton(
      style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
      onPressed: onTap,
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(yearly ? 'Yearly' : 'Monthly', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            if (yearly) const Text('Best value'),
          ]),
        ),
        Text('${p.price}${yearly ? '/yr' : '/mo'}', style: const TextStyle(fontSize: 16)),
      ]),
    );
  }
}
