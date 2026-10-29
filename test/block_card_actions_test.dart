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
import 'package:isconl/services/narration.dart';
import 'package:isconl/services/session.dart';
import 'package:isconl/services/sms_ingest.dart';
import 'package:isconl/services/updater.dart';
import 'package:isconl/ui/views/task_detail.dart';
import 'package:isconl/ui/widgets/block_card.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class TestApiClient extends ApiClient {
  TestApiClient() : super(baseUrl: 'http://test', token: 'test');

  final List<Map<String, dynamic>> recordedCalls = [];

  @override
  Future<dynamic> postJson(String path, Map<String, dynamic> body, {bool cold = false}) async {
    recordedCalls.add({'path': path, 'body': body});
    return <String, dynamic>{'ok': true};
  }

  @override
  Future<dynamic> getJson(String path, {bool cold = false}) async {
    if (path.contains('/api/tasks/detail')) {
      return {
        'task': {
          'ID': 'T101',
          'TITLE': 'Refactor day blocks',
          'STATUS': 'today',
          'PRIORITY': 'high',
          'KIND': 'innovator',
          'ESTIMATE': 3,
        },
        'effort': {'range': '1-2h', 'sitting': 'yes'},
        'tools': [],
        'brief': {},
        'draft': {},
      };
    }
    return {};
  }
}

class TestSessionService extends SessionService {
  TestSessionService(this._api);
  final TestApiClient _api;
  @override
  ApiClient get api => _api;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<AppServices> buildTestServices({bool online = true}) async {
    final rawDb = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        singleInstance: false,
        version: 4,
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
            CREATE TABLE lesson_notes (
              course TEXT NOT NULL,
              file TEXT NOT NULL,
              text TEXT NOT NULL,
              anchor INTEGER,
              updated_at INTEGER NOT NULL,
              PRIMARY KEY (course, file)
            )''');
          await ensureVaultMirrorTables(db);
        },
      ),
    );

    final db = AppDb.forTesting(rawDb);
    final api = TestApiClient();
    final session = TestSessionService(api);
    ApiClient apiOf() => session.api;
    final store = Store(db, apiOf);
    final outbox = OutboxService(db, apiOf);
    final sync = SyncEngine(store, outbox, apiOf);
    sync.online = online;
    final mutations = Mutations(store, outbox, sync, apiOf);
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

  final fixtureBlocks = [
    {
      'id': 'innovator',
      'name': 'Innovator',
      'axis': 'innovator',
      'startClock': '08:00',
      'endClock': '12:00',
      'placeable': true,
      'slots': 4,
      'tasks': [
        {
          'id': 'T1',
          'title': 'Build day block actions',
          'priority': 'high',
          'due': 'today',
          'pinned': true,
          'why': 'is due today and matches engineering',
        },
        {
          'id': 'T2',
          'title': 'Test offline queueing',
          'priority': 'medium',
          'due': '',
          'started': true,
          'startedAt': DateTime.now().subtract(const Duration(seconds: 125)).toIso8601String(),
          'why': 'is high leverage',
        },
        {
          'id': 'T3',
          'title': 'Refactor hub card',
          'priority': 'low',
          'why': 'clean architecture',
        },
        {
          'id': 'T4',
          'title': 'Extra item 4',
          'priority': 'low',
        },
        {
          'id': 'T5',
          'title': 'Extra item 5',
          'priority': 'low',
        },
      ],
    },
    {
      'id': 'leadership',
      'name': 'Leadership',
      'axis': 'leadership',
      'startClock': '14:00',
      'endClock': '17:00',
      'placeable': true,
      'slots': 3,
      'tasks': [
        {
          'id': 'T6',
          'title': 'Review partner proposals',
          'priority': 'high',
        },
      ],
    },
  ];

  group('BI26092628: BlockCard rendering and navigation', () {
    testWidgets('renders NOW block, caps items at 3, shows +2 more, and toggles to NEXT', (tester) async {
      final services = (await tester.runAsync(() => buildTestServices()))!;
      var viewedTasks = false;

      await tester.pumpWidget(MaterialApp(
        home: AppScope(
          services: services,
          child: Scaffold(
            body: SingleChildScrollView(
              child: BlockCard(
                blocks: fixtureBlocks,
                currentId: 'innovator',
                onViewTasks: () => viewedTasks = true,
              ),
            ),
          ),
        ),
      ));
      await tester.pump();

      // Check Header
      expect(find.text('NOW · Innovator'), findsOneWidget);
      expect(find.text('08:00 - 12:00'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);

      // Check at most 3 items displayed
      expect(find.text('Build day block actions'), findsOneWidget);
      expect(find.text('Test offline queueing'), findsOneWidget);
      expect(find.text('Refactor hub card'), findsOneWidget);
      expect(find.text('Extra item 4'), findsNothing);
      expect(find.text('Extra item 5'), findsNothing);

      // +2 more button
      expect(find.text('+2 more'), findsOneWidget);
      await tester.tap(find.text('+2 more'));
      expect(viewedTasks, isTrue);

      // Pin icon on pinned item
      expect(find.byIcon(Icons.push_pin_rounded), findsOneWidget);

      // Started item shows monospace mm:ss (e.g. 02:05)
      expect(find.textContaining(':'), findsWidgets);

      // Tap Next button to switch to NEXT block
      await tester.tap(find.text('Next'));
      await tester.pump();

      expect(find.text('NEXT · Leadership'), findsOneWidget);
      expect(find.text('14:00 - 17:00'), findsOneWidget);
      expect(find.text('Now'), findsOneWidget);
      expect(find.text('Review partner proposals'), findsOneWidget);

      // Tap Now to switch back
      await tester.tap(find.text('Now'));
      await tester.pump();
      expect(find.text('NOW · Innovator'), findsOneWidget);
    });
  });

  group('BI26092628: BlockCard swipe and long-press actions', () {
    testWidgets('swipe right on an item calls dayDone and dismisses it', (tester) async {
      final services = (await tester.runAsync(() => buildTestServices()))!;
      final api = services.session.api as TestApiClient;

      await tester.pumpWidget(MaterialApp(
        home: AppScope(
          services: services,
          child: Scaffold(
            body: SingleChildScrollView(
              child: BlockCard(
                blocks: fixtureBlocks,
                currentId: 'innovator',
              ),
            ),
          ),
        ),
      ));
      await tester.pump();

      final firstTask = find.text('Build day block actions');
      expect(firstTask, findsOneWidget);

      // Swipe right for Done
      await tester.drag(firstTask, const Offset(500, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Build day block actions'), findsNothing);
      expect(api.recordedCalls.any((c) => c['path'] == '/api/day/done' && c['body']['taskId'] == 'T1'), isTrue);
    });

    testWidgets('swipe left on an item calls dayMove', (tester) async {
      final services = (await tester.runAsync(() => buildTestServices()))!;
      final api = services.session.api as TestApiClient;

      await tester.pumpWidget(MaterialApp(
        home: AppScope(
          services: services,
          child: Scaffold(
            body: SingleChildScrollView(
              child: BlockCard(
                blocks: fixtureBlocks,
                currentId: 'innovator',
              ),
            ),
          ),
        ),
      ));
      await tester.pump();

      final firstTask = find.text('Build day block actions');
      expect(firstTask, findsOneWidget);

      // Swipe left for Move to next
      await tester.drag(firstTask, const Offset(-500, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(api.recordedCalls.any((c) => c['path'] == '/api/day/move' && c['body']['taskId'] == 'T1'), isTrue);
    });

    testWidgets('long press opens sheet with 5 actions and tapping Pin here calls dayPin', (tester) async {
      final services = (await tester.runAsync(() => buildTestServices()))!;
      final api = services.session.api as TestApiClient;

      await tester.pumpWidget(MaterialApp(
        home: AppScope(
          services: services,
          child: Scaffold(
            body: SingleChildScrollView(
              child: BlockCard(
                blocks: fixtureBlocks,
                currentId: 'innovator',
              ),
            ),
          ),
        ),
      ));
      await tester.pump();

      // Long press on second task (Test offline queueing)
      await tester.longPress(find.text('Test offline queueing'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Verify sheet shows task title and why
      expect(find.text('Test offline queueing'), findsWidgets);
      expect(find.text('Placed here because it is high leverage'), findsOneWidget);

      // Verify the 5 actions exist in the sheet
      expect(find.text('Pin here'), findsOneWidget);
      expect(find.text('Move to next'), findsOneWidget);
      expect(find.text('Not today'), findsOneWidget);
      expect(find.text('Stop'), findsOneWidget); // already started, so toggle is Stop
      expect(find.text('Done'), findsOneWidget);

      // Tap Pin here
      await tester.tap(find.text('Pin here'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(api.recordedCalls.any((c) => c['path'] == '/api/day/pin' && c['body']['taskId'] == 'T2'), isTrue);
    });
  });

  group('BI26092628: Offline queueing and FIFO order replay', () {
    test('offline actions queue in outbox and replay in order', () async {
      final services = await buildTestServices(online: false);
      final api = services.session.api as TestApiClient;

      // When offline, trigger three day actions
      await services.mutations.dayPin('T10', blockId: 'innovator');
      await services.mutations.dayMove('T20', blockId: 'innovator');
      await services.mutations.dayDone('T30', blockId: 'innovator');

      // Check that 3 writes are pending in outbox
      expect(await services.db.pendingCount(), 3);
      expect(api.recordedCalls.isEmpty, isTrue);

      // Inspect outbox rows to verify paths and FIFO sequence
      final pending = await services.db.pendingOutbox();
      expect(pending.length, 3);
      expect(pending[0]['path'], '/api/day/pin');
      expect((jsonDecode(pending[0]['body'] as String) as Map)['taskId'], 'T10');
      expect(pending[1]['path'], '/api/day/move');
      expect((jsonDecode(pending[1]['body'] as String) as Map)['taskId'], 'T20');
      expect(pending[2]['path'], '/api/day/done');
      expect((jsonDecode(pending[2]['body'] as String) as Map)['taskId'], 'T30');

      // Now drain the outbox
      final delivered = await services.outbox.drain();
      expect(delivered, 3);
      expect(await services.db.pendingCount(), 0);

      // Verify delivered in FIFO order
      expect(api.recordedCalls.length, 3);
      expect(api.recordedCalls[0]['path'], '/api/day/pin');
      expect(api.recordedCalls[0]['body']['taskId'], 'T10');
      expect(api.recordedCalls[1]['path'], '/api/day/move');
      expect(api.recordedCalls[1]['body']['taskId'], 'T20');
      expect(api.recordedCalls[2]['path'], '/api/day/done');
      expect(api.recordedCalls[2]['body']['taskId'], 'T30');
    });
  });

  group('BI26092628: Task detail kind and estimate edits', () {
    testWidgets('TaskDetailScreen renders kind segmented control and estimate stepper and updates via mutations', (tester) async {
      final services = (await tester.runAsync(() => buildTestServices()))!;
      final api = services.session.api as TestApiClient;

      services.store.detail('task', 'T101', '/api/tasks/detail?taskId=T101').value = {
        'task': {
          'ID': 'T101',
          'TITLE': 'Refactor day blocks',
          'STATUS': 'today',
          'PRIORITY': 'high',
          'KIND': 'innovator',
          'ESTIMATE': 3,
        },
        'effort': {'range': '1-2h', 'sitting': 'yes'},
        'tools': [],
        'brief': {},
        'draft': {},
      };

      await tester.pumpWidget(MaterialApp(
        home: AppScope(
          services: services,
          child: const TaskDetailScreen(taskId: 'T101'),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Check section and current values
      expect(find.text('BLOCK PLACEMENT'), findsOneWidget);
      expect(find.text('KIND'), findsOneWidget);
      expect(find.text('ESTIMATE'), findsOneWidget);
      expect(find.text('Innovator'), findsOneWidget);
      expect(find.text('3 half-hours (1.5h)'), findsOneWidget);

      // Change kind to Creative
      await tester.tap(find.text('Creative'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(api.recordedCalls.any((c) =>
          c['path'] == '/api/tasks/update' &&
          c['body']['taskId'] == 'T101' &&
          c['body']['kind'] == 'creative'), isTrue);

      // Increase estimate with + stepper
      await tester.tap(find.byTooltip('Increase estimate'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(api.recordedCalls.any((c) =>
          c['path'] == '/api/tasks/update' &&
          c['body']['taskId'] == 'T101' &&
          c['body']['estimate'] == 4), isTrue);

      await tester.pump(const Duration(seconds: 11));
    });
  });
}
