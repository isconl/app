/// BI26092648: the real audio engine and microphone behind the Console card.
///
/// Kept apart from the logic so tests never load a platform plugin: nothing in
/// `console_player.dart` or `console_recorder.dart` imports this file.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';

import 'console_player.dart';
import 'console_recorder.dart';

class JustAudioBackend implements AudioBackend {
  JustAudioBackend() : _player = AudioPlayer();
  final AudioPlayer _player;

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Stream<Duration?> get durationStream => _player.durationStream;

  @override
  Stream<bool> get playingStream => _player.playingStream;

  @override
  Stream<void> get completedStream =>
      _player.processingStateStream.where((s) => s == ProcessingState.completed);

  @override
  Future<Duration?> load(ConsoleTrack track) => _player.setAudioSource(
        track.isFile
            ? AudioSource.file(track.uri)
            // The route is Bearer-gated, so the header travels with the media
            // request rather than the token sitting in a URL where it would be logged.
            : AudioSource.uri(Uri.parse(track.uri), headers: track.headers),
      );

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Future<void> dispose() => _player.dispose();
}

class RecordBackend implements RecorderBackend {
  final AudioRecorder _rec = AudioRecorder();

  @override
  Future<bool> ensurePermission() => _rec.hasPermission();

  @override
  Future<void> start(String path) =>
      _rec.start(const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 44100, numChannels: 1), path: path);

  @override
  Future<void> pause() => _rec.pause();

  @override
  Future<void> resume() => _rec.resume();

  @override
  Future<String?> stop() => _rec.stop();

  /// Decibels run from about -60 (quiet room) to 0 (clipping); the glow wants 0 to 1.
  @override
  Stream<double> get levelStream => _rec
      .onAmplitudeChanged(const Duration(milliseconds: 120))
      .map((a) => math.max(0.0, math.min(1.0, (a.current + 60) / 60)));

  @override
  Future<void> dispose() => _rec.dispose();
}
