import '../api/client.dart';
import 'db.dart';

/// The API client's last-good-answer store, kept in the same SQLite snapshots
/// table as everything else, under `http:<path>`. Sign-out wipes it with the
/// rest (AppDb.deleteSnapshots), which is the only thing that should.
class DbResponseCache implements ResponseCache {
  DbResponseCache(this._db);
  final AppDb _db;

  static String keyOf(String path) => 'http:$path';

  @override
  Future<void> put(String path, dynamic value) => _db.putSnapshot(keyOf(path), value);

  @override
  Future<(dynamic, DateTime)?> get(String path) => _db.getSnapshot(keyOf(path));
}
