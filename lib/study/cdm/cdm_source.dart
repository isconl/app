/// BI26092620: how the phone reaches deck documents, through the hub.
///
/// Clients go through hub rather than straight to deck (one token, capability
/// routing, hub's own cache). The two paths below are the contract this client
/// speaks; hub serves them from deck's `GET /collections/{id}/manifest` and
/// `GET /docs/{id}@{version}` (the hub side is its own row, so until it ships
/// every call here fails soft and the lesson screen keeps using markdown).
library;

import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../api/client.dart';
import 'cdm_cache.dart';
import 'cdm_model.dart';

class CdmSource {
  CdmSource(this.api, this.cache);

  final ApiClient api;
  final CdmCache cache;

  /// Hub path of the manifest of every document the reader may open.
  static const manifestPath = '/api/study/manifest';

  /// Hub path of one immutable document version.
  static String docPath(String docId, String version) =>
      '/api/study/docs/${Uri.encodeComponent(docId)}@${Uri.encodeComponent(version)}';

  /// One document version as JSON text, or null when it cannot be reached.
  Future<String?> fetchDoc(String docId, String version) async {
    try {
      final r = await api.getConditional(docPath(docId, version), cold: true);
      return r.status == 200 && r.body.isNotEmpty ? r.body : null;
    } on ApiException {
      return null;
    } on OfflineException {
      return null;
    }
  }

  /// Revalidates the manifest. Null means "not modified" (or unreachable); the
  /// distinction does not matter to a sync, which has nothing to do either way.
  Future<CdmManifest?> fetchManifest(String? etag) async {
    try {
      final r = await api.getConditional(manifestPath, etag: etag);
      if (r.status == 304 || r.body.isEmpty) return null;
      return CdmCache.parseManifest(r.body, etag: r.etag);
    } on ApiException {
      return null;
    } on OfflineException {
      return null;
    }
  }

  /// Image bytes. A deck image URL is absolute and signed, so it is fetched as
  /// is; a relative one goes through the hub with the session token.
  Future<Uint8List?> fetchImage(String url) async {
    try {
      if (url.startsWith('http://') || url.startsWith('https://')) {
        final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
        return res.statusCode == 200 ? res.bodyBytes : null;
      }
      final r = await api.getBytes(url);
      return Uint8List.fromList(r.bytes);
    } catch (_) {
      return null;
    }
  }

  /// Opens a document from the cache, fetching only when that version is absent.
  Future<CdmDoc?> open(String docId, String version) => cache.open(docId, version, fetchDoc);

  /// Pulls what the manifest says moved. Safe to call whenever online.
  Future<CdmSyncResult> sync() => cache.sync(fetchManifest, fetchDoc);

  /// Decodes a manifest body, exposed for callers that already hold one.
  static CdmManifest manifestFromBody(String body, {String? etag}) => CdmCache.parseManifest(body, etag: etag);
}
