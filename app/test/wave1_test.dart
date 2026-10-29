import 'package:flutter_test/flutter_test.dart';
import 'package:spikewise/learn/explainers.dart';
import 'package:spikewise/services/alerts.dart';

void main() {
  final events = [
    {'date': '2026-10-29', 'ticker': 'INFY', 'announcement': 'Results'},
    {'date': '2026-10-29', 'ticker': 'ECLERX', 'announcement': null},
    {'date': '2026-10-28', 'ticker': 'TCS', 'announcement': null},
  ];

  test('digest counts only the given day', () {
    final c = digestCounts(events, '2026-10-29', {'INFY', 'TCS'});
    expect((c.total, c.filed, c.yours), (2, 1, 1));
    expect(digestTitle(c), '2 stocks moved on their own today');
    expect(digestBody(c),
        '1 near a company filing · 1 is on your list. Tap to see.');
  });

  test('digest reassures when none of yours moved, and on quiet days', () {
    expect(digestBody(digestCounts(events, '2026-10-29', {'RELIANCE'})),
        '1 near a company filing · Your stocks moved with the market.');
    final quiet = digestCounts(events, '2026-10-30', {'RELIANCE'});
    expect(digestTitle(quiet), startsWith('A quiet day'));
  });

  test('every explainer has English and Hindi, and never talks about buying',
      () {
    for (final e in explainers.values) {
      expect(e.en, isNotEmpty);
      expect(e.hi, isNotEmpty);
      final text = '${e.en} ${e.hi}'.toLowerCase();
      for (final banned in [
        'buy now',
        'target',
        'tip',
        'multibagger',
        'tezi'
      ]) {
        expect(text.contains(banned), isFalse,
            reason: '${e.title} contains "$banned"');
      }
    }
  });
}
