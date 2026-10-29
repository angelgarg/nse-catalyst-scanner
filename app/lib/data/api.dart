import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import 'models.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

/// Network access with an offline copy of every CDN file in SharedPreferences,
/// so the app opens instantly and still works without signal.
class Api {
  Api(this._prefs, {Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 30),
            ));

  final SharedPreferences _prefs;
  final Dio _dio;

  Future<dynamic> _cdn(String path, {bool preferCache = false}) async {
    final key = 'cache:$path';
    final cached = _prefs.getString(key);
    if (preferCache && cached != null) return jsonDecode(cached);
    try {
      final res = await _dio.get<String>('$kDataUrl/$path',
          options: Options(responseType: ResponseType.plain));
      final body = res.data ?? '';
      await _prefs.setString(key, body);
      return jsonDecode(body);
    } on DioException catch (e) {
      if (cached != null) return jsonDecode(cached);
      if (e.response?.statusCode == 404) throw ApiException('not_found');
      throw ApiException('Could not reach the server. Check your connection.');
    }
  }

  Future<DataMeta> meta() async => DataMeta.fromJson(await _cdn('meta.json'));

  Future<RemoteConfig> config() async {
    try {
      return RemoteConfig.fromJson(await _cdn('config.json'));
    } catch (_) {
      return const RemoteConfig();
    }
  }

  Future<List<StockSummary>> summary() async => (await _cdn('summary.json') as List)
      .whereType<Map<String, dynamic>>()
      .map(StockSummary.fromJson)
      .toList();

  Future<List<SpikeEvent>> events() async => (await _cdn('events.json') as List)
      .whereType<Map<String, dynamic>>()
      .map(SpikeEvent.fromJson)
      .toList();

  Future<List<UniverseEntry>> universe() async =>
      (await _cdn('universe.json', preferCache: true) as List)
          .whereType<Map<String, dynamic>>()
          .map(UniverseEntry.fromJson)
          .toList();

  /// Daily-build detail; falls back to on-demand server analysis for tickers
  /// outside the daily universe.
  Future<StockDetail> detail(String ticker) async {
    try {
      return StockDetail.fromJson(await _cdn('stocks/${fileKey(ticker)}.json'));
    } on ApiException catch (e) {
      if (e.message != 'not_found') rethrow;
    }
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '$kApiUrl/api/v1/analyze/${Uri.encodeComponent(fileKey(ticker))}',
        options: Options(receiveTimeout: const Duration(seconds: 90)),
      );
      return StockDetail.fromJson(res.data!);
    } on DioException catch (e) {
      final err = e.response?.data;
      throw ApiException(err is Map && err['error'] is String
          ? err['error']
          : 'Analysis server is waking up. Try again in a minute.');
    }
  }

  Future<void> sendFeedback(Map<String, dynamic> body) async {
    try {
      await _dio.post('$kApiUrl/api/v1/feedback',
          data: body, options: Options(receiveTimeout: const Duration(seconds: 90)));
    } on DioException catch (e) {
      final err = e.response?.data;
      throw ApiException(err is Map && err['error'] is String
          ? err['error']
          : 'Could not send. Check your connection and try again.');
    }
  }
}
