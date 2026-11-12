import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spikewise/config.dart';
import 'package:spikewise/data/api.dart';

/// Answers from a map of URL -> body; URLs on [blocked] fail like a DNS block.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.bodies, this.blocked);
  final Map<String, String> bodies;
  final Set<String> blocked;
  final requested = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? _, Future<void>? __) async {
    final url = o.uri.toString();
    requested.add(url);
    if (blocked.any(url.startsWith)) {
      throw DioException(requestOptions: o, type: DioExceptionType.badCertificate);
    }
    final body = bodies[url];
    return ResponseBody.fromString(body ?? '{}', body == null ? 404 : 200);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  const meta = {'last_market_date': '2026-11-11', 'generated': 'x', 'stocks': 451};

  Future<(Api, _FakeAdapter)> make(Set<String> blocked) async {
    SharedPreferences.setMockInitialValues({});
    final adapter = _FakeAdapter({
      '$kDataUrl/meta.json': jsonEncode(meta),
      '$kDataMirrorUrl/meta.json': jsonEncode(meta),
      '$kDataMirrorUrl/summary.json': '[]',
    }, blocked);
    final dio = Dio()..httpClientAdapter = adapter;
    return (Api(await SharedPreferences.getInstance(), dio: dio), adapter);
  }

  test('uses the CDN when it is reachable', () async {
    final (api, adapter) = await make({});
    expect((await api.meta()).stocks, 451);
    expect(adapter.requested, ['$kDataUrl/meta.json']);
  });

  test('falls back to the Render mirror when Pages is blocked, then sticks to it', () async {
    final (api, adapter) = await make({kDataUrl});
    expect((await api.meta()).stocks, 451);
    expect(await api.summary(), isEmpty);
    expect(adapter.requested,
        ['$kDataUrl/meta.json', '$kDataMirrorUrl/meta.json', '$kDataMirrorUrl/summary.json']);
  });

  test('a real 404 from the CDN is not retried on the mirror', () async {
    final (api, adapter) = await make({});
    await expectLater(api.events(), throwsA(isA<ApiException>()));
    expect(adapter.requested, ['$kDataUrl/events.json']);
  });
}
