/// BH26101801: everything the hold file manager reads and writes, behind one typed interface.
///
/// hold's file API is its own row (BH26102001). Until it lands the space is built against [FakeHoldApi]; [HttpHoldApi]
/// speaks the contract below and is the only thing that changes when the live routes are confirmed. Every route is
/// under /api/hold, behind guard, and names paths relative to the tenant root ("sconl/Crate/Media").
///
///   GET  /api/hold/list?path=&limit=&cursor=&sort=&dir=  -> {items:[entry], next:cursor|null}
///   GET  /api/hold/read?path=&start=&length=              -> raw bytes (ranged)
///   GET  /api/hold/recent?limit=                          -> {items:[entry]}
///   GET  /api/hold/search?q=&limit=                       -> {items:[entry]}
///   POST /api/hold/mkdir      {path}
///   POST /api/hold/rename     {path, name}
///   POST /api/hold/move       {path, to}
///   POST /api/hold/copy       {path, to}
///   POST /api/hold/delete     {path}                      (to trash, restorable)
///   POST /api/hold/restore    {path}
///   POST /api/hold/share      {path, ttl_hours}           -> {url, expires}
///   POST /api/hold/upload/begin  {path, size, hash}       -> {id, offset}
///   POST /api/hold/upload/chunk  {id, offset, data(b64)}  -> {offset}
///   POST /api/hold/upload/finish {id}                     -> {entry}
library;

import 'dart:convert';
import 'dart:typed_data';

import '../api/client.dart';
import '../util/fmt.dart' as fmt;

/// One file or folder in hold.
class HoldEntry {
  const HoldEntry({required this.path, required this.name, required this.isFolder, this.size = 0, this.modified, this.mime = '', this.trashed = false});
  final String path, name, mime;
  final bool isFolder, trashed;
  final int size;
  final DateTime? modified;

  String get parent => path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : '';
  String get extension {
    final i = name.lastIndexOf('.');
    return i <= 0 ? '' : name.substring(i + 1).toLowerCase();
  }

  /// image, pdf, audio, video, text, office, other (folders are 'folder').
  String get kind {
    if (isFolder) return 'folder';
    final m = mime.toLowerCase();
    final e = extension;
    if (m.startsWith('image/') || const {'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic'}.contains(e)) return 'image';
    if (m == 'application/pdf' || e == 'pdf') return 'pdf';
    if (m.startsWith('audio/') || const {'mp3', 'm4a', 'wav', 'ogg', 'flac', 'opus', 'aac'}.contains(e)) return 'audio';
    if (m.startsWith('video/') || const {'mp4', 'mkv', 'mov', 'webm'}.contains(e)) return 'video';
    if (m.startsWith('text/') || const {'txt', 'md', 'csv', 'json', 'log'}.contains(e)) return 'text';
    if (const {'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'odt', 'ods'}.contains(e)) return 'office';
    return 'other';
  }

  static HoldEntry from(Map<String, dynamic> m) {
    final path = fmt.s(m['path']);
    final name = fmt.s(m['name']).isNotEmpty ? fmt.s(m['name']) : path.split('/').last;
    final ms = fmt.i(m['modified']);
    return HoldEntry(
      path: path,
      name: name,
      isFolder: fmt.b(m['folder']) || fmt.b(m['isFolder']),
      size: fmt.i(m['size']),
      modified: ms > 0 ? DateTime.fromMillisecondsSinceEpoch(ms * (ms < 100000000000 ? 1000 : 1)) : null,
      mime: fmt.s(m['mime']),
      trashed: fmt.b(m['trashed']),
    );
  }
}

class HoldPage {
  const HoldPage(this.items, {this.next});
  final List<HoldEntry> items;

  /// Cursor for the next page, null when the list is complete.
  final String? next;
}

enum HoldSort { name, modified, size, type }

class HoldShare {
  const HoldShare(this.url, this.expires);
  final String url;
  final DateTime expires;
}

/// A started upload: its id and how many bytes the server already holds (the resume point).
class HoldUploadSession {
  const HoldUploadSession(this.id, this.offset);
  final String id;
  final int offset;
}

/// A failure the UI shows as a sentence; [retryable] failures go back into the upload queue's backoff.
class HoldException implements Exception {
  HoldException(this.message, {this.retryable = false});
  final String message;
  final bool retryable;
  @override
  String toString() => message;
}

abstract class HoldApi {
  Future<HoldPage> list(String path, {HoldSort sort = HoldSort.name, bool descending = false, String? cursor, int limit = 100});
  Future<List<HoldEntry>> recent({int limit = 50});
  Future<List<HoldEntry>> search(String q, {int limit = 60});
  Future<Uint8List> read(String path, {int start = 0, int? length});
  Future<void> mkdir(String path);
  Future<void> rename(String path, String name);
  Future<void> move(String path, String to);
  Future<void> copy(String path, String to);
  Future<void> delete(String path);
  Future<void> restore(String path);
  Future<HoldShare> share(String path, {int ttlHours = 24});
  Future<HoldUploadSession> beginUpload(String path, int size, String hash);
  Future<int> sendChunk(String id, int offset, Uint8List data);
  Future<HoldEntry> finishUpload(String id);
}

/// "photo.jpg" taken -> "photo (2).jpg"; never overwrites (BH26101801: conflicts keep both, with a suffix).
String conflictFreeName(String name, Set<String> taken) {
  if (!taken.contains(name)) return name;
  final dot = name.lastIndexOf('.');
  final stem = dot <= 0 ? name : name.substring(0, dot);
  final ext = dot <= 0 ? '' : name.substring(dot);
  for (var n = 2;; n++) {
    final c = '$stem ($n)$ext';
    if (!taken.contains(c)) return c;
  }
}

/// Sorts a loaded list: folders always first, then by [sort].
List<HoldEntry> sortEntries(List<HoldEntry> items, HoldSort sort, {bool descending = false}) {
  int cmp(HoldEntry a, HoldEntry b) {
    final r = switch (sort) {
      HoldSort.name => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      HoldSort.modified => (a.modified ?? DateTime(0)).compareTo(b.modified ?? DateTime(0)),
      HoldSort.size => a.size.compareTo(b.size),
      HoldSort.type => a.extension.compareTo(b.extension) != 0 ? a.extension.compareTo(b.extension) : a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    };
    return descending ? -r : r;
  }

  final out = [...items]..sort((a, b) {
      if (a.isFolder != b.isFolder) return a.isFolder ? -1 : 1;
      return cmp(a, b);
    });
  return out;
}

/// Smart sorting: a suggested name and destination for a file sitting in an `_unsorted` folder, from its date and kind.
/// Nothing moves without acceptance (the caller shows it and the user accepts or edits). The destination follows the
/// hold tree canon: Media/Photos/YYYY/MM, Media/Audio, Media/Video, Documents/YYYY.
class SortSuggestion {
  const SortSuggestion(this.entry, this.name, this.folder);
  final HoldEntry entry;
  final String name, folder;
}

SortSuggestion? suggestSort(HoldEntry e, {String root = 'sconl/Crate'}) {
  if (e.isFolder) return null;
  final d = e.modified;
  final yyyy = d == null ? 'undated' : '${d.year}';
  final mm = d == null ? '' : d.month.toString().padLeft(2, '0');
  final stamp = d == null ? '' : '${d.year}$mm${d.day.toString().padLeft(2, '0')}_';
  final base = RegExp(r'^\d{8}_').hasMatch(e.name) ? e.name : '$stamp${e.name}';
  final clean = base.replaceAll(RegExp(r'\s+'), '_').toLowerCase();
  switch (e.kind) {
    case 'image':
      return SortSuggestion(e, clean, '$root/Media/Photos/$yyyy${mm.isEmpty ? '' : '/$mm'}');
    case 'audio':
      return SortSuggestion(e, clean, '$root/Media/Audio');
    case 'video':
      return SortSuggestion(e, clean, '$root/Media/Video');
    case 'pdf':
    case 'office':
    case 'text':
      return SortSuggestion(e, clean, '$root/Documents/$yyyy');
    default:
      return null;
  }
}

class HttpHoldApi implements HoldApi {
  HttpHoldApi(this.api);
  final ApiClient api;

  String _q(Map<String, String> p) => p.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&');

  Future<Map<String, dynamic>> _post(String route, Map<String, dynamic> body) async {
    try {
      return fmt.m(await api.postJson('/api/hold/$route', body));
    } on ApiException catch (e) {
      throw HoldException(e.message, retryable: e.status == 0 || e.status >= 500);
    } on OfflineException {
      throw HoldException('Offline.', retryable: true);
    }
  }

  Future<Map<String, dynamic>> _get(String route, Map<String, String> p) async {
    try {
      return fmt.m(await api.getJson('/api/hold/$route?${_q(p)}'));
    } on ApiException catch (e) {
      throw HoldException(e.message, retryable: e.status == 0 || e.status >= 500);
    } on OfflineException {
      throw HoldException('Offline.', retryable: true);
    }
  }

  @override
  Future<HoldPage> list(String path, {HoldSort sort = HoldSort.name, bool descending = false, String? cursor, int limit = 100}) async {
    final r = await _get('list', {'path': path, 'limit': '$limit', 'sort': sort.name, 'dir': descending ? 'desc' : 'asc', 'cursor': ?cursor});
    final next = fmt.s(r['next']);
    return HoldPage([for (final m in fmt.lm(r['items'])) HoldEntry.from(m)], next: next.isEmpty ? null : next);
  }

  @override
  Future<List<HoldEntry>> recent({int limit = 50}) async =>
      [for (final m in fmt.lm((await _get('recent', {'limit': '$limit'}))['items'])) HoldEntry.from(m)];

  @override
  Future<List<HoldEntry>> search(String q, {int limit = 60}) async =>
      [for (final m in fmt.lm((await _get('search', {'q': q, 'limit': '$limit'}))['items'])) HoldEntry.from(m)];

  @override
  Future<Uint8List> read(String path, {int start = 0, int? length}) async {
    try {
      final r = await api.getBytes('/api/hold/read?${_q({'path': path, 'start': '$start', 'length': ?(length == null ? null : '$length')})}');
      return Uint8List.fromList(r.bytes);
    } on ApiException catch (e) {
      throw HoldException(e.message, retryable: e.status == 0 || e.status >= 500);
    } on OfflineException {
      throw HoldException('Offline.', retryable: true);
    }
  }

  @override
  Future<void> mkdir(String path) async => _post('mkdir', {'path': path});
  @override
  Future<void> rename(String path, String name) async => _post('rename', {'path': path, 'name': name});
  @override
  Future<void> move(String path, String to) async => _post('move', {'path': path, 'to': to});
  @override
  Future<void> copy(String path, String to) async => _post('copy', {'path': path, 'to': to});
  @override
  Future<void> delete(String path) async => _post('delete', {'path': path});
  @override
  Future<void> restore(String path) async => _post('restore', {'path': path});

  @override
  Future<HoldShare> share(String path, {int ttlHours = 24}) async {
    final r = await _post('share', {'path': path, 'ttl_hours': ttlHours});
    return HoldShare(fmt.s(r['url']), DateTime.fromMillisecondsSinceEpoch(fmt.i(r['expires']) * 1000));
  }

  @override
  Future<HoldUploadSession> beginUpload(String path, int size, String hash) async {
    final r = await _post('upload/begin', {'path': path, 'size': size, 'hash': hash});
    return HoldUploadSession(fmt.s(r['id']), fmt.i(r['offset']));
  }

  @override
  Future<int> sendChunk(String id, int offset, Uint8List data) async =>
      fmt.i((await _post('upload/chunk', {'id': id, 'offset': offset, 'data': base64Encode(data)}))['offset']);

  @override
  Future<HoldEntry> finishUpload(String id) async => HoldEntry.from(fmt.m((await _post('upload/finish', {'id': id}))['entry']));
}

/// An in-memory hold, for tests and for building the space before BH26102001 lands. [failNextChunks] makes the next n
/// chunk calls throw a retryable error, so resume is tested without a flaky network.
class FakeHoldApi implements HoldApi {
  FakeHoldApi({Map<String, Uint8List>? files, Iterable<String> folders = const ['sconl', 'acexoft']}) {
    for (final f in folders) {
      _folders.add(f);
    }
    files?.forEach((p, b) {
      _files[p] = b;
      _modified[p] = DateTime.now();
    });
  }

  final Map<String, Uint8List> _files = {};
  final Set<String> _folders = {};
  final Map<String, DateTime> _modified = {};
  final Set<String> _trash = {};
  final Map<String, ({String path, int size, BytesBuilder data})> _uploads = {};
  int failNextChunks = 0;
  int chunkCalls = 0;
  int _seq = 0;

  Uint8List? bytesOf(String path) => _files[path];
  bool exists(String path) => _files.containsKey(path) || _folders.contains(path);
  bool isTrashed(String path) => _trash.contains(path);

  String _parent(String p) => p.contains('/') ? p.substring(0, p.lastIndexOf('/')) : '';
  String _name(String p) => p.split('/').last;

  HoldEntry _entry(String path) {
    final isFolder = _folders.contains(path);
    return HoldEntry(
        path: path, name: _name(path), isFolder: isFolder, size: isFolder ? 0 : _files[path]!.length, modified: _modified[path], trashed: _trash.contains(path));
  }

  Iterable<String> get _all => [..._folders, ..._files.keys];

  @override
  Future<HoldPage> list(String path, {HoldSort sort = HoldSort.name, bool descending = false, String? cursor, int limit = 100}) async {
    if (path.isNotEmpty && !_folders.contains(path)) throw HoldException('No such folder: $path');
    final all = sortEntries([for (final p in _all) if (_parent(p) == path && !_trash.contains(p)) _entry(p)], sort, descending: descending);
    final start = int.tryParse(cursor ?? '') ?? 0;
    final end = (start + limit).clamp(0, all.length);
    return HoldPage(all.sublist(start, end), next: end < all.length ? '$end' : null);
  }

  @override
  Future<List<HoldEntry>> recent({int limit = 50}) async {
    final files = [for (final p in _files.keys) if (!_trash.contains(p)) _entry(p)]
      ..sort((a, b) => (b.modified ?? DateTime(0)).compareTo(a.modified ?? DateTime(0)));
    return files.take(limit).toList();
  }

  @override
  Future<List<HoldEntry>> search(String q, {int limit = 60}) async {
    final words = q.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    return [
      for (final p in _all)
        if (!_trash.contains(p) && words.every(_name(p).toLowerCase().contains)) _entry(p)
    ].take(limit).toList();
  }

  @override
  Future<Uint8List> read(String path, {int start = 0, int? length}) async {
    final b = _files[path];
    if (b == null) throw HoldException('Not found: $path');
    return Uint8List.sublistView(b, start.clamp(0, b.length), (length == null ? b.length : start + length).clamp(0, b.length));
  }

  @override
  Future<void> mkdir(String path) async {
    if (exists(path)) throw HoldException('"${_name(path)}" already exists here.');
    _folders.add(path);
    _modified[path] = DateTime.now();
  }

  @override
  Future<void> rename(String path, String name) => move(path, _parent(path).isEmpty ? name : '${_parent(path)}/$name');

  @override
  Future<void> move(String path, String to) async {
    final dest = _folders.contains(to) ? '$to/${_name(path)}' : to;
    if (!exists(path)) throw HoldException('Not found: $path');
    if (exists(dest)) throw HoldException('"${_name(dest)}" already exists there.');
    if (_files.containsKey(path)) {
      _files[dest] = _files.remove(path)!;
      _modified[dest] = DateTime.now();
      _modified.remove(path);
    } else {
      final moved = [for (final p in _all) if (p == path || p.startsWith('$path/')) p];
      for (final p in moved) {
        final np = dest + p.substring(path.length);
        if (_files.containsKey(p)) {
          _files[np] = _files.remove(p)!;
        } else {
          _folders.remove(p);
          _folders.add(np);
        }
      }
    }
  }

  @override
  Future<void> copy(String path, String to) async {
    final dest = _folders.contains(to) ? '$to/${_name(path)}' : to;
    if (!_files.containsKey(path)) throw HoldException('Only files can be copied here.');
    if (exists(dest)) throw HoldException('"${_name(dest)}" already exists there.');
    _files[dest] = Uint8List.fromList(_files[path]!);
    _modified[dest] = DateTime.now();
  }

  @override
  Future<void> delete(String path) async {
    if (!exists(path)) throw HoldException('Not found: $path');
    _trash.add(path);
  }

  @override
  Future<void> restore(String path) async {
    if (!_trash.remove(path)) throw HoldException('"${_name(path)}" is not in the trash.');
  }

  @override
  Future<HoldShare> share(String path, {int ttlHours = 24}) async {
    if (!exists(path)) throw HoldException('Not found: $path');
    return HoldShare('https://hold.test/s/${path.hashCode.abs()}', DateTime.now().add(Duration(hours: ttlHours)));
  }

  @override
  Future<HoldUploadSession> beginUpload(String path, int size, String hash) async {
    if (!_folders.contains(_parent(path)) && _parent(path).isNotEmpty) throw HoldException('No such folder: ${_parent(path)}');
    // A second begin for the same path and size resumes the first.
    for (final e in _uploads.entries) {
      if (e.value.path == path) return HoldUploadSession(e.key, e.value.data.length);
    }
    final id = 'u${++_seq}';
    _uploads[id] = (path: path, size: size, data: BytesBuilder());
    return HoldUploadSession(id, 0);
  }

  @override
  Future<int> sendChunk(String id, int offset, Uint8List data) async {
    chunkCalls++;
    if (failNextChunks > 0) {
      failNextChunks--;
      throw HoldException('The connection dropped.', retryable: true);
    }
    final u = _uploads[id];
    if (u == null) throw HoldException('Unknown upload.');
    if (offset != u.data.length) return u.data.length; // the server's offset wins; the client resumes from it
    u.data.add(data);
    return u.data.length;
  }

  @override
  Future<HoldEntry> finishUpload(String id) async {
    final u = _uploads.remove(id);
    if (u == null) throw HoldException('Unknown upload.');
    if (u.data.length != u.size) throw HoldException('The upload is incomplete.', retryable: true);
    _files[u.path] = u.data.toBytes();
    _modified[u.path] = DateTime.now();
    return _entry(u.path);
  }
}
