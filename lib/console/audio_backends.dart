/// BI26092648: the real audio engine and microphone behind the Console card.
///
/// Kept apart from the logic so tests never load a platform plugin: nothing in
/// `console_player.dart` or `console_recorder.dart` imports this file.
library;

import 'dart:async';
import 'dart:math' as math;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:record/record.dart';

import 'console_player.dart';
import 'console_recorder.dart';

bool _backgroundReady = false;

/// BI26100323: lock-screen and notification controls, headset buttons and playback with the screen off, on Android.
/// Called once at start with a short timeout and wrapped so that nothing here can stop the app starting: if it fails
/// (or the platform has no media service) playback simply stays foreground-only, as before. Returns whether it is on.
Future<bool> ensureBackgroundAudio() async {
  if (_backgroundReady) return true;
  if (kIsWeb || !Platform.isAndroid) return false;
  try {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.sconl.isconl.playback',
      androidNotificationChannelName: 'Console playback',
      androidNotificationOngoing: true,
    ).timeout(const Duration(seconds: 4));
    _backgroundReady = true;
  } catch (_) {
    _backgroundReady = false;
  }
  return _backgroundReady;
}

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
  Future<Duration?> load(ConsoleTrack track) {
    // The tag is what the notification and lock screen show; without the background service it is ignored.
    final tag = MediaItem(id: track.id, title: track.title, album: 'iSconl');
    return _player.setAudioSource(
      track.isFile
          ? AudioSource.file(track.uri, tag: tag)
          // The route is Bearer-gated, so the header travels with the media
          // request rather than the token sitting in a URL where it would be logged.
          : AudioSource.uri(Uri.parse(track.uri), headers: track.headers, tag: tag),
    );
  }

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

  static const _channel = MethodChannel('isconl/platform');

  /// A foreground service of type microphone for the length of a take, so Android 14 keeps capturing with the screen
  /// off. A failure to start it never blocks recording: the take then behaves as it did before.
  Future<void> _service(String method) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>(method);
    } catch (_) {}
  }

  @override
  Future<void> start(String path) async {
    await _service('startRecordingService');
    try {
      await _rec.start(const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 44100, numChannels: 1), path: path);
    } catch (_) {
      await _service('stopRecordingService');
      rethrow;
    }
  }

  @override
  Future<void> pause() => _rec.pause();

  @override
  Future<void> resume() => _rec.resume();

  @override
  Future<String?> stop() async {
    try {
      return await _rec.stop();
    } finally {
      await _service('stopRecordingService');
    }
  }

  /// Decibels run from about -60 (quiet room) to 0 (clipping); the glow wants 0 to 1.
  @override
  Stream<double> get levelStream => _rec
      .onAmplitudeChanged(const Duration(milliseconds: 120))
      .map((a) => math.max(0.0, math.min(1.0, (a.current + 60) / 60)));

  @override
  Future<void> dispose() => _rec.dispose();
}
