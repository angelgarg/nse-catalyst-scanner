import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spikewise/data/models.dart';
import 'package:spikewise/widgets/share_card.dart';

void main() {
  final e = SpikeEvent.fromJson({
    'date': '2026-09-28', 'ticker': 'BAJFINANCE', 'name': 'Bajaj Finance', 'ret': -0.0119,
    'z': 1.85, 'vr': 1.6, 'direction': 'Down', 'category': 'Press Release', 'exchange': 'NSE',
  });

  test('share text is neutral and carries the disclaimer', () {
    final t = shareText(e);
    expect(t, contains('did better than NIFTY explains'));
    expect(t, contains('Filing near this date: Press Release'));
    expect(t, contains('Educational, not investment advice'));
    for (final banned in ['buy', 'target', 'tip', '🚀']) {
      expect(t.toLowerCase().contains(banned), isFalse, reason: banned);
    }
  });

  testWidgets('share card renders with the disclaimer and "may not be the cause"', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Center(child: SizedBox(width: 360, child: SpikeShareCard(e: e))))));
    expect(find.text('BAJFINANCE'), findsOneWidget);
    expect(find.text('May not be the cause of the move.'), findsOneWidget);
    expect(find.textContaining('Educational, not investment advice'), findsOneWidget);
    expect(tester.takeException(), isNull); // no overflow
  });
}
