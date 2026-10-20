/// BI26101807: the console player's library. Three folders (Music, Recordings, Voice notes) read through one source
/// interface. Today the source is the media engine (media.local.list and media.local.ticket, interim decision of
/// 20 Oct 2026); when hold's file API lands (BH26102001) a hold source replaces it and nothing above this file changes.
///
/// A track's uri is stable ("media: plus the path") and is turned into a short-lived streaming url only when it is about to
/// play, so a track queued for an hour never carries an expired ticket.
library;

import '../api/client.dart';
import '../util/fmt.dart' as fmt;

enum LibraryFolderKind { music, recordings, voiceNotes }

class LibraryFolder {
  const LibraryFolder(this.kind, this.label, this.path);
  final LibraryFolderKind kind;
  final String label, path;
}

class LibraryTrack {
  const LibraryTrack({required this.path, required this.title, required this.bytes, this.modified});
  final String path, title;
  final int bytes;
  final DateTime? modified;

  String get id => 'library:$path';
  String get uri => '$mediaUriPrefix$path';
}

const mediaUriPrefix = 'media:';

/// The three folders under [root] (audio-music, audio-recordings, audio-voice-notes, per the hold folder tree canon).
List<LibraryFolder> libraryFolders({String root = 'Audio'}) => [
      LibraryFolder(LibraryFolderKind.music, 'Music', '$root/audio-music'),
      LibraryFolder(LibraryFolderKind.recordings, 'Recordings', '$root/audio-recordings'),
      LibraryFolder(LibraryFolderKind.voiceNotes, 'Voice notes', '$root/audio-voice-notes'),
    ];

/// Recordings and voice notes newest first; music by title.
List<LibraryTrack> orderTracks(LibraryFolderKind kind, List<LibraryTrack> tracks) {
  final out = [...tracks];
  if (kind == LibraryFolderKind.music) {
    out.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  } else {
    out.sort((a, b) => (b.modified ?? DateTime(0)).compareTo(a.modified ?? DateTime(0)));
  }
  return out;
}

String _titleOf(String name) {
  final dot = name.lastIndexOf('.');
  final stem = dot <= 0 ? name : name.substring(0, dot);
  return stem.replaceAll('_', ' ').trim();
}

/// Parses one media.local.list answer into folders to descend into and playable files.
({List<String> dirs, List<LibraryTrack> files}) parseListing(dynamic json) {
  final entries = fmt.lm(fmt.m(json)['entries']);
  final dirs = <String>[];
  final files = <LibraryTrack>[];
  for (final e in entries) {
    final type = fmt.s(e['type']);
    final path = fmt.s(e['path']);
    if (type == 'dir') {
      dirs.add(path);
    } else if (fmt.b(e['playable']) && !fmt.b(e['image'])) {
      final iso = fmt.s(e['mtimeIso']);
      files.add(LibraryTrack(path: path, title: _titleOf(fmt.s(e['name'])), bytes: fmt.i(e['bytes']), modified: DateTime.tryParse(iso)));
    }
  }
  return (dirs: dirs, files: files);
}

abstract class AudioLibrarySource {
  /// Every playable file in [folder], one level of year sub-folders included, ordered for its kind.
  Future<List<LibraryTrack>> files(LibraryFolder folder);

  /// A url the audio backend can stream right now, plus the headers it needs.
  Future<({String url, Map<String, String>? headers})> streamFor(String path);
}

class MediaEngineSource implements AudioLibrarySource {
  MediaEngineSource(this.api);
  final ApiClient api;
  String? _base;

  Future<dynamic> _list(String path) => api.getJson('/api/media/list?path=${Uri.encodeQueryComponent(path)}');

  @override
  Future<List<LibraryTrack>> files(LibraryFolder folder) async {
    final top = parseListing(await _list(folder.path));
    final all = [...top.files];
    for (final d in top.dirs.take(40)) {
      // audio-recordings/{yyyy}: one level down is enough.
      all.addAll(parseListing(await _list(d)).files);
    }
    return orderTracks(folder.kind, all);
  }

  @override
  Future<({String url, Map<String, String>? headers})> streamFor(String path) async {
    _base ??= fmt.s(fmt.m(await api.getJson('/api/media/base-url'))['url']);
    if (_base!.isEmpty) throw ApiException(0, 'The media engine is not configured.');
    final t = fmt.s(fmt.m(await api.getJson('/api/media/ticket?path=${Uri.encodeQueryComponent(path)}'))['ticket']);
    final base = _base!.endsWith('/') ? _base!.substring(0, _base!.length - 1) : _base!;
    return (url: '$base/stream?t=${Uri.encodeQueryComponent(t)}', headers: null);
  }
}

/// A scripted source for tests.
class FakeLibrarySource implements AudioLibrarySource {
  FakeLibrarySource(this.byFolder);
  final Map<String, List<LibraryTrack>> byFolder;
  int tickets = 0;

  @override
  Future<List<LibraryTrack>> files(LibraryFolder folder) async => orderTracks(folder.kind, byFolder[folder.path] ?? const []);

  @override
  Future<({String url, Map<String, String>? headers})> streamFor(String path) async => (url: 'http://media.test/stream?t=${++tickets}', headers: null);
}

/// The offline cache's bookkeeping: a played file stays on the phone up to [capBytes]; past it, the least recently
/// played files go first. Pure (no file access): [touch] says which paths to delete, the caller deletes them.
class AudioCacheIndex {
  AudioCacheIndex({this.capBytes = 200 * 1024 * 1024});
  final int capBytes;
  final Map<String, ({int bytes, int played})> _entries = {};
  int _clock = 0;

  int get totalBytes => _entries.values.fold(0, (a, e) => a + e.bytes);
  bool has(String key) => _entries.containsKey(key);
  List<String> get keys => _entries.keys.toList();

  /// Records [key] as just played (adding it if new) and returns the keys to delete to stay under the cap. The file
  /// just played is never among them, even when it alone is over the cap.
  List<String> touch(String key, int bytes) {
    _entries[key] = (bytes: bytes, played: ++_clock);
    final drop = <String>[];
    final byAge = _entries.entries.where((e) => e.key != key).toList()..sort((a, b) => a.value.played.compareTo(b.value.played));
    var total = totalBytes;
    for (final e in byAge) {
      if (total <= capBytes) break;
      drop.add(e.key);
      total -= e.value.bytes;
    }
    for (final k in drop) {
      _entries.remove(k);
    }
    return drop;
  }

  void remove(String key) => _entries.remove(key);

  Map<String, dynamic> toJson() => {for (final e in _entries.entries) e.key: [e.value.bytes, e.value.played]};

  static AudioCacheIndex fromJson(Object? j, {int capBytes = 200 * 1024 * 1024}) {
    final idx = AudioCacheIndex(capBytes: capBytes);
    if (j is Map) {
      j.forEach((k, v) {
        if (v is List && v.length == 2 && v[0] is int && v[1] is int) {
          idx._entries['$k'] = (bytes: v[0] as int, played: v[1] as int);
          if ((v[1] as int) > idx._clock) idx._clock = v[1] as int;
        }
      });
    }
    return idx;
  }
}
