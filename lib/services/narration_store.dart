import '../data/db.dart';
import 'narration.dart';

/// Keeps the voice choice and each module's reading position in the app's own
/// database, so both survive a restart and neither needs a signal.
class DbNarrationStore implements NarrationStore {
  DbNarrationStore(this._db);
  final AppDb _db;

  @override
  Future<Object?> read(String key) async => (await _db.getSnapshot(key))?.$1 as Object?;

  @override
  Future<void> write(String key, Object value) => _db.putSnapshot(key, value);

  /// Snapshots cannot be deleted, so removing one stores an empty map, which
  /// reads back as "no saved position".
  @override
  Future<void> remove(String key) => _db.putSnapshot(key, <String, Object>{});
}
