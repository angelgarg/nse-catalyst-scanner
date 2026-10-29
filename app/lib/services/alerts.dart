import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../config.dart';

/// On-device spike alerts: a periodic background job downloads the daily
/// events file and notifies about new spikes in the user's watchlist.
/// No push server or Firebase needed.
class Alerts {
  static const _task = 'spikewise.check_spikes';
  static const _lastSeenKey = 'alerts_last_seen_date';
  static final _notifications = FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    await _notifications.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher')));
    await Workmanager().initialize(alertsCallbackDispatcher);
  }

  /// Returns false when the user denied the notification permission.
  static Future<bool> enable(String latestMarketDate) async {
    final android = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final granted = await android?.requestNotificationsPermission() ?? true;
    if (!granted) return false;
    final prefs = await SharedPreferences.getInstance();
    // Only alert on spikes after today -- don't flood with history.
    await prefs.setString(_lastSeenKey, latestMarketDate);
    await Workmanager().registerPeriodicTask(
      _task,
      _task,
      frequency: const Duration(hours: 3),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.keep,
    );
    return true;
  }

  static Future<void> disable() => Workmanager().cancelByUniqueName(_task);

  static Future<void> runCheck() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('alerts_on') ?? false) ||
        !(prefs.getBool('pro_active') ?? false)) {
      return;
    }
    final watch =
        (prefs.getStringList('watchlist') ?? kDefaultWatchlist).toSet();
    final lastSeen = prefs.getString(_lastSeenKey) ?? '';
    final res = await Dio().get<String>('$kDataUrl/events.json',
        options: Options(responseType: ResponseType.plain));
    final events = (jsonDecode(res.data ?? '[]') as List).whereType<Map>();
    final fresh = events
        .where((e) =>
            watch.contains(e['ticker']) &&
            (e['date'] ?? '').compareTo(lastSeen) > 0)
        .toList();
    if (fresh.isEmpty) return;

    const details = NotificationDetails(
      android: AndroidNotificationDetails('spikes', 'Spike alerts',
          channelDescription:
              'Evening alert when a stock you follow moves on its own',
          importance: Importance.high,
          priority: Priority.high),
    );
    for (final e in fresh.take(5)) {
      final ret = (e['ret'] as num?)?.toDouble() ?? 0;
      final verb = ret >= 0 ? 'rose' : 'fell';
      final vr = (e['vr'] as num?)?.toDouble();
      final why = e['category'] != null
          ? 'Filing near this date: ${e['category']}. Open Spikewise to read it.'
          : '${vr == null ? '' : '${vr.toStringAsFixed(1)}× usual volume · '}No company filing found yet.';
      await _notifications.show(
        (e['ticker'] as String).hashCode & 0x7fffffff,
        '${e['ticker']} $verb ${(ret.abs() * 100).toStringAsFixed(1)}% on its own (${_day(e['date'] as String)})',
        why,
        details,
      );
    }
    final newest = fresh
        .map((e) => e['date'] as String)
        .reduce((a, b) => a.compareTo(b) > 0 ? a : b);
    await prefs.setString(_lastSeenKey, newest);
  }
}

String _day(String iso) {
  const m = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  final d = DateTime.tryParse(iso);
  return d == null ? iso : '${d.day} ${m[d.month - 1]}';
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
      // Network hiccup -- the next periodic run will retry.
    }
    return true;
  });
}
