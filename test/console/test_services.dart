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
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Services for widget tests that need the real composition root over an in-memory
/// sqlite. Call [initSqfliteForTests] once in setUpAll.
void initSqfliteForTests() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}

class TestApiClient extends ApiClient {
  TestApiClient() : super(baseUrl: 'http://test', token: 'test');
  bool failSignals = false;
  Map<String, dynamic>? signalsResponse;

  /// Every write the app made through this client, for tests to assert on.
  final posts = <({String path, Map<String, dynamic> body})>[];

  @override
  Future<dynamic> postJson(String path, Map<String, dynamic> body, {bool cold = false}) async {
    posts.add((path: path, body: body));
    return {'ok': true};
  }

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

class TestSessionService extends SessionService {
  TestSessionService(this._api);
  final TestApiClient _api;
  @override
  ApiClient get api => _api;
}

class TestSyncEngine extends SyncEngine {
  TestSyncEngine(super.store, super.outbox, super.apiOf);
  @override
  void start() {}
}


Future<AppServices> buildTestServices({bool online = true}) async {
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
            block_index INTEGER,
            movement TEXT,
            blocks_total INTEGER,
            words_left INTEGER,
            title TEXT,
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
        await db.execute('''
          CREATE TABLE study_sessions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            module TEXT NOT NULL,
            started_at INTEGER NOT NULL,
            ended_at INTEGER NOT NULL,
            fraction_read REAL NOT NULL,
            finished INTEGER NOT NULL,
            hour INTEGER NOT NULL,
            block_name TEXT,
            energy INTEGER,
            not_now_reason TEXT,
            synced INTEGER NOT NULL DEFAULT 0
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
  final sync = TestSyncEngine(store, outbox, apiOf);
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

