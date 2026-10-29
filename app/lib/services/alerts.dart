import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../config.dart';

/// On-device notifications, no push server needed. An hourly background job
/// checks the tiny meta.json; when a new trading day's data lands (~7:30 pm IST)
/// it sends:
///  * the free evening digest ("32 stocks moved on their own · 1 is on your list"),
///  * and, for Pro, one alert per watchlist stock that spiked.
/// Taps open the app on the right screen via [Alerts.tapped].
class Alerts {
  static const _task = 'spikewise.check_spikes';
  static const digestKey = 'digest_on';
  static const namedKey = 'alerts_on';
  static const _digestSeenKey = 'digest_last_date';
  static const _namedSeenKey = 'alerts_last_seen_date';
  static final _notifications = FlutterLocalNotificationsPlugin();

  /// Payload of the notification the user tapped: 'tonight' or 'stock:TICKER|DATE'.
  static final tapped = ValueNotifier<String?>(null);

  static Future<void> init() async {
    await _notifications.initialize(
      const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      onDidReceiveNotificationResponse: (r) => tapped.value = r.payload,
    );
    final launch = await _notifications.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      tapped.value = launch!.notificationResponse?.payload;
    }
    await Workmanager().initialize(alertsCallbackDispatcher);
  }

  /// Turns the digest (free) or named alerts (Pro) on/off. Returns false when the
  /// user denied the notification permission.
  static Future<bool> set(String key, bool on, String latestMarketDate) async {
    final prefs = await SharedPreferences.getInstance();
    if (on) {
      final android = _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (!(await android?.requestNotificationsPermission() ?? true)) {
        return false;
      }
      // Start from today's data, so nothing old floods in.
      await prefs.setString(
          key == digestKey ? _digestSeenKey : _namedSeenKey, latestMarketDate);
    }
    await prefs.setBool(key, on);
    await _sync(prefs);
    return true;
  }

  static Future<void> _sync(SharedPreferences prefs) async {
    final any = (prefs.getBool(digestKey) ?? false) ||
        ((prefs.getBool(namedKey) ?? false) &&
            (prefs.getBool('pro_active') ?? false));
    if (any) {
      await Workmanager().registerPeriodicTask(
        _task,
        _task,
        frequency: const Duration(hours: 1),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingWorkPolicy.keep,
      );
    } else {
      await Workmanager().cancelByUniqueName(_task);
    }
  }

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
        'spikes', 'Evening summary and spike alerts',
        channelDescription:
            'After market close: how many stocks moved on their own, and your stocks',
        importance: Importance.defaultImportance),
  );

  static Future<void> runCheck({DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    final digest = prefs.getBool(digestKey) ?? false;
    final named = (prefs.getBool(namedKey) ?? false) &&
        (prefs.getBool('pro_active') ?? false);
    if (!digest && !named) return;

    // Evenings only (7 pm – 11 pm IST): a calm, predictable slot, never at night.
    final ist = (now ?? DateTime.now())
        .toUtc()
        .add(const Duration(hours: 5, minutes: 30));
    if (ist.hour < 19 || ist.hour >= 23) return;

    final dio = Dio();
    final meta = jsonDecode((await dio.get<String>('$kDataUrl/meta.json',
            options: Options(responseType: ResponseType.plain)))
        .data!) as Map;
    final day = meta['last_market_date'] as String? ?? '';
    final today = ist.toIso8601String().substring(0, 10);
    if (day != today) return; // today's build hasn't landed yet (or a holiday)
    final digestDue =
        digest && day.compareTo(prefs.getString(_digestSeenKey) ?? '') > 0;
    final namedSeen = prefs.getString(_namedSeenKey) ?? '';
    final namedDue = named && day.compareTo(namedSeen) > 0;
    if (!digestDue && !namedDue) return;

    final events = (jsonDecode((await dio.get<String>('$kDataUrl/events.json',
                    options: Options(responseType: ResponseType.plain)))
                .data ??
            '[]') as List)
        .whereType<Map>()
        .toList();
    final watch =
        (prefs.getStringList('watchlist') ?? kDefaultWatchlist).toSet();
    final c = digestCounts(events, day, watch);

    if (digestDue) {
      await _notifications.show(1, digestTitle(c), digestBody(c), _details,
          payload: 'tonight');
      await prefs.setString(_digestSeenKey, day);
    }
    if (namedDue) {
      final fresh = events
          .where((e) =>
              watch.contains(e['ticker']) &&
              (e['date'] ?? '').compareTo(namedSeen) > 0)
          .take(3);
      for (final e in fresh) {
        final ret = (e['ret'] as num?)?.toDouble() ?? 0;
        final z = (e['z'] as num?)?.toDouble() ?? 0;
        final vr = (e['vr'] as num?)?.toDouble();
        await _notifications.show(
          (e['ticker'] as String).hashCode & 0x7fffffff,
          '${e['ticker']} ${ret >= 0 ? '+' : '−'}${(ret.abs() * 100).toStringAsFixed(1)}%: '
          '${z >= 0 ? 'better' : 'worse'} than NIFTY explains',
          e['category'] != null
              ? 'Filing near this date: ${e['category']}. Tap to read it.'
              : '${vr == null ? '' : '${vr.toStringAsFixed(1)}× usual volume · '}No company filing found yet.',
          _details,
          payload: 'stock:${e['ticker']}|${e['date']}',
        );
      }
      await prefs.setString(_namedSeenKey, day);
    }
  }
}

typedef DigestCounts = ({int total, int filed, int yours});

@visibleForTesting
DigestCounts digestCounts(List<Map> events, String day, Set<String> watch) {
  final todays = events.where((e) => e['date'] == day).toList();
  return (
    total: todays.length,
    filed: todays.where((e) => e['announcement'] != null).length,
    yours: todays.where((e) => watch.contains(e['ticker'])).length,
  );
}

String digestTitle(DigestCounts c) => c.total == 0
    ? 'A quiet day: no stock moved much more than NIFTY'
    : '${c.total} stocks moved on their own today';

String digestBody(DigestCounts c) {
  final filed = c.total == 0 ? '' : '${c.filed} near a company filing · ';
  return c.yours == 0
      ? '${filed}Your stocks moved with the market.'
      : '$filed${c.yours} ${c.yours == 1 ? 'is' : 'are'} on your list. Tap to see.';
}

@pragma('vm:entry-point')
void alertsCallbackDispatcher() {
  Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      await Alerts._notifications.initialize(const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher')));
      await Alerts.runCheck();
    } catch (_) {
      // Network hiccup -- the next hourly run will retry.
    }
    return true;
  });
}
