import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/data/db.dart';
import 'package:isconl/study/pick/index_cache.dart';
import 'package:isconl/study/pick/study_hash.dart';
import 'package:isconl/study/study_service.dart';
import 'package:isconl/theme.dart';
import 'package:isconl/ui/widgets/study_pick_card.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Map<String, dynamic> learning() => {
      'courses': [
        {
          'ID': 'corp',
          'GROUP_ID': 'g1',
          'lessons': [
            {'file': 'a.md', 'title': 'Alpha', 'status': 'done'},
            {'file': 'b.md', 'title': 'Beta', 'status': 'learning'},
            {'file': 'c.md', 'title': 'Gamma', 'status': 'new'},
          ],
        },
        {
          'ID': 'tech',
          'GROUP_ID': 'g2',
          'lessons': [
            {'file': 'x.md', 'title': 'Xi', 'status': 'new'},
          ],
        },
      ],
    };

class _Fetcher implements StudyIndexFetcher {
  _Fetcher(this.body);
  final String body;
  @override
  Future<IndexFetch> fetch(String? etag) async => IndexFetch(200, body: body, etag: 'e1');
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<AppDb> freshDb() async {
    final raw = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        singleInstance: false,
        version: 1,
        onCreate: (db, _) async {
          await db.execute('CREATE TABLE snapshots (key TEXT PRIMARY KEY, json TEXT NOT NULL, fetched_at INTEGER NOT NULL)');
          await db.execute('CREATE TABLE lesson_progress (course TEXT NOT NULL, file TEXT NOT NULL, status TEXT NOT NULL, updated_at INTEGER NOT NULL, PRIMARY KEY (course, file))');
          await db.execute('CREATE TABLE lesson_resume (course TEXT NOT NULL, file TEXT NOT NULL, scroll_pct INTEGER, fraction REAL, block_index INTEGER, words_left INTEGER, title TEXT, updated_at INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (course, file))');
        },
      ),
    );
    return AppDb.forTesting(raw);
  }

  test('with no cached index the pick is degraded, offline, with a reason and a notice, and skips read modules', () async {
    final svc = StudyPickService(await freshDb());
    final r = await svc.pick(learning());
    expect(r.degraded, isTrue);
    expect(r.notice, isNotNull);
    expect(r.pick.top, isNotNull);
    expect(r.pick.top!.reason, isNotEmpty);
    expect(r.pick.top!.card.id, isNot('corp/a.md'), reason: 'a read module is not offered again');
    expect(r.titles['corp/b.md'], 'Beta');
  });

  test('a module in progress is preferred, and a good cached index is used and not degraded', () async {
    final db = await freshDb();
    final svc = StudyPickService(db);
    final first = await svc.pick(learning());
    expect(first.pick.top!.card.id, 'corp/b.md', reason: 'momentum favours the module already started');
    final cache = StudyIndexCache(store: SnapshotIndexStore(db), hash: studyHash, thinIndex: () async => const []);
    final body = StudyPickService.encodeIndex([
      ...first.pick.top == null ? const [] : [first.pick.top!.card],
    ]);
    expect(await cache.refresh(_Fetcher(body)), isTrue);
    final second = await svc.pick(learning());
    expect(second.degraded, isFalse);
    expect(second.notice, isNull);
    // deleting the cache brings the degraded pick and its notice back
    await svc.forgetIndex();
    final third = await svc.pick(learning());
    expect(third.degraded, isTrue);
    expect(third.notice, isNotNull);
  });

  test('an empty library gives no pick and no error', () async {
    final r = await StudyPickService(await freshDb()).pick({'courses': []});
    expect(r.pick.top, isNull);
  });

  testWidgets('the card shows the pick, its reason, the alternates and the Why sheet', (tester) async {
    final res = (await tester.runAsync(() async => StudyPickService(await freshDb()).pick(learning())))!;
    String? opened;
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: StudyPickCard(data: learning(), onOpen: (c, l) => opened = '$c/$l', picker: (_) async => res),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('study-pick')), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.byKey(const Key('study-pick-degraded')), findsOneWidget);
    await tester.tap(find.byKey(const Key('study-pick-top')));
    expect(opened, 'corp/b.md');
    await tester.tap(find.byKey(const Key('study-pick-why')));
    await tester.pumpAndSettle();
    expect(find.text('Why this?'), findsWidgets);
    expect(find.text(res.pick.top!.reason), findsWidgets);
  });

  testWidgets('with nothing to pick the card takes no room', (tester) async {
    final res = (await tester.runAsync(() async => StudyPickService(await freshDb()).pick({'courses': []})))!;
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: Scaffold(body: StudyPickCard(data: const {}, onOpen: (_, _) {}, picker: (_) async => res))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('study-pick')), findsNothing);
  });

  test('the checked-in profile and the golden files are in the repository', () {
    expect(Directory('test/study/golden').listSync().whereType<File>().length, greaterThanOrEqualTo(8));
  });
}
