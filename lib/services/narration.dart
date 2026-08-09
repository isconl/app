import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';

import '../api/client.dart';
import '../util/fmt.dart' as fmt;

/// Listening to a module instead of reading it.
///
/// Two tiers, because one cannot serve both halves of what ARCHITECT asked for:
///
///   DEVICE  the default. Free, instant, offline, and available on EVERY module
///     including the plane-B ones, because nothing leaves the phone. The OS
///     voice is adequate for review and poor for a first read.
///
///   AGENT   the agent's ElevenLabs narration, synthesised once per module
///     revision and cached server-side. Audiobook quality, paid for once. The
///     agent REFUSES to narrate a module that declares its own plane, so this
///     tier is simply unavailable for those - which is correct, not a fault, and
///     the UI says so in those words.
///
/// The device tier is what makes this usable on a matatu with no signal, so it
/// is the one that must never depend on the network. That is why the markdown to
/// speech transform is duplicated in Dart rather than fetched: an offline
/// feature cannot ask a server what to say.
enum NarrationTier { device, agent }

enum NarrationState { idle, loading, playing, paused }

class Narrator extends ChangeNotifier {
  Narrator(this._apiProvider);

  final ApiClient Function() _apiProvider;

  final FlutterTts _tts = FlutterTts();
  AudioPlayer? _player;

  NarrationTier tier = NarrationTier.device;
  NarrationState state = NarrationState.idle;

  /// course/file currently loaded, or null.
  String? current;
  String? error;

  /// Playback rate. 1.0 is the voice's natural pace; a dense module is often
  /// better at 1.15 and a first read at 0.9.
  double speed = 1.0;

  Duration position = Duration.zero;
  Duration duration = Duration.zero;

  bool _ttsWired = false;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<PlayerState>? _stateSub;

  bool get busy => state == NarrationState.loading;
  bool get active => state == NarrationState.playing || state == NarrationState.paused;

  static String key(String course, String file) => '$course/$file';

  Future<void> _wireTts() async {
    if (_ttsWired) return;
    _ttsWired = true;
    await _tts.awaitSpeakCompletion(true);
    _tts.setCompletionHandler(() {
      if (tier == NarrationTier.device) {
        state = NarrationState.idle;
        current = null;
        notifyListeners();
      }
    });
    _tts.setErrorHandler((msg) {
      error = 'The device voice failed: $msg';
      state = NarrationState.idle;
      notifyListeners();
    });
  }

  /// Read a module aloud with the device voice. Works offline, always.
  Future<void> speakDevice({
    required String course,
    required String file,
    required String markdown,
  }) async {
    await stop();
    await _wireTts();
    tier = NarrationTier.device;
    current = key(course, file);
    error = null;
    state = NarrationState.playing;
    // The device tier has no seekable timeline to report - flutter_tts exposes
    // no position - so duration stays zero and the UI shows a pulse rather than
    // a progress bar it would have to fake.
    position = Duration.zero;
    duration = Duration.zero;
    notifyListeners();

    final text = speakable(markdown);
    if (text.trim().isEmpty) {
      error = 'Nothing in this module to read aloud.';
      state = NarrationState.idle;
      notifyListeners();
      return;
    }
    await _tts.setSpeechRate(_ttsRate(speed));
    await _tts.speak(text);
  }

  /// flutter_tts rates are not multiples of natural pace: on Android 0.5 is
  /// roughly normal speech and 1.0 is comically fast. Mapped so the UI can talk
  /// in the multiples a person expects.
  double _ttsRate(double multiple) => (0.5 * multiple).clamp(0.1, 1.0);

  /// Play the agent's narration. Requires a connection the first time; once
  /// played, just_audio has it cached for the session.
  Future<void> playAgent({
    required String course,
    required String file,
  }) async {
    await stop();
    tier = NarrationTier.agent;
    current = key(course, file);
    error = null;
    state = NarrationState.loading;
    notifyListeners();

    final api = _apiProvider();
    var base = api.baseUrl.trim();
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);
    final uri = Uri.parse('$base/api/learning/audio'
        '?course=${Uri.encodeQueryComponent(course)}'
        '&file=${Uri.encodeQueryComponent(file)}');

    try {
      final p = AudioPlayer();
      _player = p;
      _posSub = p.positionStream.listen((d) {
        position = d;
        notifyListeners();
      });
      _stateSub = p.playerStateStream.listen((s) {
        if (s.processingState == ProcessingState.completed) {
          state = NarrationState.idle;
          current = null;
          position = Duration.zero;
        } else if (s.playing) {
          state = NarrationState.playing;
        } else if (state == NarrationState.playing) {
          state = NarrationState.paused;
        }
        notifyListeners();
      });
      // The route is Bearer-gated, so the header travels with the media request
      // rather than the token being put in a URL where it would end up in logs.
      final d = await p.setAudioSource(AudioSource.uri(
        uri,
        headers: api.token.isEmpty ? null : {'Authorization': 'Bearer ${api.token}'},
      ));
      duration = d ?? Duration.zero;
      await p.setSpeed(speed);
      await p.play();
      state = NarrationState.playing;
    } catch (e) {
      error = 'Could not play the narration. It may not be made yet.';
      state = NarrationState.idle;
      current = null;
    }
    notifyListeners();
  }

  /// Ask the agent to synthesise this module properly.
  ///
  /// Returns null on success, or the reason it will not. A plane-B refusal comes
  /// back as a reason rather than an error, because nothing went wrong - the
  /// answer is no, and repeating the request will not change it.
  Future<String?> requestNarration(String course, String file) async {
    try {
      final res = await _apiProvider().postJson('/api/learning/narrate', {
        'course': course,
        'file': file,
      }, cold: true);
      final m = fmt.m(res);
      if (m['ok'] == true) return null;
      return fmt.s(m['error']).isEmpty
          ? 'The agent could not make it.'
          : fmt.s(m['error']);
    } on OfflineException {
      return 'Offline - the agent makes narration, so this one needs a connection.';
    } catch (e) {
      return 'The agent could not make it ($e).';
    }
  }

  Future<void> setSpeed(double v) async {
    speed = double.parse(v.clamp(0.7, 2.0).toStringAsFixed(2));
    if (tier == NarrationTier.agent) {
      await _player?.setSpeed(speed);
    } else if (state == NarrationState.playing) {
      // flutter_tts cannot change rate mid-utterance, so this takes effect on
      // the next module rather than pretending to apply now.
      await _tts.setSpeechRate(_ttsRate(speed));
    }
    notifyListeners();
  }

  Future<void> pause() async {
    if (tier == NarrationTier.agent) {
      await _player?.pause();
    } else {
      // The device tier cannot resume mid-utterance on Android, so pause is
      // stop. Saying so is better than a resume button that restarts the module.
      await _tts.stop();
      state = NarrationState.idle;
      current = null;
    }
    notifyListeners();
  }

  Future<void> resume() async {
    if (tier == NarrationTier.agent) {
      await _player?.play();
      state = NarrationState.playing;
      notifyListeners();
    }
  }

  Future<void> seek(Duration d) async {
    if (tier == NarrationTier.agent) await _player?.seek(d);
  }

  Future<void> stop() async {
    await _posSub?.cancel();
    await _stateSub?.cancel();
    _posSub = null;
    _stateSub = null;
    try { await _tts.stop(); } catch (_) {}
    try { await _player?.dispose(); } catch (_) {}
    _player = null;
    state = NarrationState.idle;
    current = null;
    position = Duration.zero;
    duration = Duration.zero;
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}

/// Markdown into something worth hearing.
///
/// Mirrors `speakable()` in the agent's lib/voice.js on purpose. The duplication
/// is the price of the device tier working with no signal - an offline feature
/// cannot ask a server what to say. The two must agree, so both are documented
/// with the same reasoning and both are covered by tests.
///
/// Read verbatim, markdown is unlistenable: it says "hash hash the directive"
/// and narrates table pipes. So headings become sentences, fenced code and
/// tables are skipped because reading Kotlin aloud is worse than acknowledging
/// it exists, links keep their text and lose the URL, and what was skipped is
/// announced at the end instead of vanishing.
String speakable(String markdown) {
  final lines = markdown.replaceAll('\r\n', '\n').split('\n');
  final out = <String>[];
  var inCode = false;
  var codeSkipped = 0;
  var tableSkipped = 0;

  for (var i = 0; i < lines.length; i++) {
    var l = lines[i];

    if (l.trimLeft().startsWith('```')) {
      inCode = !inCode;
      if (!inCode) codeSkipped++;
      continue;
    }
    if (inCode) continue;

    final next = i + 1 < lines.length ? lines[i + 1] : '';
    if (l.trimLeft().startsWith('|') &&
        RegExp(r'^\s*\|?[\s:|-]+\|?\s*$').hasMatch(next) &&
        next.contains('-')) {
      while (i < lines.length && lines[i].trimLeft().startsWith('|')) {
        i++;
      }
      i--; // the outer loop increments
      tableSkipped++;
      continue;
    }

    if (RegExp(r'^\s*(-{3,}|\*{3,}|_{3,})\s*$').hasMatch(l)) {
      out.add('');
      continue;
    }

    final h = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(l);
    if (h != null) {
      out.addAll(['', '${h.group(2)!.replaceAll(RegExp(r'[*_`]'), '').trim()}.', '']);
      continue;
    }

    l = l.replaceFirst(RegExp(r'^\s*>\s?'), '');
    l = l.replaceFirst(RegExp(r'^(\s*)[-*+]\s+'), r'');
    l = l.replaceFirst(RegExp(r'^(\s*)\d+[.)]\s+'), r'');

    l = l
        .replaceAllMapped(RegExp(r'\[([^\]]+)\]\(([^)]+)\)'), (m) => m.group(1)!)
        .replaceAllMapped(RegExp(r'`([^`]+)`'), (m) => m.group(1)!)
        .replaceAllMapped(RegExp(r'\*\*([^*]+)\*\*'), (m) => m.group(1)!)
        .replaceAllMapped(RegExp(r'\*([^*]+)\*'), (m) => m.group(1)!)
        .replaceAllMapped(RegExp(r'(^|\s)_([^_]+)_(\s|$)'),
            (m) => '${m.group(1)}${m.group(2)}${m.group(3)}');

    out.add(l.trim());
  }

  var text = out
      .join('\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
      .trim();

  final notes = <String>[];
  if (codeSkipped > 0) {
    notes.add('$codeSkipped code block${codeSkipped == 1 ? '' : 's'}');
  }
  if (tableSkipped > 0) {
    notes.add('$tableSkipped table${tableSkipped == 1 ? '' : 's'}');
  }
  if (notes.isNotEmpty) {
    text += '\n\nThis module also contains ${notes.join(' and ')}, '
        'which are not read aloud. Open it to read them.';
  }
  return text;
}
