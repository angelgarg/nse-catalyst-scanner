import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:spikewise/data/models.dart';
import 'package:spikewise/learn/quiz.dart';

StockDetail _detail({required List<int> spikes, int n = 120}) {
  final start = DateTime(2026, 5, 1);
  final dates = [for (var i = 0; i < n; i++) start.add(Duration(days: i)).toIso8601String().substring(0, 10)];
  return StockDetail.fromJson({
    'ticker': 'X', 'name': 'X Ltd', 'dates': dates,
    'close': [for (var i = 0; i < n; i++) 100.0 + i],
    'volume': [for (var i = 0; i < n; i++) 1000],
    'event_flags': [for (var i = 0; i < n; i++) spikes.contains(i)],
    'events': [for (final i in spikes) {'date': dates[i], 'ticker': 'X', 'ret': 0.05, 'z': 2.5, 'vr': 3.0}],
  });
}

void main() {
  final now = DateTime(2026, 11, 1);

  test('question uses only spikes at least 45 days old with a clean window', () {
    final q = questionFrom(_detail(spikes: [40]), now, math.Random(1))!;
    expect(q.start + q.answer, 40);
    expect(q.length, 20);
    expect(DateTime.parse(q.event.date).isBefore(now.subtract(const Duration(days: minAgeDays))), isTrue);
  });

  test('recent spikes are never used', () {
    // index 170 = 2026-10-18, under 45 days before 1 Nov
    expect(questionFrom(_detail(spikes: [170], n: 180), now, math.Random(1)), isNull);
  });

  test('windows with two spikes are skipped (answer must be unambiguous)', () {
    expect(questionFrom(_detail(spikes: [40, 42]), now, math.Random(1)), isNull);
  });
}
