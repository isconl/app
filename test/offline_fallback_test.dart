import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:isconl/api/client.dart';

/// In-memory stand-in for DbResponseCache.
class MemCache implements ResponseCache {
  final Map<String, (dynamic, DateTime)> rows = {};
  @override
  Future<void> put(String path, dynamic value) async => rows[path] = (value, DateTime(2026, 10, 27, 9));
  @override
  Future<(dynamic, DateTime)?> get(String path) async => rows[path];
}

void main() {
  // What the server does next: a JSON answer, a status, or no answer at all.
  late Future<http.Response> Function() next;
  ApiClient make(MemCache cache) => ApiClient(
        baseUrl: 'https://hub.test',
        token: 't',
        httpClient: MockClient((_) => next()),
      )..cache = cache;

  test('a good answer is stored, and served when the tunnel has no connector (530)', () async {
    final cache = MemCache();
    final api = make(cache);
    next = () async => http.Response(jsonEncode({'lessons': [1, 2]}), 200);
    expect(await api.getJson('/api/learning/manifest'), {'lessons': [1, 2]});
    expect(api.serverUnreachable, isFalse);

    next = () async => http.Response('<html>1033</html>', 530);
    expect(await api.getJson('/api/learning/manifest'), {'lessons': [1, 2]});
    expect(api.serverUnreachable, isTrue);
    expect(api.servedFromCacheAt, DateTime(2026, 10, 27, 9));
  });

  test('no network serves the stored copy; nothing stored still throws', () async {
    final cache = MemCache()..rows['/api/state'] = ({'ok': true}, DateTime(2026, 10, 1));
    final api = make(cache);
    // The real IOClient turns a SocketException into a ClientException, which is what the client catches.
    next = () async => throw http.ClientException('down');
    expect(await api.getJson('/api/state'), {'ok': true});
    await expectLater(api.getJson('/api/never-fetched'), throwsA(isA<OfflineException>()));
  });

  test('a 4xx is an answer and is never covered by a stored copy', () async {
    final cache = MemCache()..rows['/api/state'] = ({'ok': true}, DateTime(2026, 10, 1));
    final api = make(cache);
    next = () async => http.Response(jsonEncode({'error': 'Locked out'}), 429);
    await expectLater(api.getJson('/api/state'), throwsA(isA<ApiException>()));
    expect(api.serverUnreachable, isFalse);
  });

  test('a failure never replaces the stored copy, and the server answering clears the flag', () async {
    final cache = MemCache();
    final api = make(cache);
    var calls = 0;
    api.onReachabilityChanged = () => calls++;
    next = () async => http.Response(jsonEncode({'v': 1}), 200);
    await api.getJson('/x');
    next = () async => http.Response('', 502);
    await api.getJson('/x');
    expect(cache.rows['/x']!.$1, {'v': 1});
    next = () async => http.Response(jsonEncode({'v': 2}), 200);
    expect(await api.getJson('/x'), {'v': 2});
    expect(api.serverUnreachable, isFalse);
    expect(api.servedFromCacheAt, isNull);
    expect(calls, greaterThanOrEqualTo(2));
  });

  test('stored: false neither stores nor falls back (Snapshot keeps its own copy)', () async {
    final cache = MemCache();
    final api = make(cache);
    next = () async => http.Response(jsonEncode({'v': 1}), 200);
    await api.getJson('/y', stored: false);
    expect(cache.rows, isEmpty);
    next = () async => http.Response('', 503);
    await expectLater(api.getJson('/y', stored: false), throwsA(isA<ApiException>()));
    expect(api.serverUnreachable, isTrue);
  });
}
