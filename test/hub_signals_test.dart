import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/api/client.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/ui/widgets/debrief_card.dart';
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
import 'package:isconl/ui/views/hub.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _TestApiClient extends ApiClient {
  _TestApiClient() : super(baseUrl: 'http://test', token: 'test');
  bool failSignals = false;
  Map<String, dynamic>? signalsResponse;

  @override
  Future<dynamic> getJson(String path, {bool cold = false}) async {
    if (path.startsWith('/api/signals')) {
      if (failSignals) {
        throw ApiException(404, 'Signals not found');
      }
      return signalsResponse ?? {};
    }
    return {};
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

  Future<AppServices> buildTestServices({bool online = true}) async {
    DebriefCard.hourNow = () => 9; // the debrief card appears from 18:00 and would build a real recorder
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
            CREATE TABLE chat (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              role TEXT NOT NULL,
              text TEXT NOT NULL,
              meta TEXT,
              ts INTEGER NOT NULL
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

  // Due dates are relative to today, so "1 overdue" holds on any day the suite runs.
  String isoDay(int offset) {
    final d = DateTime.now().add(Duration(days: offset));
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> sampleState() => {
        'time': {
          'eqShort': '2026-5',
          'sprintShort': 'W39',
          'yearPct': 74,
        },
        'tasks': [
          {'ID': 'T1', 'STATUS': 'today', 'TITLE': 'Task 1', 'DUE_DATE': isoDay(2)},
          {'ID': 'T2', 'STATUS': 'review', 'TITLE': 'Task 2', 'DUE_DATE': isoDay(2)},
          {'ID': 'T3', 'STATUS': 'backlog', 'TITLE': 'Task 3', 'DUE_DATE': isoDay(-5)},
        ],
        'feed': [],
        'services': {},
      };

  group('BI26092621: Mobile Hub hero date formatting', () {
    testWidgets('the weekday span is bold and the rest is normal weight', (tester) async {
      final services = (await tester.runAsync(() => buildTestServices()))!;
      services.store.state.value = sampleState();

      await tester.pumpWidget(
        AppScope(
          services: services,
          child: const MaterialApp(
            home: Scaffold(body: HubView()),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump();

      // Find the Text widget in the hero card containing the date
      final dateFinder = find.byWidgetPredicate((widget) {
        if (widget is Text && widget.textSpan is TextSpan) {
          final span = widget.textSpan! as TextSpan;
          if (span.children != null && span.children!.length == 2) {
            final first = span.children![0] as TextSpan;
            final second = span.children![1] as TextSpan;
            return first.style?.fontWeight == FontWeight.w700 &&
                second.style?.fontWeight == FontWeight.w400 &&
                (second.text?.startsWith(' · ') ?? false);
          }
        }
        return false;
      });

      expect(dateFinder, findsOneWidget);

      // BI26101801: `Sunday · October 18, 2026`, the month in full with a comma after the day.
      final now = DateTime.now();
      const wd = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
      const mo = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
      expect(find.text('${wd[now.weekday - 1]} · ${mo[now.month - 1]} ${now.day}, ${now.year}', findRichText: true),
          findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
      await tester.pump(const Duration(seconds: 2));
    });
  });

  group('BI26092621: Three-signal strip with fixture, colours, and navigation', () {
    testWidgets('with fixture, three labels show in fixture order with tone colours and no Needs you prefix', (tester) async {
      final services = (await tester.runAsync(() => buildTestServices()))!;
      services.store.state.value = sampleState();

      final fixtureStr = File('test/fixtures/signals.json').readAsStringSync();
      final fixture = jsonDecode(fixtureStr) as Map<String, dynamic>;

      services.store.signals.value = fixture;

      await tester.pumpWidget(
        AppScope(
          services: services,
          child: const MaterialApp(
            home: Scaffold(body: HubView()),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump();

      // 1. Labels rendered in fixture order
      final rentDue = find.text('Rent due');
      final standup = find.text('Standup 10:30');
      final joelWaiting = find.text('Joel waiting');

      expect(rentDue, findsOneWidget);
      expect(standup, findsOneWidget);
      expect(joelWaiting, findsOneWidget);

      // Verify tone colours and font weights
      final rentDueText = tester.widget<Text>(rentDue);
      expect(rentDueText.style?.color, C.red);
      expect(rentDueText.style?.fontWeight, FontWeight.w600);

      final standupText = tester.widget<Text>(standup);
      expect(standupText.style?.color, C.amber);
      expect(standupText.style?.fontWeight, FontWeight.w600);

      final joelWaitingText = tester.widget<Text>(joelWaiting);
      expect(joelWaitingText.style?.color, C.blue);
      expect(joelWaitingText.style?.fontWeight, FontWeight.w600);

      // 2. Separators rendered
      expect(find.text('  ·  '), findsNWidgets(2));

      // 3. No "Needs you:" prefix
      expect(find.textContaining('Needs you:'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('a 404 renders the old _needsYou fallback', (tester) async {
      final services = (await tester.runAsync(() => buildTestServices()))!;
      services.store.state.value = sampleState();

      final api = services.session.api as _TestApiClient;
      api.failSignals = true;
      services.store.signals.value = null;

      await tester.pumpWidget(
        AppScope(
          services: services,
          child: const MaterialApp(
            home: Scaffold(body: HubView()),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump();

      // Should render "Needs you:  " with counts
      expect(find.textContaining('Needs you:'), findsOneWidget);
      expect(find.textContaining('0 alerts'), findsOneWidget);
      // BI26100540: overdue is gone from the Command view; tasks live in slate.
      expect(find.textContaining('overdue'), findsNothing);
      expect(find.textContaining('1 in review'), findsOneWidget);

      // Signals should not be present
      expect(find.text('Rent due'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('tapping a signal label navigates to its route', (tester) async {
      final services = (await tester.runAsync(() => buildTestServices()))!;
      services.store.state.value = sampleState();

      final fixtureStr = File('test/fixtures/signals.json').readAsStringSync();
      final fixture = jsonDecode(fixtureStr) as Map<String, dynamic>;
      services.store.signals.value = fixture;

      await tester.pumpWidget(
        AppScope(
          services: services,
          child: const MaterialApp(
            home: Scaffold(body: HubView()),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump();

      // Tap "Rent due" (route: "finance") -> navigates to Ledger
      await tester.tap(find.text('Rent due'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SecondaryScreen), findsOneWidget);
      expect(find.text('Ledger'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('long press on a signal label shows its detail in a snackbar', (tester) async {
      final services = (await tester.runAsync(() => buildTestServices()))!;
      services.store.state.value = sampleState();

      final fixtureStr = File('test/fixtures/signals.json').readAsStringSync();
      final fixture = jsonDecode(fixtureStr) as Map<String, dynamic>;
      services.store.signals.value = fixture;

      await tester.pumpWidget(
        AppScope(
          services: services,
          child: const MaterialApp(
            home: Scaffold(body: HubView()),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump();

      // Long press on "Rent due"
      await tester.longPress(find.text('Rent due'));
      await tester.pump();

      expect(find.text('Rent due by midnight tonight'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('offline caching: cached snapshot is loaded and rendered offline', (tester) async {
      final services = (await tester.runAsync(() => buildTestServices(online: false)))!;
      services.store.state.value = sampleState();

      final fixtureStr = File('test/fixtures/signals.json').readAsStringSync();
      final fixture = jsonDecode(fixtureStr) as Map<String, dynamic>;

      await tester.runAsync(() => services.db.putSnapshot('signals', fixture));

      // Hydrate from SQLite
      await tester.runAsync(() => services.store.signals.hydrate());

      await tester.pumpWidget(
        AppScope(
          services: services,
          child: const MaterialApp(
            home: Scaffold(body: HubView()),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump();

      expect(find.text('Rent due'), findsOneWidget);
      expect(find.text('Standup 10:30'), findsOneWidget);
      expect(find.text('Joel waiting'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
      await tester.pump(const Duration(seconds: 2));
    });
  });
}
