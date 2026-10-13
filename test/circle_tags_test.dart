import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/api/client.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/data/db.dart';
import 'package:isconl/data/lesson_notes.dart';
import 'package:isconl/data/modules.dart';
import 'package:isconl/data/mutations.dart';
import 'package:isconl/data/outbox.dart';
import 'package:isconl/data/store.dart';
import 'package:isconl/data/sync.dart';
import 'package:isconl/data/vault_mirror.dart';
import 'package:isconl/services/narration.dart';
import 'package:isconl/services/session.dart';
import 'package:isconl/services/sms_ingest.dart';
import 'package:isconl/services/updater.dart';
import 'package:isconl/ui/views/circle_tags.dart';
import 'package:isconl/util/circle_tags.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A fixture hub: records every write and serves a fixed Circle.
class FakeHub extends ApiClient {
  FakeHub() : super(baseUrl: 'http://test', token: 'test');

  final List<Map<String, dynamic>> calls = [];

  @override
  Future<dynamic> postJson(String path, Map<String, dynamic> body, {bool cold = false}) async {
    calls.add({'path': path, 'body': body});
    return <String, dynamic>{'success': true, 'touched': 1};
  }

  @override
  Future<dynamic> getJson(String path, {bool cold = false}) async {
    if (path == '/api/circle') return {'people': people};
    return {};
  }
}

final people = <Map<String, dynamic>>[
  {'ID': 'P1', 'NAME': 'Asha', 'TAGS': 'family, mentor'},
  {'ID': 'P2', 'NAME': 'Baraka', 'TAGS': 'mentor,work'},
  {'ID': 'P3', 'NAME': 'Chebet', 'TAGS': '-'},
  {'ID': 'P4', 'NAME': 'Daudi', 'TAGS': 'work'},
];

class FakeSession extends SessionService {
  FakeSession(this._api);
  final FakeHub _api;
  @override
  ApiClient get api => _api;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<(AppServices, FakeHub)> build({bool online = true}) async {
    final rawDb = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        singleInstance: false,
        version: 4,
        onCreate: (db, _) async {
          await db.execute('CREATE TABLE snapshots (key TEXT PRIMARY KEY, json TEXT NOT NULL, fetched_at INTEGER NOT NULL)');
          await db.execute('''
            CREATE TABLE outbox (
              id INTEGER PRIMARY KEY AUTOINCREMENT, method TEXT NOT NULL, path TEXT NOT NULL, body TEXT NOT NULL,
              label TEXT NOT NULL, view TEXT NOT NULL, created_at INTEGER NOT NULL,
              status TEXT NOT NULL DEFAULT 'pending', error TEXT)''');
          await db.execute('''
            CREATE TABLE lesson_notes (course TEXT NOT NULL, file TEXT NOT NULL, text TEXT NOT NULL, anchor INTEGER,
              updated_at INTEGER NOT NULL, PRIMARY KEY (course, file))''');
          await ensureVaultMirrorTables(db);
        },
      ),
    );
    final db = AppDb.forTesting(rawDb);
    final api = FakeHub();
    final session = FakeSession(api);
    ApiClient apiOf() => session.api;
    final store = Store(db, apiOf);
    final outbox = OutboxService(db, apiOf);
    final sync = SyncEngine(store, outbox, apiOf);
    sync.online = online;
    final mutations = Mutations(store, outbox, sync, apiOf);
    await store.circle.patchLocal((_) => {'people': people});
    return (
      AppServices.forTesting(
        db: db,
        session: session,
        store: store,
        modules: ModuleLibrary(db, store, apiOf),
        narrator: Narrator(apiOf),
        sms: SmsIngest(apiOf),
        outbox: outbox,
        sync: sync,
        mutations: mutations,
        updater: UpdateService(apiOf),
        lessonNotes: LessonNotesRepository(apiOf: apiOf, mutations: mutations, db: db),
      ),
      api,
    );
  }

  group('the tag format', () {
    test('reads and writes the comma cell circle uses, with - as empty', () {
      expect(parseTags('mentor,work'), ['mentor', 'work']);
      expect(parseTags(' family, mentor '), ['family', 'mentor']);
      expect(parseTags('-'), isEmpty);
      expect(parseTags(null), isEmpty);
      expect(serializeTags(['a', 'b', 'a', ' ']), 'a, b');
      expect(serializeTags([]), '-');
    });

    test('counts each tag and sorts the most used first', () {
      expect(tagCounts(people).map((t) => '${t.tag}:${t.count}'), ['mentor:2', 'work:2', 'family:1']);
    });

    test('a change counts each person once, however many of the tags they carry', () {
      expect(peopleWithAnyTag(people, ['mentor']), 2);
      expect(peopleWithAnyTag(people, ['mentor', 'work']), 3);
      expect(peopleWithAnyTag(people, ['nope']), 0);
    });

    test('a tag name cannot break the cell', () {
      expect(cleanTag('  close\tfriends, old '), 'close friends old');
    });
  });

  group('tag writes', () {
    test('each write goes to its circle route with the body circle expects', () async {
      final (s, hub) = await build();
      await s.mutations.addPersonTag('P3', 'school');
      await s.mutations.removePersonTag('P1', 'family');
      await s.mutations.renameTag('work', 'job');
      await s.mutations.mergeTags(['mentor'], 'job');
      await s.mutations.deleteTag('job');
      expect(hub.calls, [
        {'path': '/api/circle/tags/add', 'body': {'personId': 'P3', 'tag': 'school'}},
        {'path': '/api/circle/tags/remove', 'body': {'personId': 'P1', 'tag': 'family'}},
        {'path': '/api/circle/tags/rename', 'body': {'from': 'work', 'to': 'job'}},
        {'path': '/api/circle/tags/merge', 'body': {'sources': ['mentor'], 'into': 'job'}},
        {'path': '/api/circle/tags/delete', 'body': {'tag': 'job'}},
      ]);
    });

    test('offline, a person tag is queued and shown at once; a rename, merge or delete is refused', () async {
      final (s, hub) = await build(online: false);
      final add = await s.mutations.addPersonTag('P3', 'school');
      expect(add.queued, isTrue);
      final p3 = (s.store.circle.value['people'] as List).firstWhere((p) => p['ID'] == 'P3');
      expect(p3['TAGS'], 'school');
      for (final r in [
        await s.mutations.renameTag('work', 'job'),
        await s.mutations.mergeTags(['mentor'], 'job'),
        await s.mutations.deleteTag('work'),
      ]) {
        expect(r.ok, isFalse);
        expect(r.queued, isFalse);
      }
      expect(await s.db.pendingCount(), 1, reason: 'only the person tag waits in the outbox');
      expect(hub.calls, isEmpty, reason: 'nothing reaches the network offline');
    });
  });

  testWidgets('the tag list shows counts, and delete says how many people it changes before doing it', (tester) async {
    late AppServices s;
    late FakeHub hub;
    await tester.runAsync(() async => (s, hub) = await build());
    await tester.pumpWidget(AppScope(services: s, child: const MaterialApp(home: CircleTagsScreen())));
    await tester.pumpAndSettle();
    expect(find.text('mentor'), findsOneWidget);
    expect(find.text('2 people'), findsNWidgets(2));
    expect(find.text('1 person'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tag-menu-work')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete from everyone'));
    await tester.pumpAndSettle();
    expect(find.textContaining('It comes off 2 people'), findsOneWidget);
    expect(hub.calls, isEmpty, reason: 'nothing changes before the confirm');
    await tester.tap(find.text('Delete'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(hub.calls.single, {'path': '/api/circle/tags/delete', 'body': {'tag': 'work'}});
  });
}
