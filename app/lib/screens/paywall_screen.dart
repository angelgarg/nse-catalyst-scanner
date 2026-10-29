import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../config.dart';
import '../services/billing.dart';
import '../state/providers.dart';
import '../widgets/common.dart';
import '../widgets/spike_mark.dart';

class PaywallScreen extends ConsumerWidget {
  const PaywallScreen({super.key});

  static const _features = [
    (
      Icons.all_inclusive,
      'Unlimited watchlist',
      'Track as many NSE stocks as you like (free: 5)'
    ),
    (
      Icons.notifications_active_outlined,
      'Evening spike alerts',
      'A notification after market close when a stock you follow moves on its own'
    ),
    (
      Icons.history,
      '2 years of spike days',
      'Free shows the last 30 days. Filings are matched for recent spikes only'
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pro = ref.watch(proProvider);
    final billing = ref.watch(billingProvider);
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Spikewise Pro')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text(
            pro
                ? 'You have Pro. Thank you!'
                : 'Never miss a spike in the stocks you follow',
            style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        for (final f in _features)
          ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(f.$1),
              title: Text(f.$2),
              subtitle: Text(f.$3)),
        const SizedBox(height: 16),
        if (!pro) ...[
          if (billing.loading)
            const Center(child: SpikeMarkLoader())
          else if (!billing.available || billing.products.isEmpty)
            const Card(
              child: ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Subscriptions are not available right now'),
                subtitle: Text(
                    'Make sure Google Play is installed and you are signed in, then try again.'),
              ),
            )
          else
            // Yearly first: it's the better deal and the one most people should pick.
            for (final p in [
              ...billing.products
            ]..sort((a, b) => b.rawPrice.compareTo(a.rawPrice)))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _PlanButton(
                  p: p,
                  monthly: billing.products
                      .where((m) => m.id == kProMonthly)
                      .firstOrNull,
                  onTap: () => ref.read(billingProvider.notifier).buy(p),
                ),
              ),
          const Text(
              'Pay through Google Play with UPI, card or Play balance. Cancel anytime.',
              textAlign: TextAlign.center),
          if (billing.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(billing.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          TextButton(
            onPressed: () =>
                ref.read(billingProvider.notifier).refreshEntitlement(),
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
          TextButton(
              onPressed: () => openUrl(kTermsUrl), child: const Text('Terms')),
          TextButton(
              onPressed: () => openUrl(kPrivacyUrl),
              child: const Text('Privacy')),
        ]),
      ]),
    );
  }
}

class _PlanButton extends StatelessWidget {
  final ProductDetails p;
  final ProductDetails? monthly;
  final VoidCallback onTap;
  const _PlanButton({required this.p, required this.onTap, this.monthly});

  @override
  Widget build(BuildContext context) {
    final yearly = p.id == kProYearly;
    final perMonth = (p.rawPrice / 12).round();
    final saving = monthly == null || monthly!.rawPrice <= 0
        ? null
        : (100 * (1 - p.rawPrice / (monthly!.rawPrice * 12))).round();
    final style = yearly
        ? FilledButton.styleFrom(padding: const EdgeInsets.all(16))
        : FilledButton.styleFrom(
            padding: const EdgeInsets.all(16),
            backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
            foregroundColor:
                Theme.of(context).colorScheme.onSecondaryContainer);
    return FilledButton(
      style: style,
      onPressed: onTap,
      child: Row(children: [
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(yearly ? 'Yearly' : 'Monthly',
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            if (yearly)
              Text('${p.currencySymbol}$perMonth/month, billed yearly'
                  '${saving != null && saving > 0 ? ' · save $saving%' : ''}'),
          ]),
        ),
        Text('${p.price}${yearly ? '/yr' : '/mo'}',
            style: const TextStyle(fontSize: 16)),
      ]),
    );
  }
}
