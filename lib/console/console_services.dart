/// BI26092648: the Console card's player, recorder and mode, built once per app.
///
/// They have to outlive the card: the card leaves the tree when the Command tab
/// does, and playback or a recording must carry on. So they hang off the app's
/// services rather than the widget, and are created on first use, which keeps a
/// plain launch (and every test that never opens Player or Recorder) off the
/// audio and microphone plugins.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../app_scope.dart';
import '../data/audio_library.dart';
import '../data/db.dart';
import 'audio_backends.dart';
import 'console_mode.dart';
import 'console_player.dart';
import 'console_recorder.dart';

/// The snapshot table as a small key/value store.
class SnapshotKeyValue implements ConsoleKeyValue {
  SnapshotKeyValue(this._db);
  final AppDb _db;

  @override
  Future<String?> read(String key) async {
    final s = await _db.getSnapshot(key);
    final v = s?.$1;
    return v is String ? v : null;
  }

  @override
  Future<void> write(String key, String value) => _db.putSnapshot(key, value);
}

class ConsoleServices {
  ConsoleServices._(this.mode, this.player, this.recorder, this.store);

  @visibleForTesting
  factory ConsoleServices.forTesting({
    required ConsoleModeController mode,
    required ConsolePlayer player,
    required ConsoleRecorder recorder,
    required ConsoleKeyValue store,
  }) =>
      ConsoleServices._(mode, player, recorder, store);

  final ConsoleModeController mode;
  final ConsolePlayer player;
  final ConsoleRecorder recorder;
  final ConsoleKeyValue store;

  /// The library source and its offline cache, set when built by [of].
  LibraryPlayback? get library => _libraryOf[this];
  static final Expando<LibraryPlayback> _libraryOf = Expando<LibraryPlayback>('LibraryPlayback');

  static final Expando<ConsoleServices> _byApp = Expando<ConsoleServices>('ConsoleServices');

  static ConsoleServices of(AppServices services) {
    final existing = _byApp[services];
    if (existing != null) return existing;
    final store = SnapshotKeyValue(services.db);
    final player = ConsolePlayer(JustAudioBackend.new, store);
    final library = LibraryPlayback(MediaEngineSource(services.api), store);
    player.resolver = library.resolve;
    final recorder = ConsoleRecorder(
      makeBackend: RecordBackend.new,
      newFilePath: (id) async {
        final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'recordings'));
        if (!await dir.exists()) await dir.create(recursive: true);
        return p.join(dir.path, '$id.m4a');
      },
      readBytes: (path) async => Uint8List.fromList(await File(path).readAsBytes()),
      deleteFile: (path) async {
        final f = File(path);
        if (await f.exists()) await f.delete();
      },
      enqueue: services.outbox.enqueue,
      store: store,
    );
    final created = ConsoleServices._(ConsoleModeController(store), player, recorder, store);
    _byApp[services] = created;
    _libraryOf[created] = library;
    return created;
  }

  /// Restores the remembered mode and queue; safe to call more than once.
  Future<void> restore() async {
    await mode.restore();
    await player.restore();
  }

  /// Authorization headers for a hub audio URL.
  static Map<String, String>? bearer(String token) => token.isEmpty ? null : {'Authorization': 'Bearer $token'};

  /// Decodes a stored JSON list defensively (used by tests of the snapshot store).
  static List<dynamic> decodeList(String? raw) {
    if (raw == null) return const [];
    try {
      final j = jsonDecode(raw);
      return j is List ? j : const [];
    } on FormatException {
      return const [];
    }
  }
}


/// BI26101807: resolves library tracks to something playable and keeps what was played on the phone, up to 200 MB,
/// least recently played dropped first. The first play streams; the download runs beside it, so the next play of the
/// same file opens the cached copy and works offline.
class LibraryPlayback {
  LibraryPlayback(this.source, this._store);
  final AudioLibrarySource source;
  final ConsoleKeyValue _store;
  static const _key = 'console.audiocache';
  AudioCacheIndex? _index;
  final Set<String> _downloading = {};

  Future<AudioCacheIndex> _idx() async {
    if (_index != null) return _index!;
    try {
      final raw = await _store.read(_key);
      _index = AudioCacheIndex.fromJson(raw == null ? null : jsonDecode(raw));
    } catch (_) {
      _index = AudioCacheIndex();
    }
    return _index!;
  }

  // FNV-1a: String.hashCode is not promised to survive a restart, and the cache must find its files again.
  static String _stableHash(String v) {
    var h = 0x811c9dc5;
    for (final c in v.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xffffffff;
    }
    return h.toRadixString(16);
  }

  Future<File> _fileFor(String path) async {
    final dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'audio-cache'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return File(p.join(dir.path, '${_stableHash(path)}${p.extension(path)}'));
  }

  Future<ConsoleTrack> resolve(ConsoleTrack t) async {
    if (!t.uri.startsWith(mediaUriPrefix)) return t;
    final path = t.uri.substring(mediaUriPrefix.length);
    final idx = await _idx();
    final f = await _fileFor(path);
    if (idx.has(path) && await f.exists()) {
      idx.touch(path, await f.length());
      await _save();
      return ConsoleTrack(id: t.id, title: t.title, uri: f.path, isFile: true);
    }
    final s = await source.streamFor(path);
    if (_downloading.add(path)) _cache(path, s.url, f);
    return ConsoleTrack(id: t.id, title: t.title, uri: s.url, headers: s.headers);
  }

  Future<void> _cache(String path, String url, File f) async {
    try {
      final res = await http.Client().send(http.Request('GET', Uri.parse(url)));
      if (res.statusCode != 200) return;
      final sink = f.openWrite();
      await res.stream.pipe(sink);
      final idx = await _idx();
      for (final gone in idx.touch(path, await f.length())) {
        final g = await _fileFor(gone);
        if (await g.exists()) await g.delete();
      }
      await _save();
    } catch (_) {
      // A failed cache fill only means the next play streams again.
      if (await f.exists()) await f.delete();
    } finally {
      _downloading.remove(path);
    }
  }

  Future<void> _save() async {
    try {
      await _store.write(_key, jsonEncode((await _idx()).toJson()));
    } catch (_) {}
  }
}
