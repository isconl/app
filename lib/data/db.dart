import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../study/cdm/cdm_cache.dart';
import 'vault_mirror.dart';

/// Local persistence. The vault ENGINE on the server remains the single
/// source of truth for this app's data (constitution 2.7); everything here
/// is cache plus a queue of not-yet-delivered writes -- this contract is
/// unchanged and still correct after BI26083005. What changed is what
/// backs the vault ENGINE itself: it's an encrypted local SQLite file now
/// (`VAULT_STORE_ENGINE=sqlite`), backed up to OneDrive on a schedule --
/// OneDrive is a backup copy, never live-read, never the arbiter of a
/// conflict, not "the vault" this comment means when it says "truth."
class AppDb {
  AppDb._(this._db);
  @visibleForTesting
  factory AppDb.forTesting(Database db) => AppDb._(db);
  final Database _db;

  /// BI26092620: deck documents cached per version, plus their images.
  late final CdmCache cdm = CdmCache(_db);

  static Future<AppDb> open() async {
    // Web has no filesystem; ffi-web keys its IndexedDB store off a bare
    // logical name rather than a joined directory path (see main.dart's
    // databaseFactoryFfiWeb wiring).
    final path = kIsWeb
        ? 'isconl.db'
        : p.join((await getApplicationDocumentsDirectory()).path, 'isconl.db');
    final db = await openDatabase(
      path,
      // v6 (BI26092620): added cdm_cache, cdm_images and cdm_meta, the on-device
      // cache of deck documents keyed by doc@version.
      // v5 (BI26092613): added lesson_progress table for local-first
      // module status tracking (Opened/Learning/Done), and added fraction
      // column to lesson_resume for scroll position fraction.
      // v4 (BI26092614): added lesson_notes, local storage for module notes
      // with paragraph/block anchor tracking.
      // v3 (BN26083103): added lesson_resume, an always-on local table for
      // offline-safe scroll-position tracking -- separate from the
      // server-side saveLessonResume() mutation (queueable:false, so an
      // offline write there is simply dropped, not queued). This table is
      // written unconditionally, online or offline, since it's on-device;
      // the server mutation stays best-effort on top of it.
      // v2 (BN26083107): added the vault-mirror tables (real per-collection
      // tables matching a slice of vault's own schema -- see
      // vault_schema.dart) alongside the pre-existing generic snapshot
      // cache, which stays as-is. onUpgrade only needs to ADD the new
      // tables for an existing install; onCreate covers both for a fresh one.
      // v7 (BI26100325): lesson_resume also remembers WHERE by block (index,
      // movement, how many blocks, words left, title), so reading resumes at the
      // same block after a font-size or renderer change, and Today can offer
      // "Continue reading" without opening the module.
      version: 8,
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
        await CdmCache.createTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await ensureVaultMirrorTables(db);
        if (oldVersion < 3) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS lesson_resume (
              course TEXT NOT NULL,
              file TEXT NOT NULL,
              scroll_pct INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              PRIMARY KEY (course, file)
            )''');
        }
        if (oldVersion < 4) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS lesson_notes (
              course TEXT NOT NULL,
              file TEXT NOT NULL,
              text TEXT NOT NULL,
              anchor INTEGER,
              updated_at INTEGER NOT NULL,
              PRIMARY KEY (course, file)
            )''');
        }
        if (oldVersion < 5) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS lesson_progress (
              course TEXT NOT NULL,
              file TEXT NOT NULL,
              status TEXT NOT NULL,
              updated_at INTEGER NOT NULL,
              PRIMARY KEY (course, file)
            )''');
          try {
            await db.execute('ALTER TABLE lesson_resume ADD COLUMN fraction REAL');
          } catch (_) {}
        }
        if (oldVersion < 6) await CdmCache.createTables(db);
        if (oldVersion < 7) {
          for (final col in const [
            'block_index INTEGER',
            'movement TEXT',
            'blocks_total INTEGER',
            'words_left INTEGER',
            'title TEXT',
          ]) {
            try {
              await db.execute('ALTER TABLE lesson_resume ADD COLUMN $col');
            } catch (_) {}
          }
        }
        if (oldVersion < 8) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS study_sessions (
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
        }
      },
    );
    return AppDb._(db);
  }

  // ---- snapshots ----

  Future<void> putSnapshot(String key, dynamic value) async {
    await _db.insert(
      'snapshots',
      {
        'key': key,
        'json': jsonEncode(value),
        'fetched_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<(dynamic, DateTime)?> getSnapshot(String key) async {
    final rows = await _db
        .query('snapshots', where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    try {
      final value = jsonDecode(rows.first['json'] as String);
      final at = DateTime.fromMillisecondsSinceEpoch(
          rows.first['fetched_at'] as int);
      return (value, at);
    } catch (_) {
      return null;
    }
  }

  /// Keys only, for building an index of what is already on the device without
  /// decoding every cached body. The module library uses it to answer "what can
  /// I read offline" in one query.
  Future<List<String>> snapshotKeysWithPrefix(String prefix) async {
    final rows = await _db.query('snapshots',
        columns: ['key'], where: 'key LIKE ?', whereArgs: ['$prefix%']);
    return rows.map((r) => r['key'] as String).toList();
  }

  Future<void> deleteSnapshot(String key) =>
      _db.delete('snapshots', where: 'key = ?', whereArgs: [key]).then((_) {});

  /// Wipes every cached body. Sign-out only.
  ///
  /// NOTE: this takes the downloaded learning modules with it, which is correct
  /// on sign-out (the mirror belongs to a session) and would be wrong anywhere
  /// else. Nothing but sign-out may call it - a downloaded module stays until
  /// its content changes or ARCHITECT forgets it deliberately.
  Future<void> deleteSnapshots() => _db.delete('snapshots').then((_) {});

  // ---- outbox ----

  Future<int> enqueue({
    required String method,
    required String path,
    required Map<String, dynamic> body,
    required String label,
    required String view,
  }) {
    return _db.insert('outbox', {
      'method': method,
      'path': path,
      'body': jsonEncode(body),
      'label': label,
      'view': view,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'status': 'pending',
    });
  }

  Future<List<Map<String, dynamic>>> pendingOutbox() async {
    final rows = await _db.query('outbox',
        where: "status = 'pending' OR status = 'failed'",
        orderBy: 'id ASC');
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  Future<int> pendingCount() async {
    final rows = await _db.rawQuery(
        "SELECT COUNT(*) AS n FROM outbox WHERE status = 'pending' OR status = 'failed'");
    return (rows.first['n'] as int?) ?? 0;
  }

  Future<void> markOutbox(int id, String status, [String? error]) async {
    await _db.update('outbox', {'status': status, 'error': error},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteOutbox(int id) async {
    await _db.delete('outbox', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> pruneSentOutbox() async {
    // Keep the last 50 delivered actions for the activity trail.
    await _db.rawDelete('''
      DELETE FROM outbox WHERE status = 'sent' AND id NOT IN
        (SELECT id FROM outbox WHERE status = 'sent' ORDER BY id DESC LIMIT 50)
    ''');
  }

  Future<List<Map<String, dynamic>>> outboxHistory({int limit = 80}) async {
    final rows =
        await _db.query('outbox', orderBy: 'id DESC', limit: limit);
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  // ---- chat ----

  Future<void> addChat(String role, String text,
      {Map<String, dynamic>? meta}) async {
    await _db.insert('chat', {
      'role': role,
      'text': text,
      'meta': meta == null ? null : jsonEncode(meta),
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
    await _db.rawDelete('''
      DELETE FROM chat WHERE id NOT IN
        (SELECT id FROM chat ORDER BY id DESC LIMIT 200)
    ''');
  }

  Future<List<Map<String, dynamic>>> chatHistory({int limit = 100}) async {
    final rows = await _db.query('chat', orderBy: 'id DESC', limit: limit);
    return rows.reversed.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  Future<void> clearChat() => _db.delete('chat').then((_) {});

  // ---- lesson resume (BN26083103, BI26092613) ----

  /// Always-on, offline-safe scroll-position write -- unconditional, online
  /// or offline, since it's purely on-device. This is the real "absolutely
  /// aware" local source of truth; the server-side saveLessonResume()
  /// mutation is best-effort on top of it, not a replacement for it.
  ///
  /// BI26092613: "For scroll position the newest timestamp wins."
  /// Saved locally as a fraction 0 to 1 and scroll_pct.
  Future<void> saveLessonResumeLocal({
    required String course,
    required String file,
    required int scrollPct,
    double? fraction,
    int? updatedAt,
    ReadingAnchor? anchor,
  }) async {
    final now = updatedAt ?? DateTime.now().millisecondsSinceEpoch;
    final existing = await _db.query(
      'lesson_resume',
      columns: ['updated_at'],
      where: 'course = ? AND file = ?',
      whereArgs: [course, file],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      final prevUpdated = existing.first['updated_at'] as int?;
      if (prevUpdated != null && prevUpdated > now) {
        return;
      }
    }
    final effectiveFraction = fraction ?? (scrollPct / 100.0).clamp(0.0, 1.0);
    final data = <String, dynamic>{
      'course': course,
      'file': file,
      'scroll_pct': scrollPct,
      'updated_at': now,
    };
    try {
      await _db.insert(
        'lesson_resume',
        {
          ...data,
          'fraction': effectiveFraction,
          if (anchor != null) ...anchor.toColumns(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {
      await _db.insert(
        'lesson_resume',
        data,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  /// The saved scroll percentage (0-100) for one lesson, or null if this
  /// lesson has never had a position saved on this device.
  Future<int?> lessonResumeLocal({
    required String course,
    required String file,
  }) async {
    final rows = await _db.query(
      'lesson_resume',
      columns: ['scroll_pct'],
      where: 'course = ? AND file = ?',
      whereArgs: [course, file],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['scroll_pct'] as int?;
  }

  /// The saved block anchor for one lesson, or null when none was saved
  /// (positions saved before v7 only have a fraction).
  Future<ReadingAnchor?> lessonAnchorLocal({
    required String course,
    required String file,
  }) async {
    try {
      final rows = await _db.query('lesson_resume',
          where: 'course = ? AND file = ?', whereArgs: [course, file], limit: 1);
      if (rows.isEmpty) return null;
      return ReadingAnchor.fromRow(rows.first);
    } catch (_) {
      return null;
    }
  }

  /// BI26100325: the most recently read module that is not finished, for the
  /// Today "Continue reading" card. Finished modules (status done) drop off.
  Future<ReadingAnchor?> latestUnfinishedReading() async {
    try {
      final rows = await _db.rawQuery('''
        SELECT r.* FROM lesson_resume r
        LEFT JOIN lesson_progress p ON p.course = r.course AND p.file = r.file
        WHERE r.block_index IS NOT NULL
          AND COALESCE(lower(p.status), '') != 'done'
        ORDER BY r.updated_at DESC LIMIT 1''');
      if (rows.isEmpty) return null;
      return ReadingAnchor.fromRow(rows.first);
    } catch (_) {
      return null;
    }
  }

  /// The saved scroll fraction (0.0 to 1.0) for one lesson, or null if none saved.
  Future<double?> lessonResumeFractionLocal({
    required String course,
    required String file,
  }) async {
    try {
      final rows = await _db.query(
        'lesson_resume',
        columns: ['scroll_pct', 'fraction'],
        where: 'course = ? AND file = ?',
        whereArgs: [course, file],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final row = rows.first;
      if (row['fraction'] != null) {
        return (row['fraction'] as num).toDouble();
      }
      final pct = row['scroll_pct'] as int?;
      return pct != null ? pct / 100.0 : null;
    } catch (_) {
      final pct = await lessonResumeLocal(course: course, file: file);
      return pct != null ? pct / 100.0 : null;
    }
  }

  // ---- lesson progress (BI26092613) ----

  /// Rank for status: done (3) > learning (2) > opened (1) > new (0).
  static int statusRank(String? status) {
    switch (status?.toLowerCase().trim()) {
      case 'done':
        return 3;
      case 'learning':
        return 2;
      case 'opened':
        return 1;
      case 'new':
      default:
        return 0;
    }
  }

  /// Merges two statuses by rank, never downgrading automatically.
  static String mergeStatus(String? a, String? b) {
    final rankA = statusRank(a);
    final rankB = statusRank(b);
    return rankA >= rankB
        ? (a?.toLowerCase().trim() ?? 'new')
        : (b?.toLowerCase().trim() ?? 'new');
  }

  /// Local-first module status save.
  /// Status merges by rank (done > learning > opened > new) and never
  /// downgrades automatically unless [force] is true (explicit user undo).
  Future<void> saveLessonStatusLocal({
    required String course,
    required String file,
    required String status,
    bool force = false,
    int? updatedAt,
  }) async {
    final normStatus = status.toLowerCase().trim();
    final now = updatedAt ?? DateTime.now().millisecondsSinceEpoch;
    if (!force) {
      final existing = await _db.query(
        'lesson_progress',
        columns: ['status'],
        where: 'course = ? AND file = ?',
        whereArgs: [course, file],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        final prevStatus = existing.first['status'] as String?;
        if (statusRank(prevStatus) > statusRank(normStatus)) {
          return;
        }
      }
    }
    await _db.insert(
      'lesson_progress',
      {
        'course': course,
        'file': file,
        'status': normStatus,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> lessonStatusLocal({
    required String course,
    required String file,
  }) async {
    final rows = await _db.query(
      'lesson_progress',
      columns: ['status'],
      where: 'course = ? AND file = ?',
      whereArgs: [course, file],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['status'] as String?;
  }

  Future<Map<String, String>> allLessonStatusesLocal([String? course]) async {
    final rows = course == null
        ? await _db.query('lesson_progress')
        : await _db.query(
            'lesson_progress',
            where: 'course = ?',
            whereArgs: [course],
          );
    final out = <String, String>{};
    for (final r in rows) {
      final c = r['course'] as String? ?? '';
      final f = r['file'] as String? ?? '';
      final s = r['status'] as String? ?? '';
      out['$c/$f'] = s;
    }
    return out;
  }

  // ---- lesson notes (BI26092614) ----

  /// Saves a lesson note locally with optional paragraph/block anchor.
  Future<void> saveLessonNoteLocal({
    required String course,
    required String file,
    required String text,
    int? anchor,
  }) async {
    await _db.insert(
      'lesson_notes',
      {
        'course': course,
        'file': file,
        'text': text,
        'anchor': anchor,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// The locally-saved note for one lesson, or null if none saved yet.
  Future<Map<String, dynamic>?> lessonNoteLocal({
    required String course,
    required String file,
  }) async {
    final rows = await _db.query(
      'lesson_notes',
      where: 'course = ? AND file = ?',
      whereArgs: [course, file],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }


  // ---- vault mirror (BN26083107, BI26092608) ----

  /// Extracts and upserts whatever `kMirrorSources` declares for this
  /// snapshot key -- a no-op for the (still-majority) snapshot keys with no
  /// mirror source declared yet. When [isFullPull] is true, prunes local rows
  /// not present in the server response. Called from `Snapshot.refresh()`.
  Future<Map<String, int>> mirrorSnapshot(
    String snapshotKey,
    dynamic responseJson, {
    bool isFullPull = false,
    Iterable<String>? pendingOutboxIds,
  }) =>
      mirrorSnapshotIntoVaultTables(
        _db,
        snapshotKey,
        responseJson,
        isFullPull: isFullPull,
        pendingOutboxIds: pendingOutboxIds,
      );

  /// Deletes local rows in [table] whose ID is not in [keepIds], protecting
  /// pending writes in outbox.
  Future<int> pruneVault(
    String table,
    Iterable<String> keepIds, [
    Iterable<String>? pendingOutboxIds,
  ]) =>
      pruneVaultRows(_db, table, keepIds, pendingOutboxIds);

  /// Every row currently mirrored into `table` (see `vault_schema.dart`'s
  /// `kVaultTables` for the declared columns), same shape a server-side
  /// `vault.read()` would return.
  Future<List<VaultRow>> vaultRows(String table) => readVaultRows(_db, table);

  /// Returns `base` (a decoded API response, or the cached blob) with its
  /// mirrored fields refreshed from the live per-collection tables --
  /// same JSON shape, per-row merge, never a blind replace. See
  /// `overlayVaultMirror`'s own doc comment for why. A no-op for a
  /// snapshot key with no mirror source declared.
  ///
  /// BI26092613: Also overlays local `lesson_progress` so local module
  /// status is merged by rank and never downgraded on sync.
  Future<dynamic> overlayVaultMirror(String snapshotKey, dynamic base) async {
    final baseWithMirror =
        await overlayVaultMirrorTables(_db, snapshotKey, base);
    return overlayLessonProgressLocal(_db, snapshotKey, baseWithMirror);
  }

  // ---- study sessions (BI26101606) ----
  Future<int> insertStudySession(Map<String, dynamic> row) => _db.insert('study_sessions', row);
  Future<List<Map<String, dynamic>>> getStudySessions({int limit = 100}) =>
      _db.query('study_sessions', orderBy: 'id DESC', limit: limit);
  Future<int> getStudySessionCount() async {
    final r = await _db.rawQuery('SELECT COUNT(*) as c FROM study_sessions');
    return (r.first['c'] as num?)?.toInt() ?? 0;
  }
}

/// Overlays local `lesson_progress` onto `learning` and `lesson:*` snapshots.
/// Status merges by rank (done > learning > opened > new) and never downgrades.
Future<dynamic> overlayLessonProgressLocal(
  DatabaseExecutor db,
  String snapshotKey,
  dynamic base,
) async {
  if (base == null) return base;
  try {
    if (snapshotKey == 'learning') {
      if (base is! Map) return base;
      final merged = Map<String, dynamic>.from(base);
      final courses = merged['courses'];
      if (courses is! List) return merged;

      final localRows = await db.query('lesson_progress');
      if (localRows.isEmpty) return merged;

      final localMap = <String, String>{};
      for (final r in localRows) {
        final c = r['course']?.toString() ?? '';
        final f = r['file']?.toString() ?? '';
        final s = r['status']?.toString() ?? '';
        if (c.isNotEmpty && f.isNotEmpty) {
          localMap['$c/$f'] = s;
        }
      }

      final updatedCourses = <Map<String, dynamic>>[];
      for (final courseItem in courses) {
        if (courseItem is! Map) {
          updatedCourses.add(courseItem as Map<String, dynamic>);
          continue;
        }
        final cMap = Map<String, dynamic>.from(courseItem);
        final courseId = (cMap['ID'] ?? cMap['id'] ?? '').toString();
        final lessons = cMap['lessons'];
        if (lessons is List) {
          final updatedLessons = <Map<String, dynamic>>[];
          for (final lessonItem in lessons) {
            if (lessonItem is! Map) {
              updatedLessons.add(lessonItem as Map<String, dynamic>);
              continue;
            }
            final lMap = Map<String, dynamic>.from(lessonItem);
            final file = (lMap['file'] ?? '').toString();
            final localStatus = localMap['$courseId/$file'];
            if (localStatus != null) {
              final serverStatus = lMap['status']?.toString() ?? 'new';
              lMap['status'] = AppDb.mergeStatus(localStatus, serverStatus);
            }
            updatedLessons.add(lMap);
          }
          cMap['lessons'] = updatedLessons;
        }
        updatedCourses.add(cMap);
      }
      merged['courses'] = updatedCourses;
      return merged;
    } else if (snapshotKey.startsWith('lesson:')) {
      if (base is! Map) return base;
      final parts = snapshotKey.substring('lesson:'.length).split('/');
      if (parts.length >= 2) {
        final course = parts[0];
        final file = parts.sublist(1).join('/');
        final rows = await db.query(
          'lesson_progress',
          columns: ['status'],
          where: 'course = ? AND file = ?',
          whereArgs: [course, file],
          limit: 1,
        );
        if (rows.isNotEmpty) {
          final localStatus = rows.first['status'] as String?;
          final merged = Map<String, dynamic>.from(base);
          final serverStatus = merged['status']?.toString() ?? 'new';
          merged['status'] = AppDb.mergeStatus(localStatus, serverStatus);
          return merged;
        }
      }
    }
  } catch (_) {}
  return base;
}


/// Where a reader stopped in a module, by block (BI26100325).
class ReadingAnchor {
  const ReadingAnchor({
    this.course = '',
    this.file = '',
    required this.block,
    required this.movement,
    required this.blocksTotal,
    required this.wordsLeft,
    this.title = '',
    this.updatedAt = 0,
  });

  final String course;
  final String file;

  /// Index of the first visible block.
  final int block;
  final String movement;
  final int blocksTotal;
  final int wordsLeft;
  final String title;
  final int updatedAt;

  /// About how many minutes of reading remain, at 200 words a minute (min 1 when any words are left).
  int get minutesLeft => wordsLeft <= 0 ? 0 : (wordsLeft / 200).ceil();

  Map<String, Object?> toColumns() => {
        'block_index': block,
        'movement': movement,
        'blocks_total': blocksTotal,
        'words_left': wordsLeft,
        'title': title,
      };

  static ReadingAnchor? fromRow(Map<String, Object?> r) {
    final b = r['block_index'];
    if (b is! int) return null;
    return ReadingAnchor(
      course: (r['course'] ?? '').toString(),
      file: (r['file'] ?? '').toString(),
      block: b,
      movement: (r['movement'] ?? '').toString(),
      blocksTotal: (r['blocks_total'] as int?) ?? 0,
      wordsLeft: (r['words_left'] as int?) ?? 0,
      title: (r['title'] ?? '').toString(),
      updatedAt: (r['updated_at'] as int?) ?? 0,
    );
  }
}
