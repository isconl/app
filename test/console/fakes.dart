import 'dart:async';
import 'dart:typed_data';

import 'package:isconl/console/console_mode.dart';
import 'package:isconl/console/console_player.dart';
import 'package:isconl/console/console_recorder.dart';

class MemoryKv implements ConsoleKeyValue {
  final Map<String, String> data = {};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
}

class FakeAudio implements AudioBackend {
  final pos = StreamController<Duration>.broadcast();
  final dur = StreamController<Duration?>.broadcast();
  final playingC = StreamController<bool>.broadcast();
  final done = StreamController<void>.broadcast();

  Duration length = const Duration(minutes: 10);
  final List<String> loaded = [];
  final List<Duration> seeks = [];
  double speed = 1;
  bool isPlaying = false;
  bool disposed = false;
  bool failLoad = false;

  @override
  Stream<Duration> get positionStream => pos.stream;
  @override
  Stream<Duration?> get durationStream => dur.stream;
  @override
  Stream<bool> get playingStream => playingC.stream;
  @override
  Stream<void> get completedStream => done.stream;

  @override
  Future<Duration?> load(ConsoleTrack track) async {
    if (failLoad) throw StateError('no network');
    loaded.add(track.id);
    return length;
  }

  @override
  Future<void> play() async {
    isPlaying = true;
    playingC.add(true);
  }

  @override
  Future<void> pause() async {
    isPlaying = false;
    playingC.add(false);
  }

  @override
  Future<void> seek(Duration position) async => seeks.add(position);

  @override
  Future<void> setSpeed(double s) async => speed = s;

  @override
  Future<void> dispose() async => disposed = true;
}

class FakeMic implements RecorderBackend {
  bool allowed = true;
  bool started = false, paused = false, stopped = false, disposed = false;
  String? path;
  String? stopResult = 'FROM_START';
  final level = StreamController<double>.broadcast();

  @override
  Future<bool> ensurePermission() async => allowed;
  @override
  Future<void> start(String p) async {
    started = true;
    path = p;
  }

  @override
  Future<void> pause() async => paused = true;
  @override
  Future<void> resume() async => paused = false;
  @override
  Future<String?> stop() async {
    stopped = true;
    return stopResult == 'FROM_START' ? path : stopResult;
  }

  @override
  Stream<double> get levelStream => level.stream;
  @override
  Future<void> dispose() async => disposed = true;
}

class Clock {
  DateTime t = DateTime(2026, 10, 3, 9);
  DateTime now() => t;
  void advance(Duration d) => t = t.add(d);
}

typedef Upload = ({String path, Map<String, dynamic> body, String label, String view});

ConsoleRecorder makeRecorder({
  required FakeMic mic,
  required Clock clock,
  required MemoryKv kv,
  required List<Upload> uploads,
  Uint8List? bytes,
  List<String>? deleted,
}) =>
    ConsoleRecorder(
      makeBackend: () => mic,
      newFilePath: (id) async => '/tmp/$id.m4a',
      readBytes: (_) async => bytes ?? Uint8List(0),
      deleteFile: (p) async => deleted?.add(p),
      enqueue: ({required path, required body, required label, required view}) async =>
          uploads.add((path: path, body: body, label: label, view: view)),
      store: kv,
      now: clock.now,
    );
