import 'package:flutter_test/flutter_test.dart';
import 'package:spikewise/config.dart';
import 'package:spikewise/data/models.dart';

void main() {
  test('fileKey matches the pipeline rule', () {
    expect(fileKey('M&M'), 'M_M');
    expect(fileKey('BAJAJ-AUTO'), 'BAJAJ-AUTO');
  });

  test('summary row parses and detects a spike on the latest session', () {
    final s = StockSummary.fromJson({
      'ticker': 'INFY',
      'name': 'Infosys',
      'last_close': 1161.2,
      'last_date': '2026-10-29',
      'chg_1d': 0.012,
      'cat_count': 3,
      'last_cat_date': '2026-10-29',
      'spark': [1, 2, null, 4],
    });
    expect(s.spikedToday, isTrue);
    expect(s.spark, [1.0, 2.0, null, 4.0]);
  });

  test('detail tolerates missing fields and nested sentiment', () {
    final d = StockDetail.fromJson({
      'ticker': 'TCS',
      'name': 'TCS',
      'close': [1, 2, 3],
      'dates': ['a', 'b', 'c'],
      'sentiment': {
        'label': 'bullish',
        'headlines': [
          {'title': 'Wins order', 'link': '', 'age': '2h ago'}
        ]
      },
      'events': [
        {
          'date': '2026-10-01',
          'ticker': 'TCS',
          'direction': 'Down',
          'ret': -0.05
        }
      ],
    });
    expect(d.summary.sentiment, 'bullish');
    expect(d.headlines.single.title, 'Wins order');
    expect(d.events.single.up, isFalse);
    expect(d.eventFlags, isEmpty);
  });

  test('remote config defaults', () {
    final c = RemoteConfig.fromJson({});
    expect(c.freeWatchlistLimit, 5);
    expect(c.freeHistoryDays, 30);
  });
}
