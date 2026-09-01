import 'package:sqflite/sqflite.dart';

import 'vault_schema.dart';

/// One row as vault itself would return it: every schema column present,
/// values as strings, missing/absent cells filled with vault's own '-'
/// placeholder -- same contract as `sqlite-store.js`'s `read()` on the
/// server. Extra fields a hub endpoint adds on top (derived/computed, e.g.
/// `/api/circle`'s `lastTouch`/`touchCount`) are deliberately dropped here,
/// not stored -- they're recomputed live on every real fetch, storing a
/// stale copy would be actively misleading.
typedef VaultRow = Map<String, String>;

/// `CREATE TABLE IF NOT EXISTS` for every table in `kVaultTables`, matching
/// vault's own sqlite-store.js pattern: one column per schema field (all
/// TEXT, no type inference -- callers already parse numbers/dates
/// themselves), `updated_at_ms` for freshness, `ID` as the natural key.
Future<void> ensureVaultMirrorTables(Database db) async {
  for (final entry in kVaultTables.entries) {
    final cols = entry.value.map((c) => '"$c" TEXT').join(', ');
    await db.execute(
      'CREATE TABLE IF NOT EXISTS "${entry.key}" ($cols, updated_at_ms INTEGER, PRIMARY KEY("ID"))',
    );
  }
}

/// Pulls `raw[jsonKey]` (a JSON array) out of one endpoint's decoded
/// response body and keeps only the columns `table` actually declares --
/// tolerant of extra derived fields, missing fields, and a response shape
/// that doesn't match (returns [] rather than throwing, since a hub
/// endpoint's shape is out of this app's control and a bad response must
/// never crash the mirror pass).
List<VaultRow> extractVaultRows(dynamic responseJson, String table, String jsonKey) {
  final columns = kVaultTables[table];
  if (columns == null) return const [];
  if (responseJson is! Map) return const [];
  final raw = responseJson[jsonKey];
  if (raw is! List) return const [];

  final out = <VaultRow>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final row = <String, String>{};
    for (final c in columns) {
      final v = item[c];
      row[c] = (v == null || v.toString().isEmpty) ? '-' : v.toString();
    }
    out.add(row);
  }
  return out;
}

/// Insert-or-replace every row by its `ID`, in one transaction. Matches
/// vault's own `append`/`rewrite` semantics loosely (upsert-by-ID, not a
/// full-table replace) -- a row missing from THIS particular response
/// (e.g. one filtered out server-side) is left alone, not deleted, since a
/// partial/filtered fetch is not evidence the row no longer exists.
Future<void> upsertVaultRows(Database db, String table, List<VaultRow> rows) async {
  if (rows.isEmpty) return;
  final now = DateTime.now().millisecondsSinceEpoch;
  await db.transaction((txn) async {
    final batch = txn.batch();
    for (final row in rows) {
      batch.insert(
        table,
        {...row, 'updated_at_ms': now},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  });
}

/// Every row currently in `table`, oldest-inserted-first (matching
/// `sqlite-store.js`'s `ORDER BY rowid` contract) -- schema columns only,
/// `updated_at_ms` not exposed to the caller.
Future<List<VaultRow>> readVaultRows(Database db, String table) async {
  final columns = kVaultTables[table];
  if (columns == null) return const [];
  final colList = columns.map((c) => '"$c"').join(', ');
  final rows = await db.rawQuery('SELECT $colList FROM "$table" ORDER BY rowid');
  return rows.map((r) => r.map((k, v) => MapEntry(k, v?.toString() ?? '-'))).toList();
}

/// The single entry point `Snapshot.refresh()` calls after a successful
/// fetch: for every `kMirrorSources` row keyed to this snapshot, extract
/// and upsert. A snapshot key with no mirror source (most of them, today)
/// is a silent no-op -- the blob cache remains the only copy, unchanged.
Future<void> mirrorSnapshotIntoVaultTables(Database db, String snapshotKey, dynamic responseJson) async {
  for (final (key, table, jsonKey) in kMirrorSources) {
    if (key != snapshotKey) continue;
    final rows = extractVaultRows(responseJson, table, jsonKey);
    await upsertVaultRows(db, table, rows);
  }
}
