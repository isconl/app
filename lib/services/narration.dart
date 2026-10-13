import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';

import '../api/client.dart';
import '../util/fmt.dart' as fmt;
import 'narration_script.dart';

export 'narration_script.dart' show NarrationScript;

/// Listening to a module instead of reading it.
///
/// Two tiers, because one cannot serve both halves of what ARCHITECT asked for:
///
///   DEVICE  the default. Free, instant, offline, and available on EVERY module
///     including the plane-B ones, because nothing leaves the phone. The OS
///     voice is adequate for review and poor for a first read.
///
///   AGENT   the agent's Chatterbox narration (self-hosted, open-source),
///     synthesised once per module revision and cached server-side. The
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

  // ---- the device voice (BI26101394) ----
  //
  // The module is a NarrationScript of sentences, spoken one chunk (at most 3000 characters of whole
  // sentences) at a time, with speak() awaiting each chunk's end. `_at` is the sentence the current chunk
  // started on; the engine's progress callback moves `_heard` sentence by sentence inside it. Pause stops the
  // engine and keeps `_heard`, so resume, the skips and the saved place all start on a sentence.

  NarrationScript? _script;
  int _at = 0;
  int _heard = 0;

  /// Bumped on every start, stop and skip, so a chunk loop that was overtaken ends quietly.
  int _run = 0;

  /// The device voice chosen, as the engine names it, once one has been picked.
  String? deviceVoice;

  /// Set when the engine has no voice on the phone (only network ones), so the bar can offer the install.
  bool needsOfflineVoice = false;

  /// Remembers the place in a module and the chosen voice across restarts (the snapshot store, wired in
  /// app_scope). Null in tests.
  Future<String?> Function(String key)? readSetting;
  Future<void> Function(String key, String? value)? writeSetting;

  static String _placeKey(String k) => 'narration.place:$k';
  static const _voiceKey = 'narration.voice';

  Future<void> _wireTts() async {
    if (_ttsWired) return;
    _ttsWired = true;
    await _tts.awaitSpeakCompletion(true);
    _tts.setProgressHandler((text, start, end, word) {
      final s = _script;
      if (s == null || tier != NarrationTier.device) return;
      final at = s.sentenceAtOffset(_at, start);
      if (at != _heard) {
        _heard = at;
        position = s.positionOf(_heard, speed);
        notifyListeners();
      }
    });
    _tts.setErrorHandler((msg) {
      if (tier != NarrationTier.device) return;
      _run++;
      error = 'The device voice stopped with an error ($msg). Tap Listen to try again.';
      state = NarrationState.idle;
      current = null;
      notifyListeners();
    });
    await _pickVoice();
  }

  /// English, British first, and a voice on the phone rather than one that needs the network. The user's
  /// earlier choice wins when it is still installed.
  Future<void> _pickVoice() async {
    try {
      await _tts.setLanguage('en-GB');
      final raw = await _tts.getVoices;
      final voices = [
        for (final v in (raw is List ? raw : const []))
          if (v is Map) v.map((k, val) => MapEntry('$k', '$val')),
      ];
      final saved = await readSetting?.call(_voiceKey);
      final pick = chooseVoice(voices, saved: saved);
      needsOfflineVoice = voices.isNotEmpty && pick == null;
      if (pick != null) {
        await _tts.setVoice({'name': pick['name']!, 'locale': pick['locale']!});
        deviceVoice = pick['name'];
      }
    } catch (_) {
      // Some engines report no voices; the default voice still speaks.
    }
  }

  /// Read a module aloud with the device voice. Works offline, always. Starts where the listener left this
  /// module last time, unless [fromStart].
  Future<void> speakDevice({
    required String course,
    required String file,
    required String markdown,
    bool fromStart = false,
  }) async {
    await stop();
    tier = NarrationTier.device;
    current = key(course, file);
    error = null;
    state = NarrationState.loading;
    notifyListeners();

    final script = NarrationScript(speakable(markdown));
    if (script.isEmpty) {
      error = 'Nothing in this module to read aloud.';
      state = NarrationState.idle;
      current = null;
      notifyListeners();
      return;
    }
    try {
      await _wireTts();
      await _tts.setSpeechRate(_ttsRate(speed));
    } catch (e) {
      error = 'The phone\'s voice engine did not start ($e). Check Text-to-speech in Android settings, '
          'then tap Listen again.';
      state = NarrationState.idle;
      current = null;
      notifyListeners();
      return;
    }
    _script = script;
    final saved = fromStart ? null : int.tryParse(await readSetting?.call(_placeKey(current!)) ?? '');
    _heard = (saved != null && saved < script.length) ? saved : 0;
    duration = script.durationAt(speed);
    await _speakFrom(_heard);
  }

  /// Speaks chunk after chunk from sentence [from] until the end, a stop, or a newer run.
  Future<void> _speakFrom(int from) async {
    final s = _script;
    if (s == null) return;
    final run = ++_run;
    state = NarrationState.playing;
    _heard = from;
    position = s.positionOf(from, speed);
    notifyListeners();
    var i = from;
    while (i < s.length) {
      final chunk = s.chunkAt(i);
      _at = i;
      final dynamic ok = await _tts.speak(chunk.text);
      if (run != _run) return; // paused, stopped, skipped or restarted meanwhile
      if (ok == 0 || ok == false) {
        // Android refused the utterance; it is never retried in a loop.
        error = 'The phone would not read this part aloud. Tap Listen to try again from here.';
        state = NarrationState.idle;
        current = null;
        notifyListeners();
        return;
      }
      i = chunk.next;
      _heard = i;
      position = s.positionOf(i, speed);
      unawaited(_savePlace(i));
      notifyListeners();
    }
    // The end: the next Listen starts the module from the top.
    unawaited(_savePlace(null));
    _script = null;
    state = NarrationState.idle;
    current = null;
    position = Duration.zero;
    notifyListeners();
  }

  Future<void> _savePlace(int? sentence) async {
    final k = current;
    if (k == null) return;
    try {
      await writeSetting?.call(_placeKey(k), sentence?.toString());
    } catch (_) {}
  }

  /// Skip [seconds] forward or (negative) back, landing on a sentence start. Device voice only; the agent's
  /// audio seeks on its own timeline.
  Future<void> skip(int seconds) async {
    if (tier == NarrationTier.agent) {
      final p = _player;
      if (p == null) return;
      var to = p.position + Duration(seconds: seconds);
      if (to < Duration.zero) to = Duration.zero;
      if (duration > Duration.zero && to > duration) to = duration;
      await p.seek(to);
      return;
    }
    final s = _script;
    if (s == null || current == null) return;
    final to = s.skip(_heard, seconds, speed).clamp(0, s.length - 1);
    final wasPlaying = state == NarrationState.playing;
    _run++;
    await _tts.stop();
    _heard = to;
    position = s.positionOf(to, speed);
    unawaited(_savePlace(to));
    if (wasPlaying) {
      await _speakFrom(to);
    } else {
      notifyListeners();
    }
  }

  /// Chosen in settings: the voice to use from now on, remembered.
  Future<void> chooseDeviceVoice(Map<String, String> voice) async {
    await _tts.setVoice({'name': voice['name']!, 'locale': voice['locale']!});
    deviceVoice = voice['name'];
    await writeSetting?.call(_voiceKey, voice['name']);
    notifyListeners();
  }

  /// The installed English voices, local ones first, for the settings picker.
  Future<List<Map<String, String>>> englishVoices() async {
    await _wireTts();
    final raw = await _tts.getVoices;
    final voices = [
      for (final v in (raw is List ? raw : const []))
        if (v is Map) v.map((k, val) => MapEntry('$k', '$val')),
    ].where((v) => (v['locale'] ?? '').toLowerCase().startsWith('en')).toList()
      ..sort((a, b) => _voiceRank(b).compareTo(_voiceRank(a)));
    return voices;
  }

  /// flutter_tts rates are not multiples of natural pace. On Android the plugin doubles the value before
  /// handing it to the engine, so 0.5 is the engine's own 1.0, its natural pace, and 1.0 is double speed;
  /// iOS treats 0.5 as normal too. Mapped so the UI can talk in the multiples a person expects.
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
    } else {
      // An utterance keeps the rate it started with, so a playing module restarts its current sentence
      // at the new rate; the timeline is re-estimated for it.
      await _tts.setSpeechRate(_ttsRate(speed));
      final s = _script;
      if (s != null) {
        duration = s.durationAt(speed);
        position = s.positionOf(_heard, speed);
        if (state == NarrationState.playing) {
          _run++;
          await _tts.stop();
          unawaited(_speakFrom(_heard));
        }
      }
    }
    notifyListeners();
  }

  Future<void> pause() async {
    if (tier == NarrationTier.agent) {
      await _player?.pause();
    } else if (_script != null) {
      // Stop the engine and keep the sentence being heard; resume starts there.
      _run++;
      await _tts.stop();
      state = NarrationState.paused;
      unawaited(_savePlace(_heard));
    }
    notifyListeners();
  }

  Future<void> resume() async {
    if (tier == NarrationTier.agent) {
      await _player?.play();
      state = NarrationState.playing;
      notifyListeners();
    } else if (_script != null && state == NarrationState.paused) {
      await _speakFrom(_heard);
    }
  }

  Future<void> seek(Duration d) async {
    if (tier == NarrationTier.agent) {
      await _player?.seek(d);
      return;
    }
    final s = _script;
    if (s == null) return;
    // The device timeline is an estimate from word counts; a seek lands on the sentence starting nearest it.
    final to = s.skip(0, d.inSeconds, speed).clamp(0, s.length - 1);
    final wasPlaying = state == NarrationState.playing;
    _run++;
    await _tts.stop();
    _heard = to;
    position = s.positionOf(to, speed);
    unawaited(_savePlace(to));
    if (wasPlaying) {
      await _speakFrom(to);
    } else {
      notifyListeners();
    }
  }

  Future<void> stop() async {
    _run++;
    if (tier == NarrationTier.device && _script != null && current != null) {
      unawaited(_savePlace(_heard));
    }
    _script = null;
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

/// BI26101394: the voice to use from what the engine reports (`name`, `locale`, and on Android `quality` and
/// `network_required`). A voice that needs the network is never chosen, since this tier exists to work in
/// airplane mode. The [saved] choice wins while it is still installed and on the phone; otherwise British
/// English, then any English, highest quality first. Null when no English voice is on the phone.
Map<String, String>? chooseVoice(List<Map<String, String>> voices, {String? saved}) {
  final local = voices.where((v) => !_needsNetwork(v) && (v['locale'] ?? '').toLowerCase().startsWith('en'));
  if (saved != null) {
    for (final v in local) {
      if (v['name'] == saved) return v;
    }
  }
  Map<String, String>? best;
  for (final v in local) {
    if (best == null || _voiceRank(v) > _voiceRank(best)) best = v;
  }
  return best;
}

bool _needsNetwork(Map<String, String> v) {
  final n = (v['network_required'] ?? '').toLowerCase();
  return n == '1' || n == 'true' || (v['name'] ?? '').toLowerCase().contains('network');
}

/// British English beats other English; within that, the engine's quality figure (Android reports 100 to
/// 500), then a local voice over a network one.
int _voiceRank(Map<String, String> v) {
  final locale = (v['locale'] ?? '').toLowerCase().replaceAll('_', '-');
  final gb = locale == 'en-gb' ? 1000 : 0;
  final quality = int.tryParse(v['quality'] ?? '') ?? 300;
  return gb + quality + (_needsNetwork(v) ? 0 : 1);
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
  var src = markdown.replaceAll('\r\n', '\n');
  // BI26101394: what a 4.4.0 module carries that a listener must never hear. The front matter, comments,
  // and LaTeX, which reads as a string of backslashes; a block formula is pointed at, a plain inline one
  // is spoken as written.
  src = src.replaceFirst(RegExp(r'^﻿?---\n[\s\S]*?\n---[ \t]*(\n|$)'), '');
  src = src.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
  src = src.replaceAll(RegExp(r'\$\$[\s\S]+?\$\$'), '\n(formula, see screen)\n');
  src = src.replaceAllMapped(RegExp(r'(?<![\\$\w])\$(?=\S)([^$\n]+?)(?<=\S)\$(?![\w$])'), (m) {
    final f = m.group(1)!;
    return RegExp(r'[\\{}_^]').hasMatch(f) ? '(formula, see screen)' : f;
  });
  final lines = src.split('\n');
  final out = <String>[];
  var inCode = false;
  var fenceIsCode = true;
  var codeSkipped = 0;
  var activitySkipped = 0;
  var tableSkipped = 0;

  for (var i = 0; i < lines.length; i++) {
    var l = lines[i];

    if (l.trimLeft().startsWith('```')) {
      if (!inCode) {
        fenceIsCode = _codeFence(l.trimLeft().substring(3).trim());
      } else if (fenceIsCode) {
        codeSkipped++;
      } else {
        activitySkipped++;
      }
      inCode = !inCode;
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
      // A movement key ("ORIENT · Sky As Sphere") is a label for the eye; the title is what is said.
      final title = h
          .group(2)!
          .replaceAll(RegExp(r'[*_`]'), '')
          .replaceFirst(RegExp(r'^[A-Z][A-Z ]{1,20}\s*[·•|:]\s*'), '')
          .replaceAll(RegExp(r'\{[^}]*\}'), '')
          .trim();
      if (title.isNotEmpty) out.addAll(['', '$title.', '']);
      continue;
    }

    l = l.replaceFirst(RegExp(r'^\s*>\s?'), '');
    l = l.replaceFirst(RegExp(r'^(\s*)[-*+]\s+'), r'');
    l = l.replaceFirst(RegExp(r'^(\s*)\d+[.)]\s+'), r'');

    l = l
        // An image says what its alt text says; a glossary term says just the term.
        .replaceAllMapped(RegExp(r'!\[([^\]]*)\]\([^)]*\)'),
            (m) => m.group(1)!.trim().isEmpty ? '' : 'Image: ${m.group(1)!.trim()}.')
        .replaceAllMapped(RegExp(r'\[\[([^\]|]+)(\|[^\]]*)?\]\]'), (m) => m.group(1)!.trim())
        .replaceAll(RegExp(r'<[^>\n]+>'), '')
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
  if (activitySkipped > 0) {
    notes.add('$activitySkipped activit${activitySkipped == 1 ? 'y' : 'ies'}');
  }
  if (notes.isNotEmpty) {
    final list = notes.length == 1
        ? notes.single
        : '${notes.sublist(0, notes.length - 1).join(', ')} and ${notes.last}';
    text += '\n\nThis module also contains $list, which are not read aloud. Open it to read them.';
  }
  return text;
}

const _codeLangs = {
  '', 'dart', 'js', 'javascript', 'ts', 'typescript', 'python', 'py', 'bash', 'sh', 'shell', 'powershell',
  'ps1', 'json', 'yaml', 'yml', 'toml', 'rust', 'rs', 'kotlin', 'kt', 'java', 'c', 'cpp', 'c++', 'cs',
  'sql', 'html', 'css', 'go', 'text', 'txt', 'xml', 'r', 'swift', 'ruby', 'php', 'diff', 'console',
};

/// A fence of program code ("```python") is announced as code; anything else ("```experiment",
/// "```chart", "```quiz") is an activity on the page.
bool _codeFence(String info) => _codeLangs.contains(info.split(RegExp(r'\s')).first.toLowerCase());
