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
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../app_scope.dart';
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

  static final Expando<ConsoleServices> _byApp = Expando<ConsoleServices>('ConsoleServices');

  static ConsoleServices of(AppServices services) {
    final existing = _byApp[services];
    if (existing != null) return existing;
    final store = SnapshotKeyValue(services.db);
    final player = ConsolePlayer(JustAudioBackend.new, store);
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
