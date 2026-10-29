import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config.dart';
import '../state/providers.dart';
import '../widgets/common.dart';
import 'home_shell.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  final bool replay;
  const OnboardingScreen({super.key, this.replay = false});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pages = PageController();
  int _page = 0;
  bool _accepted = false;

  static const _slides = [
    (
      Icons.bolt,
      'Find stocks moving on their own',
      'Most days a stock just follows NIFTY 50. We take out the market\'s part of the move and flag the stocks that moved far more than that.'
    ),
    (
      Icons.fact_check_outlined,
      'See what the company announced',
      'For recent spikes we show the official NSE/BSE filing closest to that day. It may or may not be the reason, so read it and decide for yourself.'
    ),
    (
      Icons.star_outline,
      'Follow the stocks you care about',
      'We scan about 450 NSE stocks every evening after the market closes. Track up to 5 stocks free; Pro adds an evening alert when one of yours spikes.'
    ),
  ];

  Future<void> _finish() async {
    if (widget.replay) {
      Navigator.of(context).pop();
      return;
    }
    await ref.read(boolPrefProvider(kOnboardedKey).notifier).set(true);
    if (!mounted) return;
    Navigator.of(context)
        .pushReplacement(MaterialPageRoute(builder: (_) => const HomeShell()));
  }

  @override
  Widget build(BuildContext context) {
    final last = _page == _slides.length;
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: PageView(
              controller: _pages,
              onPageChanged: (i) => setState(() => _page = i),
              children: [
                for (final s in _slides)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(s.$1,
                              size: 72,
                              color: Theme.of(context).colorScheme.primary),
                          const SizedBox(height: 24),
                          Text(s.$2,
                              style: tt.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                              textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          Text(s.$3,
                              style: tt.bodyLarge, textAlign: TextAlign.center),
                        ]),
                  ),
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.gavel_outlined, size: 64),
                        const SizedBox(height: 20),
                        Text('For learning, not advice',
                            style: tt.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 12),
                        Text(
                          'Spikewise shows statistics from public market data for education. It is not investment advice, '
                          'does not recommend buying or selling, and is not registered with SEBI. Data can be delayed or wrong.',
                          style: tt.bodyLarge,
                          textAlign: TextAlign.center,
                        ),
                        TextButton(
                            onPressed: () => openUrl(kTermsUrl),
                            child: const Text('Read the full terms')),
                        if (!widget.replay)
                          CheckboxListTile(
                            value: _accepted,
                            onChanged: (v) =>
                                setState(() => _accepted = v ?? false),
                            title: const Text(
                                'I understand this is not investment advice'),
                            controlAffinity: ListTileControlAffinity.leading,
                          ),
                      ]),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: last
                    ? (widget.replay || _accepted ? _finish : null)
                    : () => _pages.nextPage(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut),
                child: Text(
                    last ? (widget.replay ? 'Done' : 'Get started') : 'Next'),
              ),
            ),
          ),
          if (last && !widget.replay && !_accepted)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child:
                  Text('Tick the box above to continue', style: tt.bodySmall),
            ),
        ]),
      ),
    );
  }
}
