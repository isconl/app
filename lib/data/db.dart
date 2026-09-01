import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

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
  final Database _db;

  static Future<AppDb> open() async {
    // Web has no filesystem; ffi-web keys its IndexedDB store off a bare
    // logical name rather than a joined directory path (see main.dart's
    // databaseFactoryFfiWeb wiring).
    final path = kIsWeb
        ? 'isconl.db'
        : p.join((await getApplicationDocumentsDirectory()).path, 'isconl.db');
    final db = await openDatabase(
      path,
      // v2 (BN26083107): added the vault-mirror tables (real per-collection
      // tables matching a slice of vault's own schema -- see
      // vault_schema.dart) alongside the pre-existing generic snapshot
      // cache, which stays as-is. onUpgrade only needs to ADD the new
      // tables for an existing install; onCreate covers both for a fresh one.
      version: 2,
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
        await ensureVaultMirrorTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await ensureVaultMirrorTables(db);
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

  // ---- vault mirror (BN26083107) ----

  /// Extracts and upserts whatever `kMirrorSources` declares for this
  /// snapshot key -- a no-op for the (still-majority) snapshot keys with no
  /// mirror source declared yet. Called from `Snapshot.refresh()` right
  /// after a successful fetch, alongside (not instead of) the existing
  /// `putSnapshot()` blob cache.
  Future<void> mirrorSnapshot(String snapshotKey, dynamic responseJson) =>
      mirrorSnapshotIntoVaultTables(_db, snapshotKey, responseJson);

  /// Every row currently mirrored into `table` (see `vault_schema.dart`'s
  /// `kVaultTables` for the declared columns), same shape a server-side
  /// `vault.read()` would return.
  Future<List<VaultRow>> vaultRows(String table) => readVaultRows(_db, table);

  /// Returns `base` (a decoded API response, or the cached blob) with its
  /// mirrored fields refreshed from the live per-collection tables --
  /// same JSON shape, per-row merge, never a blind replace. See
  /// `overlayVaultMirror`'s own doc comment for why. A no-op for a
  /// snapshot key with no mirror source declared.
  Future<dynamic> overlayVaultMirror(String snapshotKey, dynamic base) =>
      overlayVaultMirrorTables(_db, snapshotKey, base);
}
