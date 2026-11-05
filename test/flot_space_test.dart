// BI26103090: Ledger is Flot in the app.
// Every word a person sees that names the money product says Flot:
// the space name, tab/screen titles, buttons, empty states, settings and notifications.
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
import 'package:isconl/services/ledger_tools.dart';
import 'package:isconl/services/narration.dart';
import 'package:isconl/services/session.dart';
import 'package:isconl/services/sms_ingest.dart';
import 'package:isconl/services/updater.dart';
import 'package:isconl/theme.dart';
import 'package:isconl/ui/shell.dart';
import 'package:isconl/ui/views/ledger_tools.dart';
import 'package:isconl/ui/views/personal_dash_model.dart';
import 'package:isconl/ui/views/personal_dashboard.dart';
import 'package:isconl/ui/views/settings.dart';
import 'package:isconl/ui/widgets/sidebar_rail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeApiClient extends ApiClient {
  _FakeApiClient() : super(baseUrl: 'http://test', token: 'test');
  @override
  Future<dynamic> getJson(String path, {bool cold = false, bool stored = true}) async => {};
  @override
  Future<dynamic> postJson(String path, Map<String, dynamic> body, {bool cold = false}) async => {'ok': true};
}

class _FakeSessionService extends SessionService {
  _FakeSessionService(this._api);
  final ApiClient _api;
  @override
  ApiClient get api => _api;
}

class _TestSyncEngine extends SyncEngine {
  _TestSyncEngine(super.store, super.outbox, super.apiOf);
  @override
  void start() {}
}

class _FakeLedger implements LedgerApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  Future<LedgerSummary> summary() async => const LedgerSummary();
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
    final api = _FakeApiClient();
    final session = _FakeSessionService(api);
    ApiClient apiOf() => session.api;
    final store = Store(db, apiOf);
    final outbox = OutboxService(db, apiOf);
    final sync = _TestSyncEngine(store, outbox, apiOf);
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

  group('BI26103090: Ledger is Flot in the app', () {
    test('routes: finance, flot, and ledger routes all resolve to Flot', () {
      expect(viewForNavRoute('finance')?.$2, 'Flot');
      expect(viewForNavRoute('flot')?.$2, 'Flot');
      expect(viewForNavRoute('ledger')?.$2, 'Flot');
      expect(viewForNavRoute('holdings')?.$2, 'Flot');
      expect(viewForNavRoute('flot-tools')?.$2, 'Flot tools');
      expect(viewForNavRoute('ledger-tools')?.$2, 'Flot tools');
    });

    test('sidebar rail personal group includes Flot and not Ledger', () {
      final personalGroup = navGroups.firstWhere((g) => g.label == 'Personal');
      final labels = personalGroup.items.map((item) => item.label).toList();

      expect(labels, contains('Flot'));
      expect(labels, isNot(contains('Ledger')));
    });

    testWidgets('PersonalDashboard tile displays FLOT label', (t) async {
      t.view.physicalSize = const Size(1080, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);

      await t.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: PersonalDashboard(
            blocks: BlocksProgress(3, 12, 'Innovator'),
            habits: const [],
            netWorth: 125000,
            currency: 'KES',
            unlock: () async => true,
          ),
        ),
      ));
      await t.pump();
      await t.pump(const Duration(milliseconds: 200));

      expect(find.text('FLOT'), findsOneWidget);
      expect(find.text('LEDGER'), findsNothing);
    });

    testWidgets('LedgerToolsScreen locked state displays Flot is private', (t) async {
      await t.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: LedgerToolsScreen(
            api: _FakeLedger(),
            unlock: () async => false,
          ),
        ),
      ));
      await t.pump();
      await t.pump(const Duration(milliseconds: 200));

      expect(find.text('Flot is private'), findsOneWidget);
      expect(find.text('The ledger is private'), findsNothing);
    });

    testWidgets('SettingsView SMS ingest copy refers to Flot entry', (t) async {
      t.view.physicalSize = const Size(1080, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);

      final services = (await t.runAsync(() => buildTestServices()))!;

      await t.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: AppScope(
          services: services,
          child: const Scaffold(body: SmsCard()),
        ),
      ));
      await t.pump();
      await t.pump(const Duration(milliseconds: 200));

      expect(find.textContaining('becomes a Flot entry automatically'), findsOneWidget);
      expect(find.textContaining('becomes a ledger entry automatically'), findsNothing);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    });
  });
}
