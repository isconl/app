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

/// An API client whose answers a test scripts per path prefix. A value that is an [ApiException] is thrown.
class ScriptedApi extends ApiClient {
  ScriptedApi(this.answers) : super(baseUrl: 'http://test', token: 'test');
  final Map<String, Object> answers;
  final List<String> asked = [];

  @override
  Future<dynamic> getJson(String path, {bool cold = false}) async {
    asked.add(path);
    for (final e in answers.entries) {
      if (path.startsWith(e.key)) {
        final v = e.value;
        if (v is ApiException) throw v;
        return v;
      }
    }
    return {};
  }
}

class _Session extends SessionService {
  _Session(this._api);
  final ApiClient _api;
  @override
  ApiClient get api => _api;
}

class _Sync extends SyncEngine {
  _Sync(super.store, super.outbox, super.apiOf);
  @override
  void start() {}
}

/// Full in-memory app services around [api], for widget tests. Call inside `tester.runAsync`.
Future<AppServices> buildTestServices(ApiClient api, {bool online = true}) async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final rawDb = await databaseFactory.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      singleInstance: false,
      version: 5,
      onCreate: (db, _) async {
        await db.execute('CREATE TABLE snapshots (key TEXT PRIMARY KEY, json TEXT NOT NULL, fetched_at INTEGER NOT NULL)');
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
        await db.execute('CREATE TABLE chat (id INTEGER PRIMARY KEY AUTOINCREMENT, role TEXT NOT NULL, text TEXT NOT NULL, meta TEXT, ts INTEGER NOT NULL)');
        await db.execute(
            'CREATE TABLE lesson_resume (course TEXT NOT NULL, file TEXT NOT NULL, scroll_pct INTEGER NOT NULL, fraction REAL, updated_at INTEGER NOT NULL, PRIMARY KEY (course, file))');
        await db.execute(
            'CREATE TABLE lesson_notes (course TEXT NOT NULL, file TEXT NOT NULL, text TEXT NOT NULL, anchor INTEGER, updated_at INTEGER NOT NULL, PRIMARY KEY (course, file))');
        await db.execute(
            'CREATE TABLE lesson_progress (course TEXT NOT NULL, file TEXT NOT NULL, status TEXT NOT NULL, updated_at INTEGER NOT NULL, PRIMARY KEY (course, file))');
        await ensureVaultMirrorTables(db);
      },
    ),
  );
  final db = AppDb.forTesting(rawDb);
  final session = _Session(api);
  ApiClient apiOf() => session.api;
  final store = Store(db, apiOf);
  final outbox = OutboxService(db, apiOf);
  final sync = _Sync(store, outbox, apiOf);
  sync.online = online;
  final mutations = Mutations(store, outbox, sync, apiOf, db);
  return AppServices.forTesting(
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
  );
}
