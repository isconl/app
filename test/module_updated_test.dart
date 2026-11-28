// BI26112303: a module republished since it was last opened shows Updated, and opening it clears that.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/api/client.dart';
import 'package:isconl/data/db.dart';
import 'package:isconl/data/modules.dart';
import 'package:isconl/data/store.dart';
import 'package:isconl/theme.dart';
import 'package:isconl/ui/views/learning.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<ModuleLibrary> _library() async {
  sqfliteFfiInit();
  final raw = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      singleInstance: false,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('CREATE TABLE snapshots (key TEXT PRIMARY KEY, json TEXT NOT NULL, fetched_at INTEGER NOT NULL)');
      },
    ),
  );
  final db = AppDb.forTesting(raw);
  ApiClient api() => ApiClient(baseUrl: 'http://test', token: 't');
  final lib = ModuleLibrary(db, Store(db, api), api);
  await lib.load();
  return lib;
}

void _manifest(ModuleLibrary lib, String rev) => lib.setManifestForTesting({
      'lessons': [
        {'course': 'c', 'file': 'm01.md', 'rev': rev},
      ],
    });

void main() {
  test('a module read at rev A and republished at rev B is Updated until it is opened again', () async {
    final lib = await _library();
    _manifest(lib, 'A');
    // First sight: taken as read at A, so the first run does not flag the whole library.
    expect(lib.isUpdated('c', 'm01.md', 'done'), isFalse);
    _manifest(lib, 'B');
    expect(lib.isUpdated('c', 'm01.md', 'done'), isTrue);
    expect(lib.isUpdated('c', 'm01.md', 'learning'), isTrue);
    expect(lib.isUpdated('c', 'm01.md', 'new'), isFalse, reason: 'a module never opened is just new');
    await lib.markRead('c', 'm01.md');
    expect(lib.isUpdated('c', 'm01.md', 'done'), isFalse, reason: 'opened at B, back to Done');
  });

  test('Updated has its own label and colour, never the grey of an unopened module', () {
    expect(statusChipColor('updated', C.green), isNot(C.text3));
    expect(moduleStatusColor('updated', C.green), isNot(C.text3));
    expect(moduleStatusWords('updated'), contains('updated'));
  });

  testWidgets('the chip reads Updated', (t) async {
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: ModuleStatusChip(status: 'updated', trackColor: C.green))));
    expect(find.text('Updated'), findsOneWidget);
  });
}
