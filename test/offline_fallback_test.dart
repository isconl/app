import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:isconl/api/client.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/ui/views/learning.dart';
import 'package:isconl/ui/widgets/common.dart';
import 'package:isconl/ui/widgets/offline_banner.dart';

import 'support/test_services.dart';

/// In-memory stand-in for DbResponseCache.
class MemCache implements ResponseCache {
  final Map<String, (dynamic, DateTime)> rows = {};
  @override
  Future<void> put(String path, dynamic value) async => rows[path] = (value, DateTime(2026, 10, 27, 9));
  @override
  Future<(dynamic, DateTime)?> get(String path) async => rows[path];
}

void main() {
  group('ApiClient offline fallback unit tests', () {
    // What the server does next: a JSON answer, a status, or no answer at all.
    late Future<http.Response> Function() next;
    ApiClient make(MemCache cache) => ApiClient(
          baseUrl: 'https://hub.test',
          token: 't',
          httpClient: MockClient((_) => next()),
        )..cache = cache;

    // BI26103095 (30 Oct 2026): on the light fleet hub answers some routes with its own JSON 5xx (an engine that is not
    // running there, slate being down). That is hub answering, so the server is reachable: no "server unreachable"
    // banner and no stored copy standing in for it. And a 404 on /api/notifications no longer signs Sconl out.
    test('hub answering a JSON 5xx is an answer, not an unreachable server', () async {
      final api = make(MemCache());
      next = () async => http.Response(jsonEncode({'ok': false, 'error': 'slate is not reachable'}), 503);
      await expectLater(api.getJson('/api/slate/matrix'), throwsA(isA<ApiException>().having((e) => e.answered, 'answered', isTrue)));
      expect(api.serverUnreachable, isFalse);
      next = () async => http.Response('<html>Bad gateway</html>', 502);
      await expectLater(api.getJson('/api/slate/matrix'), throwsA(isA<ApiException>()));
      expect(api.serverUnreachable, isTrue, reason: 'a non-JSON gateway page still means the server did not answer');
    });

    test('a 404 on /api/notifications does not end the session; only /api/state can', () async {
      var signedOut = 0;
      final api = make(MemCache())..onAuthFailure = () => signedOut++;
      next = () async => http.Response(jsonEncode({'error': 'Not found'}), 404);
      await expectLater(api.getJson('/api/notifications'), throwsA(isA<ApiException>()));
      expect(signedOut, 0);
      await expectLater(api.getJson('/api/state'), throwsA(isA<ApiException>()));
      expect(signedOut, 1);
    });

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

    test('hub answers 400 when spark cannot parse a lesson falls back to stored copy', () async {
      final cache = MemCache()
        ..rows['/api/learning/lesson?course=c1&file=l1.md'] =
            ({'content': 'stored markdown'}, DateTime(2026, 10, 27, 9));
      final api = make(cache);
      next = () async => http.Response(jsonEncode({'error': 'Deck refused to parse this lesson'}), 400);
      expect(await api.getJson('/api/learning/lesson?course=c1&file=l1.md'), {'content': 'stored markdown'});
      expect(api.serverUnreachable, isTrue);
      expect(api.servedFromCacheAt, DateTime(2026, 10, 27, 9));
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
  });

  group('Study course and lesson offline fallback widget tests', () {
    testWidgets('Study course screen with server unreachable shows stored library with no error state and no endless spinner', (tester) async {
      final testTime = DateTime(2026, 10, 27, 9);
      final api = ScriptedApi({
        '/api/learning': ApiException(503, 'Server unreachable'),
      });
      api.serverUnreachable = true;
      api.servedFromCacheAt = testTime;

      final services = (await tester.runAsync(() => buildTestServices(api, online: true)))!;

      final courseData = {
        'ID': 'distributed-systems',
        'TITLE': 'Distributed Systems',
        'lessons': [
          {
            'file': '01-consensus.md',
            'title': 'Consensus Models',
            'status': 'opened',
            'position': 1,
          }
        ],
      };

      await tester.pumpWidget(
        AppScope(
          services: services,
          child: MaterialApp(
            home: CourseDetailScreen(
              course: courseData,
              title: 'Distributed Systems',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Stored library / course is visible
      expect(find.text('Distributed Systems'), findsWidgets);
      expect(find.text('Consensus Models'), findsOneWidget);
      // Offline banner shows server unreachable with quiet last updated line
      expect(find.byType(OfflineBanner), findsOneWidget);
      expect(find.byKey(const Key('offline-banner-unreachable')), findsOneWidget);
      expect(find.textContaining('Server unreachable · showing what is on this phone'), findsOneWidget);
      // No endless spinner
      expect(find.byType(MiniSpinner), findsNothing);
      // No error state
      expect(find.byType(ErrorRetry), findsNothing);
    });

    testWidgets('Lesson screen with server unreachable falls back to stored lesson with quiet last updated line', (tester) async {
      final testTime = DateTime(2026, 10, 27, 9);
      final api = ScriptedApi({
        '/api/learning/lesson': ApiException(400, 'Deck refused to parse this lesson'),
      });
      api.serverUnreachable = true;
      api.servedFromCacheAt = testTime;

      final services = (await tester.runAsync(() => buildTestServices(api, online: true)))!;

      // Store cached copy in snapshots DB table
      final data = {
        'content': '# Consensus Models\n\nRaft and Paxos agree on state.',
        'title': 'Consensus Models',
        'updatedAt': '2026-10-27T09:00:00Z',
        'version': '1.0',
      };
      await tester.runAsync(() => services.db.putSnapshot(
        'lesson:distributed-systems/01-consensus.md',
        data,
      ));
      services.store.detail('lesson', 'distributed-systems/01-consensus.md', '/api/learning/lesson?course=distributed-systems&file=01-consensus.md').value = data;

      await tester.pumpWidget(
        AppScope(
          services: services,
          child: const MaterialApp(
            home: LessonScreen(
              course: 'distributed-systems',
              file: '01-consensus.md',
              title: 'Consensus Models',
              status: 'opened',
            ),
          ),
        ),
      );

      // Allow SnapshotView to hydrate from db and render
      await tester.pump();
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
      await tester.pump();

      // Stored lesson content is displayed
      expect(find.text('Consensus Models'), findsWidgets);
      expect(find.textContaining('Raft and Paxos agree on state'), findsOneWidget);
      // Quiet last updated line in offline banner
      expect(find.byType(OfflineBanner), findsOneWidget);
      expect(find.byKey(const Key('offline-banner-unreachable')), findsOneWidget);
      expect(find.textContaining('Server unreachable · showing what is on this phone'), findsOneWidget);
      // No endless spinner
      expect(find.byType(MiniSpinner), findsNothing);
      // No error state
      expect(find.byType(ErrorRetry), findsNothing);

      // Clean teardown
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 60)));
      await tester.pump();
    });
  });
}
