// The study index cache (BI26101604): the last good /api/learning/index copy with its ETag, self-healing.
// A missing, unreadable or hash-failing cache never blocks Study: the cache builds a thin index from the modules
// already downloaded, marks the result degraded, and retries the fetch the next time it is online.
import 'dart:convert';

import 'models.dart';

abstract class StudyIndexStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class IndexFetch {
  final int status; // 200 or 304
  final String? body;
  final String? etag;
  const IndexFetch(this.status, {this.body, this.etag});
}

abstract class StudyIndexFetcher {
  /// Sends If-None-Match when [etag] is set. Throws on any network failure.
  Future<IndexFetch> fetch(String? etag);
}

typedef Hasher = String Function(String text);

class IndexLoad {
  final List<ModuleCard> cards;
  final bool degraded;
  final String? notice;
  const IndexLoad(this.cards, {this.degraded = false, this.notice});
}

class StudyIndexCache {
  static const bodyKey = 'study.index.json';
  static const metaKey = 'study.index.meta';
  final StudyIndexStore store;
  final Hasher hash;

  /// Builds the thin index from the front matter of downloaded modules (lib/data/modules.dart).
  final Future<List<ModuleCard>> Function() thinIndex;
  const StudyIndexCache({required this.store, required this.hash, required this.thinIndex});

  /// Reads the cache offline. Always returns something usable.
  Future<IndexLoad> load() async {
    final cached = await _readGood();
    if (cached != null) return IndexLoad(cached);
    List<ModuleCard> thin;
    try {
      thin = await thinIndex();
    } catch (_) {
      thin = const [];
    }
    return IndexLoad(thin,
        degraded: true, notice: thin.isEmpty ? 'The study index is not on this phone yet.' : 'The study index was missing, so this pick uses the modules you have downloaded.');
  }

  /// Fetches when online. A 304 keeps the copy; a 200 replaces it only if it parses. Returns true when the cache is
  /// good afterwards. Network failures return the previous state without throwing.
  Future<bool> refresh(StudyIndexFetcher fetcher) async {
    String? etag;
    final good = await _readGood();
    if (good != null) etag = _meta(await store.read(metaKey))?['etag'] as String?;
    try {
      final r = await fetcher.fetch(etag);
      if (r.status == 304 && good != null) return true;
      final body = r.body;
      if (r.status != 200 || body == null || _parse(body) == null) return good != null;
      await store.write(bodyKey, body);
      await store.write(metaKey, jsonEncode({'etag': r.etag, 'hash': hash(body)}));
      return true;
    } catch (_) {
      return good != null;
    }
  }

  Future<List<ModuleCard>?> _readGood() async {
    try {
      final body = await store.read(bodyKey);
      final meta = _meta(await store.read(metaKey));
      if (body == null || meta == null || meta['hash'] != hash(body)) return null;
      return _parse(body);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _meta(String? raw) {
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  List<ModuleCard>? _parse(String body) {
    try {
      final j = jsonDecode(body);
      final list = j is Map ? j['modules'] : j;
      if (list is! List) return null;
      return list.map((e) => ModuleCard.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return null;
    }
  }
}
