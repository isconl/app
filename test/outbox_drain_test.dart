// BI26111590: one write the server cannot take never holds up the rest of the outbox.
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/api/client.dart';
import 'package:isconl/data/db.dart';
import 'package:isconl/data/outbox.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Api extends ApiClient {
  _Api(this.answer, {this.stateAlive = true}) : super(baseUrl: 'http://test', token: 'test');

  /// path -> what the server does with a POST there: 'ok', '404', '503', 'nothing'.
  final Map<String, String> answer;
  final bool stateAlive;
  final List<String> sent = [];

  @override
  Future<dynamic> postJson(String path, Map<String, dynamic> body, {bool cold = false}) async {
    switch (answer[path] ?? 'ok') {
      case '404':
        throw ApiException(404, 'Not found (or session expired)', authSuspect: true);
      case '503':
        throw ApiException(503, 'that part of iSconl is not running on this server', answered: true);
      case 'nothing':
        throw ApiException(502, 'Bad gateway');
    }
    sent.add(path);
    return {'ok': true};
  }

  @override
  Future<dynamic> getJson(String path, {bool cold = false, bool stored = true}) async {
    if (path == '/api/state' && !stateAlive) throw ApiException(404, 'Session expired', authSuspect: true);
    return {};
  }
}

Future<AppDb> _db() async {
  final raw = await databaseFactory.openDatabase(inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false, version: 1, onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE outbox (
            id INTEGER PRIMARY KEY AUTOINCREMENT, method TEXT NOT NULL, path TEXT NOT NULL, body TEXT NOT NULL,
            label TEXT NOT NULL, view TEXT NOT NULL, created_at INTEGER NOT NULL,
            status TEXT NOT NULL DEFAULT 'pending', error TEXT)''');
      }));
  return AppDb.forTesting(raw);
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<OutboxService> queue(AppDb db, _Api api, List<String> paths) async {
    final o = OutboxService(db, () => api);
    for (final p in paths) {
      await o.enqueue(path: p, body: {'x': 1}, label: p, view: 'test');
    }
    return o;
  }

  test('a write to a part not on the server (404) is skipped, the rest go', () async {
    final db = await _db();
    final api = _Api({'/api/circle/touch': '404'});
    final o = await queue(db, api, ['/api/circle/touch', '/api/tasks/update', '/api/ideas/add']);
    final n = await o.drain();
    expect(n, 2);
    expect(api.sent, ['/api/tasks/update', '/api/ideas/add']);
    expect(o.pending, 1, reason: 'the skipped write waits for its engine, it is not lost');
    expect(o.failed, 0);
  });

  test('hub 503 "not running" is skipped and kept, never marked failed', () async {
    final db = await _db();
    final api = _Api({'/api/journal/add': '503'});
    final o = await queue(db, api, ['/api/journal/add', '/api/tasks/update']);
    expect(await o.drain(), 1);
    expect(o.pending, 1);
    expect(o.failed, 0);
  });

  test('a dead session still stops the drain', () async {
    final db = await _db();
    final api = _Api({'/api/tasks/update': '404'}, stateAlive: false);
    final o = await queue(db, api, ['/api/tasks/update', '/api/ideas/add']);
    expect(await o.drain(), 0);
    expect(o.lastError, 'session expired');
    expect(o.pending, 2);
  });

  test('no answer at all still stops the pass and keeps order', () async {
    final db = await _db();
    final api = _Api({'/a': 'nothing'});
    final o = await queue(db, api, ['/ok1', '/a', '/ok2']);
    await o.drain();
    expect(api.sent, ['/ok1']);
    expect(o.pending, 2);
  });
}
