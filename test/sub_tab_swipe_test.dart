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

class ShellTestApiClient extends ApiClient {
  ShellTestApiClient() : super(baseUrl: 'http://test', token: 'test');

  @override
  Future<dynamic> getJson(String path, {bool cold = false}) async {
    if (path.contains('/api/teams')) {
      return {'teams': []};
    }
    if (path.contains('/api/state')) {
      return {'feed': [], 'tasks': []};
    }
    if (path.contains('/api/circle')) {
      return {'people': []};
    }
    if (path.contains('/api/jira')) {
      return {'issues': []};
    }
    if (path.contains('/api/buffer')) {
      return {'profile': {}, 'updates': {}};
    }
    if (path.contains('/api/portfolio')) {
      return {'sections': []};
    }
    if (path.contains('/api/hub') || path.contains('/api/blocks')) {
      return {'blocks': []};
    }
    return {};
  }

  @override
  Future<dynamic> postJson(String path, Map<String, dynamic> body, {bool cold = false}) async {
    return {'ok': true};
  }
}

class ShellTestSessionService extends SessionService {
  ShellTestSessionService(this._api);
  final ShellTestApiClient _api;
  @override
  ApiClient get api => _api;
}

class TestSyncEngine extends SyncEngine {
  TestSyncEngine(super.store, super.outbox, super.apiOf);

  @override
  void start() {
    // Avoid running 90-second periodic timer in fakeAsync during widget tests
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
    final api = ShellTestApiClient();
    final session = ShellTestSessionService(api);
    ApiClient apiOf() => session.api;
    final store = Store(db, apiOf);
    final outbox = OutboxService(db, apiOf);
    final sync = TestSyncEngine(store, outbox, apiOf);
    sync.online = false; // offline in test
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

  group('BI26092605: Sub-tab swipe and navigation in Shell', () {
    testWidgets('swiping on Channels moves Inbox -> Deck -> Teams -> Tools and stays on Channels', (tester) async {
      final services = (await tester.runAsync(() => buildTestServices()))!;

      // Pre-seed stores so views render immediately
      services.store.state.value = {'feed': [], 'tasks': []};
      services.store.circle.value = {'people': []};
      services.store.jira.value = {'issues': []};

      await tester.pumpWidget(MaterialApp(
        home: AppScope(
          services: services,
          child: const Shell(initialTab: 1), // Channels
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Bottom bar tab is Channels, title is Channels
      expect(find.widgetWithText(ShellAppBar, 'Channels'), findsOneWidget);

      // Landing sub-tab is Inbox (index 0, uppercase section title; BI26092606)
      expect(find.text('INBOX'), findsOneWidget);
      expect(find.text('Deck'), findsOneWidget);
      expect(find.text('Teams'), findsOneWidget);
      expect(find.text('Tools'), findsOneWidget);

      final pageViewFinder = find.byKey(const ValueKey('tab_sub_pageview_1'));
      expect(pageViewFinder, findsOneWidget);

      Future<void> swipe(double dx) async {
        await tester.drag(pageViewFinder, Offset(dx, 0));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }

      Color? tileColor(String label) {
        final box = tester.widget<AnimatedContainer>(
          find.ancestor(of: find.text(label), matching: find.byType(AnimatedContainer)).first,
        );
        return (box.decoration as BoxDecoration).color;
      }

      // Left 1: Inbox -> Deck, still on Channels
      await swipe(-500);
      expect(find.widgetWithText(ShellAppBar, 'Channels'), findsOneWidget);
      expect(tileColor('Deck'), C.greenBg);

      // Left 2: Deck -> Teams
      await swipe(-500);
      expect(find.widgetWithText(ShellAppBar, 'Channels'), findsOneWidget);
      expect(tileColor('Teams'), C.greenBg);

      // Left 3: Teams -> Tools
      await swipe(-500);
      expect(find.widgetWithText(ShellAppBar, 'Channels'), findsOneWidget);
      expect(tileColor('Tools'), C.greenBg);

      // Left 4: past Tools (the last sub-tab) bounces and never jumps bottom tab
      await swipe(-500);
      expect(find.widgetWithText(ShellAppBar, 'Channels'), findsOneWidget);
      expect(tileColor('Tools'), C.greenBg);

      // Back right: Tools -> Teams
      await swipe(500);
      expect(find.widgetWithText(ShellAppBar, 'Channels'), findsOneWidget);
      expect(tileColor('Teams'), C.greenBg);

      await tester.pump(const Duration(seconds: 11));
    });

    testWidgets('tapping a sub-tab in strip animates to it and commits _sub', (tester) async {
      final services = (await tester.runAsync(() => buildTestServices()))!;
      services.store.state.value = {'feed': [], 'tasks': []};
      services.store.circle.value = {'people': []};
      services.store.jira.value = {'issues': []};

      await tester.pumpWidget(MaterialApp(
        home: AppScope(
          services: services,
          child: const Shell(initialTab: 1),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Tap Teams
      await tester.tap(find.text('Teams'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.widgetWithText(ShellAppBar, 'Channels'), findsOneWidget);
      final kanbanTileFinder = find.ancestor(
        of: find.text('Teams'),
        matching: find.byType(AnimatedContainer),
      );
      final kanbanBox = tester.widget<AnimatedContainer>(kanbanTileFinder.first);
      expect((kanbanBox.decoration as BoxDecoration).color, C.greenBg);

      await tester.pump(const Duration(seconds: 11));
    });

    testWidgets('tapping bottom nav switches tab instantly and lands on sub 0', (tester) async {
      final services = (await tester.runAsync(() => buildTestServices()))!;
      services.store.state.value = {'feed': [], 'tasks': []};
      services.store.circle.value = {'people': []};
      services.store.jira.value = {'issues': []};

      await tester.pumpWidget(MaterialApp(
        home: AppScope(
          services: services,
          child: const Shell(initialTab: 1), // Channels
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Navigate to Teams (sub 2)
      await tester.tap(find.text('Teams'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Now tap Projects in bottom nav bar by semantics label
      await tester.tap(find.bySemanticsLabel('Projects'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Title is Projects
      expect(find.widgetWithText(ShellAppBar, 'Projects'), findsOneWidget);

      // Sub-tab is Practice (index 0 of Projects, formerly Portfolio; BI26092606)
      // The view's own section label also reads PRACTICE, so look in the sub-tab strip only.
      final practiceTab = find.descendant(of: find.byType(SubTabBar), matching: find.text('PRACTICE'));
      expect(practiceTab, findsOneWidget);
      final practiceContainer = tester.widget<Container>(
        find.ancestor(of: practiceTab, matching: find.byType(Container)).first,
      );
      expect(practiceContainer.decoration, isNull);

      // Now tap Channels again in bottom nav by semantics label
      await tester.tap(find.bySemanticsLabel('Channels'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Title is Channels and lands on Inbox (sub 0), NOT Teams!
      expect(find.widgetWithText(ShellAppBar, 'Channels'), findsOneWidget);
      expect(find.text('INBOX'), findsOneWidget);
      final inboxContainer = tester.widget<Container>(
        find.ancestor(of: find.text('INBOX'), matching: find.byType(Container)).first,
      );
      expect(inboxContainer.decoration, isNull);

      await tester.pump(const Duration(seconds: 11));
    });

    testWidgets('back navigation returns from sub > 0 to sub 0, then to tab 0', (tester) async {
      final services = (await tester.runAsync(() => buildTestServices()))!;
      services.store.state.value = {'feed': [], 'tasks': []};
      services.store.circle.value = {'people': []};
      services.store.jira.value = {'issues': []};

      await tester.pumpWidget(MaterialApp(
        home: AppScope(
          services: services,
          child: const Shell(initialTab: 1), // Channels
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Tap Teams (sub 2)
      await tester.tap(find.text('Teams'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Pop route (Android back button)
      final dynamic widgetsAppState = tester.state(find.byType(WidgetsApp));
      await widgetsAppState.didPopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Returned to Inbox (sub 0), still on Channels (BI26092606)
      expect(find.widgetWithText(ShellAppBar, 'Channels'), findsOneWidget);
      expect(find.text('INBOX'), findsOneWidget);

      // Pop route again: should return to Command (tab 0)
      await widgetsAppState.didPopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.widgetWithText(ShellAppBar, 'Command'), findsOneWidget);

      await tester.pump(const Duration(seconds: 11));
    });
  });
}
