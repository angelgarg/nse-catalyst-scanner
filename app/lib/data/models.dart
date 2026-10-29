double? _d(dynamic v) => v is num ? v.toDouble() : null;
int _i(dynamic v) => v is num ? v.toInt() : 0;
String? _s(dynamic v) => v is String && v.isNotEmpty ? v : null;

class DataMeta {
  final String lastMarketDate;
  final String generated;
  final int stocks;

  DataMeta({required this.lastMarketDate, required this.generated, required this.stocks});

  factory DataMeta.fromJson(Map<String, dynamic> j) => DataMeta(
        lastMarketDate: j['last_market_date'] ?? '',
        generated: j['generated'] ?? '',
        stocks: _i(j['stocks']),
      );
}

class RemoteConfig {
  final int minAppBuild;
  final int latestAppBuild;
  final String? notice;
  final int freeWatchlistLimit;
  final int freeHistoryDays;

  const RemoteConfig({
    this.minAppBuild = 1,
    this.latestAppBuild = 1,
    this.notice,
    this.freeWatchlistLimit = 5,
    this.freeHistoryDays = 30,
  });

  factory RemoteConfig.fromJson(Map<String, dynamic> j) => RemoteConfig(
        minAppBuild: _i(j['min_app_build']),
        latestAppBuild: _i(j['latest_app_build']),
        notice: _s(j['notice']),
        freeWatchlistLimit: j['free_watchlist_limit'] is num ? _i(j['free_watchlist_limit']) : 5,
        freeHistoryDays: j['free_history_days'] is num ? _i(j['free_history_days']) : 30,
      );
}

class UniverseEntry {
  final String ticker;
  final String name;
  UniverseEntry(this.ticker, this.name);

  factory UniverseEntry.fromJson(Map<String, dynamic> j) =>
      UniverseEntry(j['ticker'] ?? '', j['name'] ?? '');
}

/// One row of summary.json -- enough for list tiles.
class StockSummary {
  final String ticker;
  final String name;
  final double? lastClose;
  final String? lastDate;
  final double? chg1d;
  final double? ret1m;
  final double? ret3m;
  final int catCount;
  final String? lastCatDate;
  final double? zLast;
  final double? vrLast;
  final double? rsi;
  final String sentiment;
  final List<double?> spark;

  StockSummary({
    required this.ticker,
    required this.name,
    this.lastClose,
    this.lastDate,
    this.chg1d,
    this.ret1m,
    this.ret3m,
    this.catCount = 0,
    this.lastCatDate,
    this.zLast,
    this.vrLast,
    this.rsi,
    this.sentiment = 'neutral',
    this.spark = const [],
  });

  factory StockSummary.fromJson(Map<String, dynamic> j) => StockSummary(
        ticker: j['ticker'] ?? '',
        name: j['name'] ?? '',
        lastClose: _d(j['last_close']),
        lastDate: _s(j['last_date']),
        chg1d: _d(j['chg_1d']),
        ret1m: _d(j['ret_1m']),
        ret3m: _d(j['ret_3m']),
        catCount: _i(j['cat_count']),
        lastCatDate: _s(j['last_cat_date']),
        zLast: _d(j['z_last']),
        vrLast: _d(j['vr_last']),
        rsi: _d(j['rsi']),
        sentiment: j['sentiment'] is String ? j['sentiment'] : 'neutral',
        spark: (j['spark'] as List? ?? const []).map(_d).toList(),
      );

  /// True when the latest session itself was a spike day.
  bool get spikedToday => lastCatDate != null && lastCatDate == lastDate;
}

class SpikeEvent {
  final String date;
  final String ticker;
  final String name;
  final double? ret;
  final double? z;
  final double? vr;
  final bool up;
  final String? category;
  final String? announcement;
  final String? exchange;
  final String? link;

  SpikeEvent({
    required this.date,
    required this.ticker,
    required this.name,
    this.ret,
    this.z,
    this.vr,
    this.up = true,
    this.category,
    this.announcement,
    this.exchange,
    this.link,
  });

  factory SpikeEvent.fromJson(Map<String, dynamic> j) => SpikeEvent(
        date: j['date'] ?? '',
        ticker: j['ticker'] ?? '',
        name: j['name'] ?? '',
        ret: _d(j['ret']),
        z: _d(j['z']),
        vr: _d(j['vr']),
        up: j['direction'] != 'Down',
        category: _s(j['category']),
        announcement: _s(j['announcement']),
        exchange: _s(j['exchange']),
        link: _s(j['link']),
      );
}

class Headline {
  final String title;
  final String link;
  final String age;
  Headline(this.title, this.link, this.age);
}

class StockDetail {
  final StockSummary summary;
  final List<String> dates;
  final List<double?> close;
  final List<double?> ma20;
  final List<bool> eventFlags;
  final double? annVol;
  final double? beta;
  final double? mom5;
  final double? predMove;
  final double? predDir;
  final double? predR2;
  final int predN;
  final String sentimentLabel;
  final List<Headline> headlines;
  final List<SpikeEvent> events;
  final bool onDemand;

  StockDetail({
    required this.summary,
    required this.dates,
    required this.close,
    required this.ma20,
    required this.eventFlags,
    this.annVol,
    this.beta,
    this.mom5,
    this.predMove,
    this.predDir,
    this.predR2,
    this.predN = 0,
    this.sentimentLabel = 'neutral',
    this.headlines = const [],
    this.events = const [],
    this.onDemand = false,
  });

  factory StockDetail.fromJson(Map<String, dynamic> j) {
    final sent = j['sentiment'] is Map ? j['sentiment'] as Map : const {};
    final close = (j['close'] as List? ?? const []).map(_d).toList();
    final summaryJson = Map<String, dynamic>.from(j)
      ..['sentiment'] = sent['label'] ?? 'neutral'
      ..['spark'] = close.length > 30 ? close.sublist(close.length - 30) : close;
    return StockDetail(
      summary: StockSummary.fromJson(summaryJson),
      dates: (j['dates'] as List? ?? const []).cast<String>(),
      close: close,
      ma20: (j['ma20'] as List? ?? const []).map(_d).toList(),
      eventFlags: (j['event_flags'] as List? ?? const []).map((v) => v == true).toList(),
      annVol: _d(j['ann_vol']),
      beta: _d(j['beta']),
      mom5: _d(j['mom5']),
      predMove: _d(j['pred_move']),
      predDir: _d(j['pred_dir']),
      predR2: _d(j['pred_r2']),
      predN: _i(j['pred_n']),
      sentimentLabel: sent['label'] ?? 'neutral',
      headlines: (sent['headlines'] as List? ?? const [])
          .whereType<Map>()
          .map((h) => Headline(h['title'] ?? '', h['link'] ?? '', h['age'] ?? ''))
          .where((h) => h.title.isNotEmpty)
          .toList(),
      events: (j['events'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(SpikeEvent.fromJson)
          .toList(),
      onDemand: j['on_demand'] == true,
    );
  }
}
