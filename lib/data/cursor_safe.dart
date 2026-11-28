/// BI26111901: reads a single large cell without tripping Android's CursorWindow limit.
///
/// On Android, sqflite copies every result row into a CursorWindow that holds about 2 MB. A cell bigger than that can
/// be written (inserts bind the value directly) but never read back: the query throws "Row too big to fit into
/// CursorWindow". On 19 Nov 2026 the cached course catalogue (snapshot key `learning`) passed that size, so every start
/// threw while hydrating it and the app could not open. Resetting stored data did not help, because the first refresh
/// downloaded the same body and stored it again.
///
/// The read here asks for the cell's length first and, when it is large, pulls it in slices with `substr`, each well
/// under the window (256 Ki characters is at most 1 MiB of UTF-8). It works for rows already on the phone, so no
/// migration is needed, and it behaves the same on desktop and web, where there is no window to hit.
library;

import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

/// Characters (TEXT) or bytes (BLOB) per slice. 256 Ki characters is at most 1 MiB in UTF-8, half the window.
const int kCursorSafeSlice = 256 * 1024;

/// The TEXT value of [column] in the first row of [table] matching [where], read in slices when large, or null when
/// no row matches or the value is null. [slice] is only lowered by tests.
Future<String?> readTextCursorSafe(
  DatabaseExecutor db, {
  required String table,
  required String column,
  required String where,
  required List<Object?> whereArgs,
  int slice = kCursorSafeSlice,
}) async {
  final head = await db.rawQuery('SELECT length($column) AS n FROM $table WHERE $where LIMIT 1', whereArgs);
  if (head.isEmpty) return null;
  final n = head.first['n'] as int?;
  if (n == null) return null;
  if (n <= slice) {
    final rows = await db.rawQuery('SELECT $column AS v FROM $table WHERE $where LIMIT 1', whereArgs);
    return rows.isEmpty ? null : rows.first['v'] as String?;
  }
  final out = StringBuffer();
  for (var start = 1; start <= n; start += slice) {
    final rows = await db.rawQuery(
        'SELECT substr($column, ?, ?) AS v FROM $table WHERE $where LIMIT 1', [start, slice, ...whereArgs]);
    if (rows.isEmpty) return null; // the row went away between slices
    out.write(rows.first['v'] as String? ?? '');
  }
  return out.toString();
}

/// The BLOB value of [column], read the same way. `length` and `substr` count bytes for a BLOB.
Future<Uint8List?> readBlobCursorSafe(
  DatabaseExecutor db, {
  required String table,
  required String column,
  required String where,
  required List<Object?> whereArgs,
  int slice = kCursorSafeSlice,
}) async {
  final head =
      await db.rawQuery('SELECT length($column) AS n, typeof($column) AS t FROM $table WHERE $where LIMIT 1', whereArgs);
  if (head.isEmpty) return null;
  final n = head.first['n'] as int?;
  if (n == null) return null;
  if (n <= slice || head.first['t'] != 'blob') {
    final rows = await db.rawQuery('SELECT $column AS v FROM $table WHERE $where LIMIT 1', whereArgs);
    return rows.isEmpty ? null : _bytes(rows.first['v']);
  }
  final out = BytesBuilder(copy: false);
  for (var start = 1; start <= n; start += slice) {
    final rows = await db.rawQuery(
        'SELECT substr($column, ?, ?) AS v FROM $table WHERE $where LIMIT 1', [start, slice, ...whereArgs]);
    if (rows.isEmpty) return null;
    final part = _bytes(rows.first['v']);
    if (part != null) out.add(part);
  }
  return out.toBytes();
}

Uint8List? _bytes(Object? v) {
  if (v == null) return null;
  if (v is Uint8List) return v;
  if (v is List<int>) return Uint8List.fromList(v);
  return null;
}
