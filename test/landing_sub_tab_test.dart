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
import 'package:isconl/theme.dart';
import 'package:isconl/ui/shell.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class LandingTestApiClient extends ApiClient {
  LandingTestApiClient() : super(baseUrl: 'http://test', token: 'test');

  @override
  Future<dynamic> getJson(String path, {bool cold = false}) async {
    if (path.contains('/api/state')) {
      return {
        'tasks': [
          {'ID': '1', 'TITLE': 'Task 1', 'STATUS': 'today'},
          {'ID': '2', 'TITLE': 'Task 2', 'STATUS': 'today'},
          {'ID': '3', 'TITLE': 'Task 3', 'STATUS': 'done'},
        ],
        'feed': [
          {'ID': 'm1', 'STATUS': 'new', 'TITLE': 'Msg 1', 'RECEIVED': '2026-09-27T08:00:00Z'},
          {'ID': 'm2', 'STATUS': 'new', 'TITLE': 'Msg 2', 'RECEIVED': '2026-09-27T08:05:00Z'},
          {'ID': 'm3', 'STATUS': 'new', 'TITLE': 'Msg 3', 'RECEIVED': '2026-09-27T08:10:00Z'},
          {'ID': 'm4', 'STATUS': 'read', 'TITLE': 'Msg 4', 'RECEIVED': '2026-09-27T08:15:00Z'},
        ],
      };
    }
    if (path.contains('/api/portfolio')) {
      return {
        'items': [
          {'title': 'Resume 2026', 'url': 'https://example.com/resume'},
          {'title': 'CV Tech Lead', 'url': 'https://example.com/cv'},
        ],
      };
    }
    if (path.contains('/api/hub') || path.contains('/api/blocks')) {
      return {
        'blocks': [
          {'id': 'b1', 'title': 'Deep Work'},
          {'id': 'b2', 'title': 'Review'},
          {'id': 'b3', 'title': 'Planning'},
        ],
      };
    }
    if (path.contains('/api/teams')) return {'teams': []};
    if (path.contains('/api/circle')) return {'people': []};
    if (path.contains('/api/jira')) return {'issues': []};
    if (path.contains('/api/buffer')) return {'profile': {}, 'updates': {}};
    return {};
  }

  @override
  Future<dynamic> postJson(String path, Map<String, dynamic> body, {bool cold = false}) async {
    return {'ok': true};
  }
}

class LandingTestSessionService extends SessionService {
  LandingTestSessionService(this._api);
  final LandingTestApiClient _api;
  @override
  ApiClient get api => _api;
}

class LandingTestSyncEngine extends SyncEngine {
  LandingTestSyncEngine(super.store, super.outbox, super.apiOf);

  @override
  void start() {
    // Avoid running periodic timer in fakeAsync
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<AppServices> buildTestServices() async {
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
    final api = LandingTestApiClient();
    final session = LandingTestSessionService(api);
    ApiClient apiOf() => session.api;
    final store = Store(db, apiOf);
    final outbox = OutboxService(db, apiOf);
    final sync = LandingTestSyncEngine(store, outbox, apiOf);
    sync.online = false;
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

  group('BI26092606: Landing sub-tab styling and counts', () {
    testWidgets('SubTabBar landing sub-tab renders uppercase text with no BoxDecoration fill or border', (tester) async {
      int selectedIndex = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SubTabBar(
            subs: const [
              SubTab('Hub', SizedBox()),
              SubTab('Tasks', SizedBox()),
              SubTab('Calendar', SizedBox()),
              SubTab('Planning', SizedBox()),
            ],
            index: selectedIndex,
            onSelect: (i) => selectedIndex = i,
            landingCount: 12,
          ),
        ),
      ));
      await tester.pump();

      // Landing sub-tab is HUB · 12
      final landingTextFinder = find.text('HUB · 12');
      expect(landingTextFinder, findsOneWidget);

      final landingText = tester.widget<Text>(landingTextFinder);
      expect(landingText.style?.color, C.text); // Selected state: full strength C.text
      expect(landingText.style?.letterSpacing, 1.2);
      expect(landingText.style?.fontWeight, FontWeight.w600);

      // Verify container has NO BoxDecoration (no fill, no border)
      final containerFinder = find.ancestor(
        of: landingTextFinder,
        matching: find.byType(Container),
      );
      final container = tester.widget<Container>(containerFinder.first);
      expect(container.decoration, isNull);

      // Sub-tab 1 (Tasks) retains button pill styling
      final tasksTextFinder = find.text('Tasks');
      expect(tasksTextFinder, findsOneWidget);
      final tasksBoxFinder = find.ancestor(
        of: tasksTextFinder,
        matching: find.byType(AnimatedContainer),
      );
      final tasksBox = tester.widget<AnimatedContainer>(tasksBoxFinder.first);
      final tasksDeco = tasksBox.decoration as BoxDecoration;
      expect(tasksDeco.color, Colors.transparent); // Unselected
      expect(tasksDeco.borderRadius, BorderRadius.circular(Sz.rSm));
    });

    testWidgets('SubTabBar landing sub-tab dims to C.text3 when unselected and tap selects it', (tester) async {
      int selectedIndex = 1;
      await tester.pumpWidget(MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return Scaffold(
              body: SubTabBar(
                subs: const [
                  SubTab('Hub', SizedBox()),
                  SubTab('Tasks', SizedBox()),
                  SubTab('Calendar', SizedBox()),
                ],
                index: selectedIndex,
                onSelect: (i) => setState(() => selectedIndex = i),
                landingCount: 5,
              ),
            );
          },
        ),
      ));
      await tester.pump();

      // When index 1 is selected:
      // Landing tab is unselected -> dimmed C.text3
      final landingTextFinder = find.text('HUB · 5');
      expect(landingTextFinder, findsOneWidget);
      final unselectedLandingText = tester.widget<Text>(landingTextFinder);
      expect(unselectedLandingText.style?.color, C.text3);

      // Index 1 (Tasks) is active -> C.greenBg tint and C.greenBright text
      final tasksBox = tester.widget<AnimatedContainer>(
        find.ancestor(of: find.text('Tasks'), matching: find.byType(AnimatedContainer)).first,
      );
      expect((tasksBox.decoration as BoxDecoration).color, C.greenBg);

      // Tapping landing sub-tab switches selectedIndex to 0
      await tester.tap(landingTextFinder);
      await tester.pump();

      expect(selectedIndex, 0);
      final selectedLandingText = tester.widget<Text>(find.text('HUB · 5'));
      expect(selectedLandingText.style?.color, C.text);
    });

    testWidgets('SubTabBar renders label alone without · 0 when count is 0, null, or unavailable', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SubTabBar(
            subs: const [
              SubTab('Inbox', SizedBox()),
              SubTab('Teams', SizedBox()),
            ],
            index: 0,
            onSelect: (_) {},
            landingCount: 0,
          ),
        ),
      ));
      await tester.pump();

      expect(find.text('INBOX'), findsOneWidget);
      expect(find.text('INBOX · 0'), findsNothing);
    });

    testWidgets('SubTabBar count computation for all 5 tabs and Systems has no count', (tester) async {
      final services = (await tester.runAsync(() => buildTestServices()))!;

      // Tab 0: Command -> Hub (2 open tasks due today, ignoring done)
      services.store.state.value = {
        'tasks': [
          {'ID': '1', 'STATUS': 'today'},
          {'ID': '2', 'STATUS': 'today'},
          {'ID': '3', 'STATUS': 'done'},
          {'ID': '4', 'STATUS': 'backlog'},
        ],
        'feed': [
          {'STATUS': 'new'},
          {'STATUS': 'new'},
          {'STATUS': 'read'},
        ],
      };
      expect(SubTabBar.countFor(0, services), 2);

      // Tab 1: Channels -> Inbox (2 unread items with STATUS == 'new')
      expect(SubTabBar.countFor(1, services), 2);

      // Tab 2: Projects -> Practice (items in portfolio)
      services.store.portfolio.value = {
        'items': [
          {'title': 'CV 1'},
          {'title': 'CV 2'},
          {'title': 'CV 3'},
        ],
      };
      expect(SubTabBar.countFor(2, services), 3);

      // Tab 3: Personal -> Rhythm (blocks in day)
      services.store.day.value = {
        'blocks': [
          {'id': '1'},
          {'id': '2'},
          {'id': '3'},
          {'id': '4'},
        ],
      };
      expect(SubTabBar.countFor(3, services), 4);

      // Tab 4: Systems -> Settings (no count)
      expect(SubTabBar.countFor(4, services), isNull);

      await tester.pump(const Duration(seconds: 11));
    });

    testWidgets('Shell integrates landing sub-tabs across all bottom tabs', (tester) async {
      final services = (await tester.runAsync(() => buildTestServices()))!;
      services.store.state.value = {
        'tasks': [
          {'ID': '1', 'TITLE': 'Due Today 1', 'STATUS': 'today'},
          {'ID': '2', 'TITLE': 'Due Today 2', 'STATUS': 'today'},
        ],
        'feed': [
          {'ID': 'm1', 'STATUS': 'new', 'TITLE': 'Msg 1', 'RECEIVED': '2026-09-27T08:00:00Z'},
          {'ID': 'm2', 'STATUS': 'new', 'TITLE': 'Msg 2', 'RECEIVED': '2026-09-27T08:05:00Z'},
          {'ID': 'm3', 'STATUS': 'new', 'TITLE': 'Msg 3', 'RECEIVED': '2026-09-27T08:10:00Z'},
        ],
      };
      services.store.portfolio.value = {
        'items': [
          {'title': 'Resume', 'url': 'http://resume'},
        ],
      };
      services.store.day.value = {
        'blocks': [
          {'id': 'b1'},
          {'id': 'b2'},
        ],
      };

      await tester.pumpWidget(MaterialApp(
        home: AppScope(
          services: services,
          child: const Shell(initialTab: 0),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Command Tab (0): Hub landing has count 2
      expect(find.text('HUB · 2'), findsOneWidget);

      // Tap Channels in bottom nav
      await tester.tap(find.bySemanticsLabel('Channels'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Channels Tab (1): Inbox landing has count 3
      expect(find.text('INBOX · 3'), findsOneWidget);

      // Tap Projects in bottom nav
      await tester.tap(find.bySemanticsLabel('Projects'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Projects Tab (2): Practice landing has count 1
      expect(find.text('PRACTICE · 1'), findsOneWidget);

      // Tap Personal in bottom nav
      await tester.tap(find.bySemanticsLabel('Personal'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Personal Tab (3): Rhythm landing has count 2
      expect(find.text('RHYTHM · 2'), findsOneWidget);

      // Tap Systems in bottom nav
      await tester.tap(find.bySemanticsLabel('Systems'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Systems Tab (4): Settings has NO count
      expect(find.text('SETTINGS'), findsOneWidget);
      expect(find.text('SETTINGS · 0'), findsNothing);

      await tester.pump(const Duration(seconds: 11));
    });
  });
}
