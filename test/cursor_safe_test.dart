// BI26111901: "Row too big to fit into CursorWindow" stopped the app starting on 19 Nov 2026. The cached course
// catalogue (snapshot `learning`) passed Android's 2 MB per-row read limit. Desktop sqlite has no such limit, so
// _WindowedDb below throws exactly the way Android does whenever a returned row is over 2 MB. These tests prove the
// limit reproduces, that every large-cell read in the app now stays under it, and that a cache row which cannot be
// read is dropped rather than thrown. The last test is a guard: it fails if new code reads a large cache column
// with a plain query.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/data/cursor_safe.dart';
import 'package:isconl/data/db.dart';
import 'package:isconl/study/cdm/cdm_cache.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Android's CursorWindow default, 2 MB.
const _window = 2 * 1024 * 1024;

int _cellBytes(Object? v) {
  if (v is String) return utf8.encode(v).length;
  if (v is List<int>) return v.length;
  return 8;
}

/// Wraps a real database and refuses any result row larger than the window, the way Android's CursorWindow does.
class _WindowedDb implements Database {
  _WindowedDb(this._inner);
  final Database _inner;
  int largestRow = 0;

  List<Map<String, Object?>> _check(List<Map<String, Object?>> rows) {
    for (final r in rows) {
      final size = r.values.fold<int>(0, (a, v) => a + _cellBytes(v));
      if (size > largestRow) largestRow = size;
      if (size > _window) {
        throw Exception('DatabaseException(Row too big to fit into CursorWindow requiredPos=0, totalRows=1)');
      }
    }
    return rows;
  }

  @override
  Future<List<Map<String, Object?>>> query(String table,
          {bool? distinct,
          List<String>? columns,
          String? where,
          List<Object?>? whereArgs,
          String? groupBy,
          String? having,
          String? orderBy,
          int? limit,
          int? offset}) async =>
      _check(await _inner.query(table,
          distinct: distinct,
          columns: columns,
          where: where,
          whereArgs: whereArgs,
          groupBy: groupBy,
          having: having,
          orderBy: orderBy,
          limit: limit,
          offset: offset));

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async =>
      _check(await _inner.rawQuery(sql, arguments));

  @override
  Future<int> insert(String table, Map<String, Object?> values,
          {String? nullColumnHack, ConflictAlgorithm? conflictAlgorithm}) =>
      _inner.insert(table, values, nullColumnHack: nullColumnHack, conflictAlgorithm: conflictAlgorithm);

  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) =>
      _inner.delete(table, where: where, whereArgs: whereArgs);

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) => _inner.execute(sql, arguments);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

Future<Database> _open() async {
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false));
  await db.execute('CREATE TABLE snapshots (key TEXT PRIMARY KEY, json TEXT NOT NULL, fetched_at INTEGER NOT NULL)');
  await CdmCache.createTables(db);
  return db;
}

/// A catalogue-shaped body of about [mb] MB, with multi-byte characters so slicing by characters is exercised.
Map<String, dynamic> _bigCatalogue(double mb) {
  final lessons = <Map<String, dynamic>>[];
  var size = 0;
  var i = 0;
  while (size < mb * 1024 * 1024) {
    final title = 'Module $i: anaesthesia — café ✓ 呼吸 ${'x' * 400}';
    lessons.add({'file': 'm$i.md', 'title': title, 'status': 'new'});
    size += utf8.encode(title).length + 40;
    i++;
  }
  return {
    'courses': [
      {'ID': 'bme', 'lessons': lessons}
    ]
  };
}

void main() {
  setUpAll(sqfliteFfiInit);

  test('the simulator reproduces the 19 Nov failure on a plain read', () async {
    final raw = await _open();
    final db = _WindowedDb(raw);
    final app = AppDb.forTesting(db);
    await app.putSnapshot('learning', _bigCatalogue(3));
    expect(() => db.query('snapshots', where: 'key = ?', whereArgs: ['learning'], limit: 1), throwsException);
    await raw.close();
  });

  test('a 3 MB learning snapshot reads back whole, every row under the window', () async {
    final raw = await _open();
    final db = _WindowedDb(raw);
    final app = AppDb.forTesting(db);
    final body = _bigCatalogue(3);
    await app.putSnapshot('learning', body);
    final got = await app.getSnapshot('learning');
    expect(got, isNotNull);
    expect(jsonEncode(got!.$1), jsonEncode(body));
    expect(db.largestRow, lessThanOrEqualTo(_window));
    await raw.close();
  });

  test('slicing by characters keeps multi-byte text intact', () async {
    final raw = await _open();
    final text = 'aé✓呼吸😀b' * 37;
    await raw.insert('snapshots', {'key': 'k', 'json': text, 'fetched_at': 0});
    for (final slice in [1, 2, 3, 7, 64, 100000]) {
      final got = await readTextCursorSafe(raw,
          table: 'snapshots', column: 'json', where: 'key = ?', whereArgs: ['k'], slice: slice);
      expect(got, text, reason: 'slice $slice');
    }
    expect(
        await readTextCursorSafe(raw, table: 'snapshots', column: 'json', where: 'key = ?', whereArgs: ['none']),
        isNull);
    await raw.close();
  });

  test('blobs slice by bytes', () async {
    final raw = await _open();
    final bytes = Uint8List.fromList(List.generate(10007, (i) => i % 251));
    await raw.insert('cdm_images', {'url': 'u', 'bytes': bytes, 'fetched_at': 0});
    for (final slice in [1, 13, 4096, 1 << 20]) {
      final got =
          await readBlobCursorSafe(raw, table: 'cdm_images', column: 'bytes', where: 'url = ?', whereArgs: ['u'], slice: slice);
      expect(got, bytes, reason: 'slice $slice');
    }
    await raw.close();
  });

  test('a large deck document and a large image read back under the window', () async {
    final raw = await _open();
    final db = _WindowedDb(raw);
    final cache = CdmCache(db);
    final doc = jsonEncode(_bigCatalogue(2.5));
    await raw.insert('cdm_cache', {'doc_id': 'd', 'version': '1', 'content_hash': '', 'json': doc, 'fetched_at': 0});
    expect(await cache.readRaw('d', '1'), doc);
    final img = Uint8List.fromList(List.generate(3 * 1024 * 1024, (i) => i % 256));
    await raw.insert('cdm_images', {'url': 'i', 'bytes': img, 'fetched_at': 0});
    final got = await cache.image('i', (_) async => fail('must come from the cache'));
    expect(got, img);
    expect(db.largestRow, lessThanOrEqualTo(_window));
    await raw.close();
  });

  test('an unreadable snapshot is dropped and reads as a miss, never thrown', () async {
    final raw = await _open();
    final app = AppDb.forTesting(raw);
    await raw.insert('snapshots', {'key': 'learning', 'json': '{not json', 'fetched_at': 0});
    expect(await app.getSnapshot('learning'), isNull);
    expect(await raw.query('snapshots', where: 'key = ?', whereArgs: ['learning']), isEmpty);
    await raw.close();
  });

  // Guard: the large cache columns (snapshots.json, cdm_cache.json, cdm_images.bytes) are read only through
  // cursor_safe.dart. A plain query of these tables must name its columns, and those columns must not include the
  // large one. This fails the build before an oversized read can reach a phone again.
  test('no plain read of a large cache column anywhere in lib/', () {
    final offences = <String>[];
    final call = RegExp(r"""\.(query|rawQuery)\(\s*(['"])([^'"]*)\2""");
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.replaceAll('\\', '/').endsWith('data/cursor_safe.dart')) continue;
      final src = f.readAsStringSync();
      for (final m in call.allMatches(src)) {
        final first = m.group(3)!;
        final end = src.indexOf(');', m.end);
        final args = src.substring(m.end, end < 0 ? src.length : end);
        final where = '${f.path}:${'\n'.allMatches(src.substring(0, m.start)).length + 1}';
        if (m.group(1) == 'query' && const ['snapshots', 'cdm_cache', 'cdm_images'].contains(first)) {
          final cols = RegExp(r'columns:\s*\[([^\]]*)\]').firstMatch(args);
          if (cols == null || RegExp(r"""['"](json|bytes)['"]""").hasMatch(cols.group(1)!)) offences.add(where);
        }
        if (m.group(1) == 'rawQuery') {
          final sql = first.toLowerCase();
          final big = RegExp(r'from\s+(snapshots|cdm_cache|cdm_images)\b').hasMatch(sql);
          if (big && (sql.contains('*') || RegExp(r'\b(json|bytes)\b').hasMatch(sql.split(' from ').first))) {
            offences.add(where);
          }
        }
      }
    }
    expect(offences, isEmpty,
        reason: 'read these through readTextCursorSafe / readBlobCursorSafe (lib/data/cursor_safe.dart): $offences');
  });
}
