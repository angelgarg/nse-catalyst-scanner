import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../screens/paywall_screen.dart';
import '../state/providers.dart';

String friendlyError(Object e) {
  final s = '$e';
  // ApiException messages are written for users; anything else is not.
  if (s == 'not_found') return 'We don\'t have data for this stock yet.';
  if (e.runtimeType.toString() == 'ApiException') return s;
  return 'Something went wrong. Pull down or tap below to try again.';
}

Future<void> openUrl(String url) =>
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

void openPaywall(BuildContext context) => Navigator.of(context)
    .push(MaterialPageRoute(builder: (_) => const PaywallScreen()));

class ErrorRetry extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const ErrorRetry({super.key, required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off, size: 44),
            const SizedBox(height: 12),
            Text(friendlyError(error), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.tonal(
                onPressed: onRetry, child: const Text('Try again')),
          ]),
        ),
      );
}

/// Blurs nothing, hides nothing: shows a clear lock row that opens the paywall.
class ProLock extends ConsumerWidget {
  final String label;
  final Widget child;
  const ProLock({super.key, required this.label, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(proProvider)) return child;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.lock_outline),
        title: Text(label),
        subtitle: const Text('Included with Spikewise Pro'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => openPaywall(context),
      ),
    );
  }
}

class Disclaimer extends StatelessWidget {
  const Disclaimer({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          'Educational statistics from public data. Not investment advice and not a '
          'recommendation to buy or sell. Spikewise is not SEBI-registered.',
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
}
