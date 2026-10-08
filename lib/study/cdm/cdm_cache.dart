/// BI26092620: the on-device cache of deck documents, keyed by `doc@version`.
///
/// A published version never changes, so a cached `(doc_id, version)` is correct
/// forever and opening a module is a local read. The network is touched only when
/// that exact version is absent, and a sync fetches only what the manifest says
/// moved. The manifest itself is revalidated with an ETag, so with nothing
/// published it is one 304 and no document traffic at all.
///
/// Works on a plain sqflite [Database] so a test can hand it an in-memory ffi one;
/// `AppDb` owns the real one and calls [CdmCache.createTables] on create/upgrade.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import 'cdm_model.dart';

/// Fetches one document version as JSON text, or null when it cannot be reached.
typedef CdmDocFetch = Future<String?> Function(String docId, String version);

/// Revalidates the manifest. Returns null for "not modified" (a 304), otherwise
/// the entries and the ETag to send next time.
typedef CdmManifestFetch = Future<CdmManifest?> Function(String? etag);

/// Fetches image bytes, or null when the image cannot be reached.
typedef CdmImageFetch = Future<Uint8List?> Function(String url);

class CdmManifestEntry {
  const CdmManifestEntry({required this.docId, required this.version, this.contentHash = ''});
  final String docId;
  final String version;
  final String contentHash;
}

class CdmManifest {
  const CdmManifest(this.entries, {this.etag});
  final List<CdmManifestEntry> entries;
  final String? etag;
}

class CdmSyncResult {
  const CdmSyncResult({this.notModified = false, this.fetched = const [], this.failed = const []});

  /// The manifest answered 304: nothing was compared or fetched.
  final bool notModified;

  /// Documents pulled because their version moved or was never cached.
  final List<String> fetched;

  /// Documents that moved but could not be fetched (offline mid-sync).
  final List<String> failed;
}

class CdmCache {
  CdmCache(this._db);
  final Database _db;

  /// How many versions of one document are kept. Two covers "the reader is
  /// mid-module when a new version publishes" without growing without bound.
  static const keepVersions = 2;

  static const _manifestEtagKey = 'manifest_etag';

  static Future<void> createTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cdm_cache (
        doc_id TEXT NOT NULL,
        version TEXT NOT NULL,
        content_hash TEXT NOT NULL,
        json TEXT NOT NULL,
        fetched_at INTEGER NOT NULL,
        PRIMARY KEY (doc_id, version)
      )''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cdm_images (
        url TEXT PRIMARY KEY,
        bytes BLOB NOT NULL,
        fetched_at INTEGER NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cdm_meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )''');
  }

  // ---- documents ----

  /// The cached JSON text of one version, or null.
  Future<String?> readRaw(String docId, String version) async {
    final rows = await _db.query('cdm_cache',
        columns: ['json'], where: 'doc_id = ? AND version = ?', whereArgs: [docId, version], limit: 1);
    return rows.isEmpty ? null : rows.first['json'] as String;
  }

  Future<bool> has(String docId, String version) async => await readRaw(docId, version) != null;

  Future<void> write(String docId, String version, String json, {String contentHash = ''}) async {
    await _db.insert(
      'cdm_cache',
      {
        'doc_id': docId,
        'version': version,
        'content_hash': contentHash,
        'json': json,
        'fetched_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _prune(docId);
  }

  /// Keeps the newest [keepVersions] versions of a document by fetch time.
  Future<void> _prune(String docId) async {
    final rows = await _db.query('cdm_cache',
        columns: ['version'], where: 'doc_id = ?', whereArgs: [docId], orderBy: 'fetched_at DESC, version DESC');
    for (final r in rows.skip(keepVersions)) {
      await _db.delete('cdm_cache', where: 'doc_id = ? AND version = ?', whereArgs: [docId, r['version']]);
    }
  }

  /// The version of a document the device holds newest, or null.
  Future<String?> latestVersion(String docId) async {
    final rows = await _db.query('cdm_cache',
        columns: ['version'], where: 'doc_id = ?', whereArgs: [docId], orderBy: 'fetched_at DESC, version DESC', limit: 1);
    return rows.isEmpty ? null : rows.first['version'] as String;
  }

  /// Opens a document: from the cache when that exact version is there (zero
  /// network), otherwise through [fetch] and then cached. Returns null when it is
  /// neither cached nor reachable, or when the payload is not a document.
  Future<CdmDoc?> open(String docId, String version, CdmDocFetch fetch) async {
    var raw = await readRaw(docId, version);
    if (raw == null) {
      raw = await fetch(docId, version);
      if (raw == null) return null;
      try {
        CdmDoc.fromJsonString(raw);
      } on FormatException {
        return null; // never cache something that is not a document
      }
      await write(docId, version, raw);
    }
    try {
      return CdmDoc.fromJsonString(raw);
    } on FormatException {
      // A corrupt row must not pin the module as unreadable: drop it so the next open refetches.
      await _db.delete('cdm_cache', where: 'doc_id = ? AND version = ?', whereArgs: [docId, version]);
      return null;
    }
  }

  // ---- manifest sync ----

  /// Pulls the manifest (a 304 usually) and fetches only the documents whose
  /// version is not already on the device.
  Future<CdmSyncResult> sync(CdmManifestFetch manifest, CdmDocFetch fetch) async {
    final etag = await _meta(_manifestEtagKey);
    final m = await manifest(etag);
    if (m == null) return const CdmSyncResult(notModified: true);
    final fetched = <String>[];
    final failed = <String>[];
    for (final e in m.entries) {
      if (await has(e.docId, e.version)) continue;
      final raw = await fetch(e.docId, e.version);
      if (raw == null) {
        failed.add(e.docId);
        continue;
      }
      try {
        CdmDoc.fromJsonString(raw);
      } on FormatException {
        failed.add(e.docId);
        continue;
      }
      await write(e.docId, e.version, raw, contentHash: e.contentHash);
      fetched.add(e.docId);
    }
    // Remember the ETag only when everything it describes is on the device, so a
    // half-finished sync is retried in full instead of being answered with a 304.
    if (failed.isEmpty && m.etag != null) await _setMeta(_manifestEtagKey, m.etag!);
    return CdmSyncResult(fetched: fetched, failed: failed);
  }

  // ---- images ----

  /// Image bytes from the cache, else fetched once and kept, so a module's
  /// pictures survive going offline.
  Future<Uint8List?> image(String url, CdmImageFetch fetch) async {
    final rows = await _db.query('cdm_images', columns: ['bytes'], where: 'url = ?', whereArgs: [url], limit: 1);
    if (rows.isNotEmpty) return Uint8List.fromList(rows.first['bytes'] as List<int>);
    final bytes = await fetch(url);
    if (bytes == null || bytes.isEmpty) return null;
    await _db.insert(
      'cdm_images',
      {'url': url, 'bytes': bytes, 'fetched_at': DateTime.now().millisecondsSinceEpoch},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return bytes;
  }

  // ---- meta ----

  Future<String?> _meta(String key) async {
    final rows = await _db.query('cdm_meta', columns: ['value'], where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> _setMeta(String key, String value) => _db
      .insert('cdm_meta', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);

  /// Used by tests that decode a manifest body.
  static CdmManifest parseManifest(String body, {String? etag}) {
    final j = jsonDecode(body);
    final list = j is Map ? (j['docs'] ?? j['documents'] ?? j['items']) : j;
    final out = <CdmManifestEntry>[];
    if (list is List) {
      for (final e in list) {
        if (e is! Map) continue;
        final id = '${e['id'] ?? e['doc_id'] ?? ''}';
        final v = '${e['version'] ?? ''}';
        if (id.isEmpty || v.isEmpty) continue;
        out.add(CdmManifestEntry(docId: id, version: v, contentHash: '${e['contentHash'] ?? e['content_hash'] ?? ''}'));
      }
    }
    return CdmManifest(out, etag: etag);
  }
}
