import 'dart:convert';

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
import 'package:isconl/services/course_standard.dart';
import 'package:isconl/services/narration.dart';
import 'package:isconl/services/session.dart';
import 'package:isconl/services/sms_ingest.dart';
import 'package:isconl/services/updater.dart';
import 'package:isconl/theme.dart';
import 'package:isconl/ui/views/learning.dart';
import 'package:isconl/ui/widgets/common.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _TestApiClient extends ApiClient {
  _TestApiClient() : super(baseUrl: 'http://test', token: 'test');
  final List<Map<String, dynamic>> recordedCalls = [];
  bool shouldFail = false;
  Map<String, dynamic>? lessonData;

  @override
  Future<dynamic> getJson(String path, {bool cold = false}) async {
    if (shouldFail) throw OfflineException();
    if (path.startsWith('/api/learning/lesson')) {
      if (lessonData != null) return lessonData!;
      final paragraphs = List.generate(40, (i) => 'Paragraph $i: Detailed technical content designed to take up vertical height.').join('\n\n');
      return {
        'content': paragraphs,
        'reviewedAt': '2026-09-22',
        'version': '3.0',
        'status': 'new',
      };
    }
    return {};
  }

  @override
  Future<dynamic> postJson(String path, Map<String, dynamic> body, {bool cold = false}) async {
    if (shouldFail) throw OfflineException();
    recordedCalls.add({'path': path, 'body': body});
    return {'ok': true};
  }
}

class _TestSessionService extends SessionService {
  _TestSessionService(this._api);
  final _TestApiClient _api;
  @override
  ApiClient get api => _api;
}

class _TestSyncEngine extends SyncEngine {
  _TestSyncEngine(super.store, super.outbox, super.apiOf);
  @override
  void start() {}
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<AppServices> buildTestServices({bool online = true, bool shouldFail = false}) async {
    final rawDb = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        singleInstance: false,
        version: 5,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE snapshots (
              key TEXT PRIMARY KEY,
              json TEXT NOT NULL,
              fetched_at INTEGER NOT NULL
            )''');
          await db.execute('''
            CREATE TABLE outbox (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              method TEXT NOT NULL,
              path TEXT NOT NULL,
              body TEXT NOT NULL,
              label TEXT NOT NULL,
              view TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              status TEXT NOT NULL DEFAULT 'pending',
              error TEXT
            )''');
          await db.execute('''
            CREATE TABLE lesson_resume (
              course TEXT NOT NULL,
              file TEXT NOT NULL,
              scroll_pct INTEGER NOT NULL,
              fraction REAL,
              updated_at INTEGER NOT NULL,
              PRIMARY KEY (course, file)
            )''');
          await db.execute('''
            CREATE TABLE lesson_notes (
              course TEXT NOT NULL,
              file TEXT NOT NULL,
              text TEXT NOT NULL,
              anchor INTEGER,
              updated_at INTEGER NOT NULL,
              PRIMARY KEY (course, file)
            )''');
          await db.execute('''
            CREATE TABLE lesson_progress (
              course TEXT NOT NULL,
              file TEXT NOT NULL,
              status TEXT NOT NULL,
              updated_at INTEGER NOT NULL,
              PRIMARY KEY (course, file)
            )''');
          await ensureVaultMirrorTables(db);
        },
      ),
    );
    final db = AppDb.forTesting(rawDb);
    final api = _TestApiClient();
    api.shouldFail = shouldFail;
    final session = _TestSessionService(api);
    ApiClient apiOf() => session.api;
    final store = Store(db, apiOf);
    final outbox = OutboxService(db, apiOf);
    final sync = _TestSyncEngine(store, outbox, apiOf);
    sync.online = online;
    final mutations = Mutations(store, outbox, sync, apiOf, db);
    final modules = ModuleLibrary(db, store, apiOf);
    final narrator = Narrator(apiOf);
    final sms = SmsIngest(apiOf);
    final updater = UpdateService(apiOf);
    final lessonNotes = LessonNotesRepository(apiOf: apiOf, mutations: mutations, db: db);

    return AppServices.forTesting(
      db: db,
      session: session,
      store: store,
      modules: modules,
      narrator: narrator,
      sms: sms,
      outbox: outbox,
      sync: sync,
      mutations: mutations,
      updater: updater,
      lessonNotes: lessonNotes,
    );
  }

  group('BI26092613: Local-first database, outbox queueing, and conflict resolution', () {
    test('in airplane mode: open, scroll, and mark done queue 3 outbox entries, and drain on network restore', () async {
      // Offline mode with failing network stub
      final services = await buildTestServices(online: false, shouldFail: true);
      final api = services.session.api as _TestApiClient;

      // 1. Open module: sets Opened locally and in outbox
      final openRes = await services.mutations.lessonProgress('med-anatomy', '00-orientation.md', 'opened');
      expect(openRes.queued, isTrue);
      expect(await services.db.lessonStatusLocal(course: 'med-anatomy', file: '00-orientation.md'), 'opened');

      // 2. Scroll past 10%: sets Learning locally and in outbox
      final scrollRes = await services.mutations.lessonProgress('med-anatomy', '00-orientation.md', 'learning');
      expect(scrollRes.queued, isTrue);
      expect(await services.db.lessonStatusLocal(course: 'med-anatomy', file: '00-orientation.md'), 'learning');

      // Scroll position saved locally and queued in outbox
      final resumeRes = await services.mutations.saveLessonResume(
        course: 'med-anatomy',
        lesson: '00-orientation.md',
        scrollPct: 25,
        fraction: 0.25,
      );
      expect(resumeRes.queued, isTrue);
      expect(await services.db.lessonResumeLocal(course: 'med-anatomy', file: '00-orientation.md'), 25);
      expect(await services.db.lessonResumeFractionLocal(course: 'med-anatomy', file: '00-orientation.md'), 0.25);

      // 3. Mark done: sets Done locally and in outbox
      final doneRes = await services.mutations.lessonProgress('med-anatomy', '00-orientation.md', 'done');
      expect(doneRes.queued, isTrue);
      expect(await services.db.lessonStatusLocal(course: 'med-anatomy', file: '00-orientation.md'), 'done');

      // Check outbox entries
      final pending = await services.db.pendingOutbox();
      final progressWrites = pending.where((r) => r['path'] == '/api/learning/progress').toList();
      expect(progressWrites.length, 3, reason: 'There are exactly 3 progress outbox entries: opened, learning, done');
      expect((jsonDecode(progressWrites[0]['body'] as String) as Map)['status'], 'opened');
      expect((jsonDecode(progressWrites[1]['body'] as String) as Map)['status'], 'learning');
      expect((jsonDecode(progressWrites[2]['body'] as String) as Map)['status'], 'done');

      // 4. Restore network and drain outbox
      services.sync.online = true;
      api.shouldFail = false;

      final delivered = await services.outbox.drain();
      expect(delivered, pending.length);
      expect(await services.db.pendingCount(), 0);

      // Verify delivered in FIFO sequence
      final deliveredProgress = api.recordedCalls.where((c) => c['path'] == '/api/learning/progress').toList();
      expect(deliveredProgress.length, 3);
      expect(deliveredProgress[0]['body']['status'], 'opened');
      expect(deliveredProgress[1]['body']['status'], 'learning');
      expect(deliveredProgress[2]['body']['status'], 'done');
    });

    test('a server "learning" does not downgrade a local "done"', () async {
      final services = await buildTestServices();

      // Local state is done
      await services.db.saveLessonStatusLocal(
        course: 'med-anatomy',
        file: '01-nerves.md',
        status: 'done',
      );
      expect(await services.db.lessonStatusLocal(course: 'med-anatomy', file: '01-nerves.md'), 'done');

      // Server returns learning
      final serverLearningSnapshot = {
        'courses': [
          {
            'ID': 'med-anatomy',
            'lessons': [
              {
                'file': '01-nerves.md',
                'status': 'learning',
              },
            ],
          },
        ],
      };

      final merged = await services.db.overlayVaultMirror('learning', serverLearningSnapshot);
      final lessons = (merged['courses'] as List)[0]['lessons'] as List;
      expect(lessons[0]['status'], 'done', reason: 'Server "learning" must not downgrade local "done"');

      // Same for detail snapshot
      final detailMerged = await services.db.overlayVaultMirror(
        'lesson:med-anatomy/01-nerves.md',
        {'course': 'med-anatomy', 'file': '01-nerves.md', 'status': 'learning'},
      );
      expect(detailMerged['status'], 'done');
    });

    test('status rank order: done > learning > opened > new and undo force', () async {
      expect(AppDb.statusRank('done'), 3);
      expect(AppDb.statusRank('learning'), 2);
      expect(AppDb.statusRank('opened'), 1);
      expect(AppDb.statusRank('new'), 0);
      expect(AppDb.statusRank(null), 0);

      expect(AppDb.mergeStatus('done', 'learning'), 'done');
      expect(AppDb.mergeStatus('learning', 'done'), 'done');
      expect(AppDb.mergeStatus('opened', 'new'), 'opened');
      expect(AppDb.mergeStatus('learning', 'opened'), 'learning');

      final services = await buildTestServices();
      await services.db.saveLessonStatusLocal(course: 'c', file: 'f', status: 'done');
      // Automatic downgrade attempt is ignored
      await services.db.saveLessonStatusLocal(course: 'c', file: 'f', status: 'learning');
      expect(await services.db.lessonStatusLocal(course: 'c', file: 'f'), 'done');

      // Explicit user undo (force = true) allows reverting
      await services.db.saveLessonStatusLocal(course: 'c', file: 'f', status: 'learning', force: true);
      expect(await services.db.lessonStatusLocal(course: 'c', file: 'f'), 'learning');
    });

    test('for scroll position the newest timestamp wins', () async {
      final services = await buildTestServices();

      // Newer timestamp saved first
      await services.db.saveLessonResumeLocal(
        course: 'med-anatomy',
        file: '01-nerves.md',
        scrollPct: 75,
        fraction: 0.75,
        updatedAt: 2000,
      );

      // Older timestamp attempts to overwrite
      await services.db.saveLessonResumeLocal(
        course: 'med-anatomy',
        file: '01-nerves.md',
        scrollPct: 20,
        fraction: 0.20,
        updatedAt: 1000,
      );

      // 75 remains because 2000 > 1000
      expect(await services.db.lessonResumeLocal(course: 'med-anatomy', file: '01-nerves.md'), 75);
      expect(await services.db.lessonResumeFractionLocal(course: 'med-anatomy', file: '01-nerves.md'), 0.75);

      // Even newer timestamp overwrites
      await services.db.saveLessonResumeLocal(
        course: 'med-anatomy',
        file: '01-nerves.md',
        scrollPct: 90,
        fraction: 0.90,
        updatedAt: 3000,
      );

      expect(await services.db.lessonResumeLocal(course: 'med-anatomy', file: '01-nerves.md'), 90);
      expect(await services.db.lessonResumeFractionLocal(course: 'med-anatomy', file: '01-nerves.md'), 0.90);
    });
  });

  group('BI26092613: UI widgets and reader lifecycle', () {
    // BI26101601: the standard tag at the foot of a module starts no database work in these tests.
    setUp(() => CourseStandard.instance.debugPreload(version: '4.5.0'));

    testWidgets('header line renders words, min read, reviewed date, and version', (tester) async {
      final services = (await tester.runAsync(() => buildTestServices()))!;
      final api = services.session.api as _TestApiClient;

      final doc = List.filled(1240, 'word').join(' ');
      final lessonData = {
        'content': doc,
        'reviewedAt': '2026-09-22',
        'version': '3.0',
        'status': 'new',
      };
      api.lessonData = lessonData;
      await tester.runAsync(() => services.db.putSnapshot('lesson:med-anatomy/03-heart.md', lessonData));
      services.store.detail(
        'lesson',
        'med-anatomy/03-heart.md',
        '/api/learning/lesson?course=med-anatomy&file=03-heart.md',
      ).value = lessonData;

      await tester.pumpWidget(
        AppScope(
          services: services,
          child: const MaterialApp(
            home: LessonScreen(
              course: 'med-anatomy',
              file: '03-heart.md',
              title: 'Heart',
              status: 'new',
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
      await tester.pump();

      expect(
        find.text('1,240 words · 6 min read · reviewed 22 Sep 2026 · v3.0'),
        findsOneWidget,
      );
    });

    testWidgets('opening module sets Opened, scrolling past 10% sets Learning, and Mark as done shows Done · undo', (tester) async {
      tester.view.physicalSize = const Size(600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final services = (await tester.runAsync(() => buildTestServices(online: false)))!;
      final api = services.session.api as _TestApiClient;

      final paragraphs = List.generate(40, (i) => 'Paragraph $i: Detailed technical content designed to take up vertical height.').join('\n\n');
      final lessonData = {
        'content': paragraphs,
        'reviewedAt': '2026-09-22',
        'version': '3.0',
        'status': 'new',
      };
      api.lessonData = lessonData;
      await tester.runAsync(() => services.db.putSnapshot('lesson:med-anatomy/00-orientation.md', lessonData));
      services.store.detail(
        'lesson',
        'med-anatomy/00-orientation.md',
        '/api/learning/lesson?course=med-anatomy&file=00-orientation.md',
      ).value = lessonData;

      await tester.pumpWidget(
        AppScope(
          services: services,
          child: const MaterialApp(
            home: LessonScreen(
              course: 'med-anatomy',
              file: '00-orientation.md',
              title: 'Orientation',
              status: 'new',
              trackColor: Color(0xFF00AA55),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
      await tester.pump();

      // 1. Opened pill is selected
      final openedPill = tester.widget<Pill>(find.widgetWithText(Pill, 'Opened'));
      expect(openedPill.selected, isTrue);

      // 2. Scroll past 10%
      final scrollableFinder = find.byType(Scrollable).first;
      final scrollState = tester.state<ScrollableState>(scrollableFinder);
      final maxExtent = scrollState.position.maxScrollExtent;
      expect(maxExtent, greaterThan(0));

      scrollState.position.jumpTo(maxExtent * 0.25);
      await tester.pump();
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
      await tester.pump();

      final learningPill = tester.widget<Pill>(find.widgetWithText(Pill, 'Learning'));
      expect(learningPill.selected, isTrue);

      // 3. Mark as done button
      final markDoneFinder = find.text('Mark as done');
      expect(markDoneFinder, findsOneWidget);
      await tester.ensureVisible(markDoneFinder);
      await tester.pumpAndSettle();

      await tester.tap(markDoneFinder);
      await tester.pump();
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
      await tester.pump();

      final donePill = tester.widget<Pill>(find.widgetWithText(Pill, 'Done'));
      expect(donePill.selected, isTrue);
      expect(find.text('Done · undo'), findsOneWidget);

      // 4. Undo within 5 seconds
      await tester.tap(find.text('Done · undo'));
      await tester.pump();
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
      await tester.pump();

      final revertedLearningPill = tester.widget<Pill>(find.widgetWithText(Pill, 'Learning'));
      expect(revertedLearningPill.selected, isTrue);
      expect(find.text('Mark as done'), findsOneWidget);

      // Mark as done again and wait 5 seconds -> changes to Completed
      await tester.tap(find.text('Mark as done'));
      await tester.pump();
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
      expect(find.text('Done · undo'), findsOneWidget);

      // Advance clock past 5 seconds
      await tester.pump(const Duration(seconds: 6));
      expect(find.text('Completed'), findsOneWidget);

      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    });

    testWidgets('BI26100537: module end shows a green Mark as done, then Previous Module and Next Module side by side', (tester) async {
      tester.view.physicalSize = const Size(600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final services = (await tester.runAsync(() => buildTestServices(online: false)))!;
      final api = services.session.api as _TestApiClient;
      final lessonData = {'content': 'Short module.', 'reviewedAt': '2026-09-22', 'version': '4.0', 'status': 'new'};
      api.lessonData = lessonData;
      for (final f in ['00-a.md', '01-b.md', '02-c.md']) {
        await tester.runAsync(() => services.db.putSnapshot('lesson:med-anatomy/$f', lessonData));
        services.store.detail('lesson', 'med-anatomy/$f', '/api/learning/lesson?course=med-anatomy&file=$f').value = lessonData;
      }
      final all = [
        for (final f in ['00-a.md', '01-b.md', '02-c.md']) {'file': f, 'title': f, 'status': 'new'},
      ];

      Future<void> open(String file) async {
        await tester.pumpWidget(AppScope(
          services: services,
          child: MaterialApp(
            key: UniqueKey(),
            home: LessonScreen(course: 'med-anatomy', file: file, title: file, status: 'new', allLessons: all, trackColor: const Color(0xFF3355CC)),
          ),
        ));
        await tester.pump();
        await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
        await tester.pump();
      }

      await open('01-b.md');
      final done = find.byKey(const Key('mark-as-done'));
      await tester.ensureVisible(done);
      final doneStyle = tester.widget<FilledButton>(done).style!;
      expect(doneStyle.backgroundColor!.resolve({}), C.green, reason: 'success green, not the track colour');
      final prev = find.byKey(const Key('previous-module'));
      final next = find.byKey(const Key('next-module'));
      expect(find.text('Previous Module'), findsOneWidget);
      expect(find.text('Next Module'), findsOneWidget);
      expect(tester.getTopLeft(prev).dy, tester.getTopLeft(next).dy, reason: 'side by side');
      expect(tester.getSize(prev).width, tester.getSize(next).width, reason: 'equal width');
      expect(tester.getTopLeft(prev).dy, greaterThan(tester.getBottomLeft(done).dy - 1), reason: 'below Mark as done');
      expect(tester.widget<OutlinedButton>(find.descendant(of: prev, matching: find.byType(OutlinedButton))).onPressed, isNotNull);

      // The first module: Previous stays, disabled, with the same label.
      await open('00-a.md');
      await tester.ensureVisible(find.byKey(const Key('next-module')));
      expect(find.text('Previous Module'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(find.descendant(of: find.byKey(const Key('previous-module')), matching: find.byType(OutlinedButton))).onPressed, isNull);
      expect(tester.widget<OutlinedButton>(find.descendant(of: find.byKey(const Key('next-module')), matching: find.byType(OutlinedButton))).onPressed, isNotNull);
      await open('02-c.md');
      await tester.ensureVisible(find.byKey(const Key('previous-module')));
      expect(tester.widget<OutlinedButton>(find.descendant(of: find.byKey(const Key('next-module')), matching: find.byType(OutlinedButton))).onPressed, isNull);
    });
  });
}
