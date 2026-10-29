import 'package:flutter_test/flutter_test.dart';
import 'package:spikewise/config.dart';
import 'package:spikewise/data/models.dart';
import 'package:spikewise/widgets/format.dart';

void main() {
  test('default watchlist leaves room under the free limit', () {
    expect(kDefaultWatchlist.length, lessThan(const RemoteConfig().freeWatchlistLimit));
  });

  test('plain-language move sizes', () {
    expect(moveSize(1.7), 'Big move');
    expect(moveSize(-2.4), 'Very big move');
    expect(moveSize(5), 'Rare move');
    expect(volumeText(5.46), '5.5× usual volume');
  });

  test('zero change is neutral, not +0.00%', () {
    expect(pct(0.0, digits: 2), '0.00%');
    expect(pct(0.012), '+1.2%');
    expect(pct(-0.031), '-3.1%');
  });

  test('rupees drop paise above 1000 and keep Indian grouping', () {
    expect(inr(118065.4), '₹1,18,065');
    expect(inr(265.5), '₹265.50');
  });

  test('filing timing relative to the spike', () {
    SpikeEvent ev(String filed) =>
        SpikeEvent.fromJson({'date': '2026-10-23', 'ticker': 'X', 'filed': filed});
    expect(ev('2026-10-21').filedRelative, 'filed 2 days before');
    expect(ev('2026-10-23').filedRelative, 'filed the same day');
    expect(ev('2026-10-24').filedRelative, 'filed 1 day after');
  });

  test('IST time formatting', () {
    expect(istTime('2026-10-29T14:02:23Z'), '29 Oct, 7:32 pm IST');
  });
}
