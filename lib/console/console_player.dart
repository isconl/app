/// BI26092648: the Console card's Player mode.
///
/// A small queue player. The ring shows the timeline, the centre plays and
/// pauses, and what was playing is remembered so the next launch continues
/// where it left off. The audio engine sits behind [AudioBackend] so the logic
/// here is tested without a device; `just_audio` is the real one
/// (`audio_backends.dart`).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'console_mode.dart';
import 'ring_math.dart';

/// One thing in the queue. [uri] is a URL or, when [isFile], a local path.
class ConsoleTrack {
  const ConsoleTrack({required this.id, required this.title, required this.uri, this.isFile = false, this.headers});

  final String id;
  final String title;
  final String uri;
  final bool isFile;
  final Map<String, String>? headers;

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'uri': uri, 'isFile': isFile};

  /// Request headers are never persisted: a bearer token does not belong in a snapshot.
  static ConsoleTrack? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], title = j['title'], uri = j['uri'];
    if (id is! String || title is! String || uri is! String) return null;
    return ConsoleTrack(id: id, title: title, uri: uri, isFile: j['isFile'] == true);
  }
}

/// The audio engine, reduced to what the card needs.
abstract class AudioBackend {
  Stream<Duration> get positionStream;
  Stream<Duration?> get durationStream;
  Stream<bool> get playingStream;
  Stream<void> get completedStream;

  /// Loads a track, returning its length when known.
  Future<Duration?> load(ConsoleTrack track);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setSpeed(double speed);
  Future<void> dispose();
}

class ConsolePlayer extends ChangeNotifier {
  ConsolePlayer(this._makeBackend, this._store);

  final AudioBackend Function() _makeBackend;
  final ConsoleKeyValue _store;

  static const speeds = <double>[1.0, 1.25, 1.5, 2.0];
  static const skipBack = Duration(seconds: 15);
  static const skipForward = Duration(seconds: 30);
  static const _key = 'console.player';

  AudioBackend? _backend;
  final List<StreamSubscription<dynamic>> _subs = [];

  final List<ConsoleTrack> queue = [];
  int index = -1;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  bool playing = false;
  bool loading = false;
  double speed = 1.0;
  String? error;

  ConsoleTrack? get current => index >= 0 && index < queue.length ? queue[index] : null;
  double get fraction => fractionOfPosition(position, duration);
  bool get hasTrack => current != null;

  // ---- queue ----

  Future<void> addToQueue(ConsoleTrack t, {bool playNow = false}) async {
    final existing = queue.indexWhere((q) => q.id == t.id);
    if (existing >= 0) {
      if (playNow) await playAt(existing);
      return;
    }
    queue.add(t);
    notifyListeners();
    if (playNow || index < 0) await playAt(queue.length - 1, autoplay: playNow);
    await _persist();
  }

  Future<void> removeAt(int i) async {
    if (i < 0 || i >= queue.length) return;
    final wasCurrent = i == index;
    queue.removeAt(i);
    if (queue.isEmpty) {
      index = -1;
      await _stopBackend();
    } else if (wasCurrent) {
      index = i.clamp(0, queue.length - 1);
      await playAt(index, autoplay: playing);
    } else if (i < index) {
      index--;
    }
    notifyListeners();
    await _persist();
  }

  /// Moves a queue item to its final position (the index it will have afterwards,
  /// which is what `ReorderableListView.onReorderItem` reports).
  Future<void> reorder(int from, int to) async {
    if (from < 0 || from >= queue.length) return;
    final target = to.clamp(0, queue.length - 1);
    final playingId = current?.id;
    final item = queue.removeAt(from);
    queue.insert(target, item);
    if (playingId != null) index = queue.indexWhere((q) => q.id == playingId);
    notifyListeners();
    await _persist();
  }

  // ---- transport ----

  Future<void> playAt(int i, {bool autoplay = true}) async {
    if (i < 0 || i >= queue.length) return;
    index = i;
    position = Duration.zero;
    duration = Duration.zero;
    error = null;
    loading = true;
    notifyListeners();
    final b = _ensureBackend();
    try {
      final d = await b.load(queue[i]);
      duration = d ?? Duration.zero;
      await b.setSpeed(speed);
      if (autoplay) {
        await b.play();
      }
    } catch (e) {
      error = 'Could not play ${queue[i].title}.';
      playing = false;
    }
    loading = false;
    notifyListeners();
    await _persist();
  }

  Future<void> togglePlay() async {
    final b = _backend;
    if (current == null) return;
    if (b == null) {
      // Nothing is loaded yet (a fresh launch with a restored queue): open the
      // saved track at its saved position, then play.
      await _resumeLoaded();
      await _backend?.play();
      return;
    }
    if (playing) {
      await b.pause();
    } else {
      await b.play();
    }
  }

  Future<void> skipBackward() => seekTo(position - skipBack);

  Future<void> skipForwardNow() => seekTo(position + skipForward);

  Future<void> seekTo(Duration p) async {
    final b = _backend;
    if (b == null || duration <= Duration.zero) return;
    final clamped = p < Duration.zero ? Duration.zero : (p > duration ? duration : p);
    position = clamped;
    notifyListeners();
    await b.seek(clamped);
  }

  /// A drag on the ring: a 0 to 1 fraction of the track.
  Future<void> seekFraction(double f) => seekTo(positionForFraction(f, duration));

  /// Cycles 1x, 1.25x, 1.5x, 2x.
  Future<void> cycleSpeed() async {
    final i = speeds.indexOf(speed);
    speed = speeds[(i + 1) % speeds.length];
    notifyListeners();
    await _backend?.setSpeed(speed);
    await _persist();
  }

  Future<void> next() async {
    if (index + 1 < queue.length) await playAt(index + 1);
  }

  // ---- remembering ----

  /// Brings back the queue and where it was, paused: a launch must not start sound.
  Future<void> restore() async {
    final raw = await _store.read(_key);
    if (raw == null) return;
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return;
      speed = (j['speed'] is num && speeds.contains((j['speed'] as num).toDouble())) ? (j['speed'] as num).toDouble() : 1.0;
      queue
        ..clear()
        ..addAll([
          for (final t in (j['queue'] is List ? j['queue'] as List : const []))
            if (ConsoleTrack.fromJson(t) case final ConsoleTrack ct) ct
        ]);
      final i = j['index'] is int ? j['index'] as int : -1;
      index = i >= 0 && i < queue.length ? i : (queue.isEmpty ? -1 : 0);
      position = Duration(milliseconds: j['positionMs'] is int ? j['positionMs'] as int : 0);
      notifyListeners();
    } on FormatException {
      // A damaged snapshot is not worth failing the card over.
    }
  }

  /// Opens the restored track at its saved position, paused, the first time play is pressed.
  Future<void> _resumeLoaded() async {
    final start = position;
    await playAt(index, autoplay: false);
    if (start > Duration.zero && duration > start) await seekTo(start);
  }

  Future<void> _persist() => _store.write(
      _key,
      jsonEncode({
        'queue': [for (final t in queue) t.toJson()],
        'index': index,
        'positionMs': position.inMilliseconds,
        'speed': speed,
      }));

  /// Saves where playback is; called on pause and when the card goes away.
  Future<void> savePosition() => _persist();

  // ---- backend wiring ----

  AudioBackend _ensureBackend() {
    final existing = _backend;
    if (existing != null) return existing;
    final b = _makeBackend();
    _backend = b;
    _subs
      ..add(b.positionStream.listen((p) {
        position = p;
        notifyListeners();
      }))
      ..add(b.durationStream.listen((d) {
        if (d != null) duration = d;
        notifyListeners();
      }))
      ..add(b.playingStream.listen((v) {
        final was = playing;
        playing = v;
        notifyListeners();
        if (was && !v) unawaited(_persist());
      }))
      ..add(b.completedStream.listen((_) {
        unawaited(next());
      }));
    return b;
  }

  Future<void> _stopBackend() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await _backend?.dispose();
    _backend = null;
    playing = false;
    position = Duration.zero;
    duration = Duration.zero;
  }

  @override
  void dispose() {
    unawaited(_stopBackend());
    super.dispose();
  }
}
