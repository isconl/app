import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// BN26083103: exercises the lesson_resume table's schema and access
/// pattern (upsert-by-(course,file), read-back) against a real (ffi, not
/// device-channel) SQLite database. Deliberately does NOT go through
/// AppDb.open() (needs path_provider's platform channel, not available
/// under `flutter test`) -- mirrors vault_mirror_test.dart's approach,
/// with the exact same CREATE TABLE/insert/query shape db.dart's
/// AppDb.saveLessonResumeLocal()/lessonResumeLocal() use.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<Database> freshDb() async {
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await db.execute('''
      CREATE TABLE lesson_resume (
        course TEXT NOT NULL,
        file TEXT NOT NULL,
        scroll_pct INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (course, file)
      )''');
    return db;
  }

  Future<void> saveLocal(Database db, String course, String file, int scrollPct) =>
      db.insert(
        'lesson_resume',
        {
          'course': course,
          'file': file,
          'scroll_pct': scrollPct,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<int?> readLocal(Database db, String course, String file) async {
    final rows = await db.query('lesson_resume',
        columns: ['scroll_pct'],
        where: 'course = ? AND file = ?',
        whereArgs: [course, file],
        limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['scroll_pct'] as int?;
  }

  test('no saved position returns null', () async {
    final db = await freshDb();
    expect(await readLocal(db, 'med-anatomy', '00-orientation.md'), isNull);
  });

  test('save then read round-trips the scroll percentage', () async {
    final db = await freshDb();
    await saveLocal(db, 'med-anatomy', '00-orientation.md', 42);
    expect(await readLocal(db, 'med-anatomy', '00-orientation.md'), 42);
  });

  test('a second save for the same (course, file) replaces, not duplicates', () async {
    final db = await freshDb();
    await saveLocal(db, 'med-anatomy', '00-orientation.md', 10);
    await saveLocal(db, 'med-anatomy', '00-orientation.md', 90);
    expect(await readLocal(db, 'med-anatomy', '00-orientation.md'), 90);
    final rows = await db.query('lesson_resume');
    expect(rows.length, 1);
  });

  test('different lessons in the same course track independently', () async {
    final db = await freshDb();
    await saveLocal(db, 'med-anatomy', '00-orientation.md', 20);
    await saveLocal(db, 'med-anatomy', '01-skeletal-system.md', 75);
    expect(await readLocal(db, 'med-anatomy', '00-orientation.md'), 20);
    expect(await readLocal(db, 'med-anatomy', '01-skeletal-system.md'), 75);
  });
}
