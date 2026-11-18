/// BI26092648: the Console card's Recorder mode.
///
/// Records to a file on the device first, so nothing depends on a connection, and
/// only then queues the file for upload in chunks through the outbox, which
/// delivers them whenever the phone is online. The microphone sits behind
/// [RecorderBackend] so this logic is tested without one; the `record` package is
/// the real one (`audio_backends.dart`).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'console_mode.dart';
import 'ring_math.dart';

abstract class RecorderBackend {
  /// Asks for the microphone if needed; true when recording is allowed.
  Future<bool> ensurePermission();
  Future<void> start(String path);
  Future<void> pause();
  Future<void> resume();

  /// Stops and returns the finished file's path, or null if nothing was written.
  Future<String?> stop();

  /// Input level, 0 (silence) to 1 (loud), while recording.
  Stream<double> get levelStream;
  Future<void> dispose();
}

enum RecorderState { idle, recording, paused, review }

/// The outbox's enqueue, as a function, so a test can stand in for it.
typedef EnqueueUpload = Future<void> Function({
  required String path,
  required Map<String, dynamic> body,
  required String label,
  required String view,
});

class SavedRecording {
  const SavedRecording({required this.id, required this.title, required this.path, required this.durationMs, required this.createdAt, this.chunks = 0});
  final String id;
  final String title;
  final String path;
  final int durationMs;
  final int createdAt;

  /// How many upload parts were queued for it.
  final int chunks;

  Map<String, dynamic> toJson() =>
      {'id': id, 'title': title, 'path': path, 'durationMs': durationMs, 'createdAt': createdAt, 'chunks': chunks};

  static SavedRecording? fromJson(Object? j) {
    if (j is! Map) return null;
    if (j['id'] is! String || j['path'] is! String) return null;
    return SavedRecording(
      id: j['id'] as String,
      title: j['title'] is String ? j['title'] as String : 'Recording',
      path: j['path'] as String,
      durationMs: j['durationMs'] is int ? j['durationMs'] as int : 0,
      createdAt: j['createdAt'] is int ? j['createdAt'] as int : 0,
      chunks: j['chunks'] is int ? j['chunks'] as int : 0,
    );
  }
}

class ConsoleRecorder extends ChangeNotifier {
  ConsoleRecorder({
    required this.makeBackend,
    required this.newFilePath,
    required this.readBytes,
    required this.deleteFile,
    required this.enqueue,
    required this.store,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final RecorderBackend Function() makeBackend;
  final Future<String> Function(String id) newFilePath;
  final Future<Uint8List> Function(String path) readBytes;
  final Future<void> Function(String path) deleteFile;
  final EnqueueUpload enqueue;
  final ConsoleKeyValue store;
  final DateTime Function() _now;

  /// Raw bytes per upload part. Base64 inflates it by a third, so a part is about 256 KB on the wire.
  static const chunkBytes = 192 * 1024;
  static const uploadPath = '/api/console/recordings/chunk';
  static const _recordingsKey = 'console.recordings';

  RecorderBackend? _backend;
  StreamSubscription<double>? _levelSub;
  Timer? _ticker;

  RecorderState state = RecorderState.idle;
  double level = 0;
  String? error;

  /// The finished take, held between Stop and Keep or Discard.
  String? _takePath;
  String? _takeId;
  Duration _takeLength = Duration.zero;

  /// Set when a suggestion for the title arrives; the card offers it as the default.
  String? suggestedTitle;

  /// What the card shows under the ring after Keep: where the take is.
  String? status;

  DateTime? _runStart;
  Duration _banked = Duration.zero;

  Duration get elapsed => state == RecorderState.recording && _runStart != null ? _banked + _now().difference(_runStart!) : _banked;
  int get laps => lapCount(elapsed);
  double get lap => lapFraction(elapsed);
  bool get hasTake => _takePath != null;

  // ---- recording ----

  /// Starts a take. Returns false, with [error] set, when the microphone is refused.
  Future<bool> start() async {
    if (state != RecorderState.idle) return false;
    error = null;
    status = null;
    final b = makeBackend();
    if (!await b.ensurePermission()) {
      await b.dispose();
      error = 'The microphone is off for iSconl. Turn it on in Android settings to record.';
      notifyListeners();
      return false;
    }
    _backend = b;
    final id = 'rec-${_now().millisecondsSinceEpoch}';
    final path = await newFilePath(id);
    try {
      await b.start(path);
    } catch (e) {
      error = 'Could not start recording.';
      await _release();
      notifyListeners();
      return false;
    }
    _takeId = id;
    _takePath = path;
    _banked = Duration.zero;
    _runStart = _now();
    suggestedTitle = null;
    state = RecorderState.recording;
    _levelSub = b.levelStream.listen((v) {
      level = v.clamp(0.0, 1.0);
      notifyListeners();
    });
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => tick());
    notifyListeners();
    return true;
  }

  /// The centre control: record when idle, stop when recording or paused.
  Future<void> toggleRecord() async {
    switch (state) {
      case RecorderState.idle:
        await start();
      case RecorderState.recording:
      case RecorderState.paused:
        await stop();
      case RecorderState.review:
        break;
    }
  }

  /// Long-press on the centre.
  Future<void> togglePause() async {
    final b = _backend;
    if (b == null) return;
    if (state == RecorderState.recording) {
      _banked = elapsed;
      _runStart = null;
      state = RecorderState.paused;
      level = 0;
      await b.pause();
    } else if (state == RecorderState.paused) {
      _runStart = _now();
      state = RecorderState.recording;
      await b.resume();
    }
    notifyListeners();
  }

  Future<void> stop() async {
    final b = _backend;
    if (b == null || state == RecorderState.idle || state == RecorderState.review) return;
    _takeLength = elapsed;
    _banked = _takeLength;
    _runStart = null;
    _ticker?.cancel();
    _ticker = null;
    level = 0;
    final path = await b.stop();
    // Take the microphone away synchronously, publish the new state, and only then
    // wait for the plugin to let go: the card should not sit on "recording" while
    // a platform channel finishes closing.
    final released = _release();
    if (path == null) {
      error = 'Nothing was recorded.';
      _takePath = null;
      state = RecorderState.idle;
    } else {
      _takePath = path;
      state = RecorderState.review;
    }
    notifyListeners();
    await released;
  }

  void tick() {
    if (state == RecorderState.recording) notifyListeners();
  }

  // ---- keep or discard ----

  /// Saves the take under [title] and queues it for upload. The file stays on the
  /// device either way; the queue only decides when it reaches the server.
  Future<SavedRecording?> keep(String title) async {
    final path = _takePath, id = _takeId;
    if (state != RecorderState.review || path == null || id == null) return null;
    final name = title.trim().isEmpty ? (suggestedTitle ?? 'Recording ${_now().toIso8601String().substring(0, 16).replaceFirst('T', ' ')}') : title.trim();
    final bytes = await readBytes(path);
    final total = bytes.isEmpty ? 0 : (bytes.length + chunkBytes - 1) ~/ chunkBytes;
    for (var i = 0; i < total; i++) {
      final from = i * chunkBytes;
      final to = (from + chunkBytes) > bytes.length ? bytes.length : from + chunkBytes;
      await enqueue(
        path: uploadPath,
        body: {
          'id': id,
          'index': i,
          'total': total,
          'title': name,
          'durationMs': _takeLength.inMilliseconds,
          'bytes': bytes.length,
          'mime': 'audio/mp4',
          'data': base64Encode(bytes.sublist(from, to)),
        },
        label: 'Recording "$name" ${i + 1}/$total',
        view: 'console',
      );
    }
    final saved = SavedRecording(
        id: id, title: name, path: path, durationMs: _takeLength.inMilliseconds, createdAt: _now().millisecondsSinceEpoch, chunks: total);
    await _remember(saved);
    status = total == 0 ? 'Saved on this device' : 'Saved on this device, $total ${total == 1 ? 'part' : 'parts'} queued to upload';
    _clearTake();
    state = RecorderState.idle;
    notifyListeners();
    return saved;
  }

  Future<void> discard() async {
    final path = _takePath;
    if (state == RecorderState.recording || state == RecorderState.paused) await stop();
    final p = _takePath ?? path;
    if (p != null) {
      try {
        await deleteFile(p);
      } catch (_) {/* a leftover temp file is not worth an error */}
    }
    _clearTake();
    status = null;
    state = RecorderState.idle;
    notifyListeners();
  }

  void applySuggestion(String title) {
    suggestedTitle = title;
    notifyListeners();
  }

  // ---- the local list ----

  Future<List<SavedRecording>> recordings() async {
    final raw = await store.read(_recordingsKey);
    if (raw == null) return const [];
    try {
      final j = jsonDecode(raw);
      if (j is! List) return const [];
      return [
        for (final e in j)
          if (SavedRecording.fromJson(e) case final SavedRecording r) r
      ];
    } on FormatException {
      return const [];
    }
  }

  Future<void> _remember(SavedRecording r) async {
    final all = [r, ...(await recordings()).where((e) => e.id != r.id)];
    await store.write(_recordingsKey, jsonEncode([for (final e in all.take(50)) e.toJson()]));
  }

  // ---- housekeeping ----

  void _clearTake() {
    _takePath = null;
    _takeId = null;
    _takeLength = Duration.zero;
    _banked = Duration.zero;
    _runStart = null;
    suggestedTitle = null;
  }

  Future<void> _release() async {
    // Everything is detached before the first await, so a new take started while
    // this one is still closing gets its own backend and subscription untouched.
    final sub = _levelSub;
    final backend = _backend;
    _levelSub = null;
    _backend = null;
    _ticker?.cancel();
    _ticker = null;
    await sub?.cancel();
    await backend?.dispose();
  }

  @override
  void dispose() {
    unawaited(_release());
    super.dispose();
  }
}
