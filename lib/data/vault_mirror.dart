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

/// Wires the mirrored tables into what `Snapshot.value` actually holds --
/// this is the "UI reads the mirrored tables" step: `Store`'s ~26 getters
/// and every view that reads `store.X.value['someField']` do NOT change,
/// because this function returns the exact same JSON shape the blob cache
/// always had -- same field names, same nesting -- just with each row's
/// vault-schema columns refreshed from the live table.
///
/// PER-ROW MERGE, not a blind array swap -- found live while wiring the
/// first views to this: every hub endpoint enriches or renames fields on
/// top of vault's raw schema (`/api/circle`'s `lastTouch`/`dueIn`/`recent`,
/// `/api/plans`' nested `tasks`, inbox's `RECEIVED` vs. vault's own
/// `RECEIVED_AT`). A blind replace with the mirror's schema-only rows would
/// have silently dropped every one of those and broken the screens that
/// render them -- circle's touch-recency sort/badges, planning's per-plan
/// subtask list, inbox's timestamp. Merging `{...baseRow, ...mirrorRow}`
/// by ID is safe unconditionally: a hub-added/renamed field survives
/// because its key never collides with a vault schema column name; a
/// vault schema field gets refreshed with the mirror's (possibly more
/// complete/fresher) value on top.
///
/// The mirror is preferred over the blob for a mirrored field WHENEVER the
/// table has rows -- not just as an offline fallback. This is a genuine
/// upgrade, not a passthrough: `upsertVaultRows` never deletes, so the
/// table accumulates every row this app has ever seen for that collection
/// across multiple fetches, while the blob only ever holds the single most
/// recent response verbatim. A row present in the mirror but not in the
/// current base response (the base fetch was filtered/paginated, or simply
/// hasn't run yet) still appears -- with its vault-schema fields only,
/// since there's no base row to merge hub-added fields from. That's a net
/// improvement over today (the row was invisible before), not a
/// regression, even though it renders with fewer decorations than a row
/// the base response also covered.
///
/// A base row NOT found in the mirror (the mirror source for this table
/// hasn't caught up yet) is kept as-is, appended after the merged ones --
/// never silently dropped.
///
/// A mirrored field with zero rows in its table is left exactly as `base`
/// already had it -- an empty table is indistinguishable from "never
/// fetched yet" and must not stomp real cached data with emptiness.
/// Non-mirrored fields (`/api/state`'s `time`, `services`, etc.) always
/// come from `base` untouched -- this function only ever touches the
/// specific `jsonKey`s `kMirrorSources` declares for `snapshotKey`.
Future<dynamic> overlayVaultMirrorTables(Database db, String snapshotKey, dynamic base) async {
  final sources = kMirrorSources.where((s) => s.$1 == snapshotKey);
  if (sources.isEmpty) return base; // no-op for the majority of snapshot keys today

  final merged = (base is Map) ? Map<String, dynamic>.from(base) : <String, dynamic>{};
  for (final (_, table, jsonKey) in sources) {
    final mirrorRows = await readVaultRows(db, table);
    if (mirrorRows.isEmpty) continue;

    final baseList = merged[jsonKey];
    final baseById = <String, Map<String, dynamic>>{};
    if (baseList is List) {
      for (final item in baseList) {
        if (item is Map && item['ID'] != null) {
          baseById[item['ID'].toString()] = Map<String, dynamic>.from(item);
        }
      }
    }

    final combined = <Map<String, dynamic>>[];
    final seenIds = <String>{};
    for (final row in mirrorRows) {
      final id = row['ID'] ?? '-';
      final baseRow = baseById[id];
      combined.add(baseRow != null ? {...baseRow, ...row} : Map<String, dynamic>.from(row));
      seenIds.add(id);
    }
    if (baseList is List) {
      for (final item in baseList) {
        if (item is Map) {
          final id = item['ID']?.toString() ?? '-';
          if (!seenIds.contains(id)) combined.add(Map<String, dynamic>.from(item));
        }
      }
    }
    merged[jsonKey] = combined;
  }
  return merged;
}
