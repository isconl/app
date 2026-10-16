import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';

import '../api/client.dart';
import '../util/fmt.dart' as fmt;
import 'audio_downloads.dart';

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

/// The slice of the text-to-speech engine the narrator needs. [FlutterTtsDriver]
/// is the real one; tests pass a fake, so the chunk loop is testable without a
/// phone.
abstract class TtsDriver {
  Future<void> awaitSpeakCompletion(bool wait);
  Future<void> setLanguage(String language);
  Future<void> setSpeechRate(double rate);
  Future<void> setVoice(Map<String, String> voice);
  Future<List<Map<String, String>>> getVoices();

  /// Speaks one chunk and, with awaitSpeakCompletion(true), returns when it has
  /// finished. A result of 1 is success; anything else means the engine refused.
  Future<Object?> speak(String text);
  Future<void> stop();

  /// False only when the phone has no text-to-speech engine to speak with. A slow or failed
  /// answer counts as ready: the speak call then reports the real problem.
  Future<bool> engineReady();
}

class FlutterTtsDriver implements TtsDriver {
  final FlutterTts _t = FlutterTts();

  @override
  Future<void> awaitSpeakCompletion(bool wait) async => _t.awaitSpeakCompletion(wait);
  @override
  Future<void> setLanguage(String language) async => _t.setLanguage(language);
  @override
  Future<void> setSpeechRate(double rate) async => _t.setSpeechRate(rate);
  @override
  Future<void> setVoice(Map<String, String> voice) async => _t.setVoice(voice);

  @override
  Future<List<Map<String, String>>> getVoices() async {
    final v = await _t.getVoices;
    if (v is! List) return const [];
    return [
      for (final e in v)
        if (e is Map) {for (final k in e.keys) '$k': '${e[k]}'},
    ];
  }

  @override
  Future<Object?> speak(String text) => _t.speak(text);
  @override
  Future<void> stop() async => _t.stop();

  @override
  Future<bool> engineReady() async {
    try {
      final engines = await _t.getEngines.timeout(const Duration(seconds: 3));
      return engines is! List || engines.isNotEmpty;
    } catch (_) {
      return true;
    }
  }
}

/// Where the voice choice and the per-module position are kept. The app backs
/// it with its local database; tests use a map.
abstract class NarrationStore {
  Future<Object?> read(String key);
  Future<void> write(String key, Object value);
  Future<void> remove(String key);
}

class MemoryNarrationStore implements NarrationStore {
  final Map<String, Object> data = {};
  @override
  Future<Object?> read(String key) async => data[key];
  @override
  Future<void> write(String key, Object value) async => data[key] = value;
  @override
  Future<void> remove(String key) async => data.remove(key);
}

class Narrator extends ChangeNotifier {
  Narrator(this._apiProvider, {TtsDriver? tts, NarrationStore? store, this.downloads})
      : _tts = tts ?? FlutterTtsDriver(),
        _store = store;

  /// Narration kept on the phone. Played first when its revision matches.
  final AudioDownloads? downloads;

  /// Where the current audio comes from: downloaded, streamed or device.
  String? source;

  final ApiClient Function() _apiProvider;

  final TtsDriver _tts;
  final NarrationStore? _store;
  AudioPlayer? _player;

  NarrationTier tier = NarrationTier.device;
  NarrationState state = NarrationState.idle;

  /// course/file currently loaded, or null.
  String? current;
  String? error;

  /// True when the engine has no offline voice installed, so the UI can say how
  /// to get one instead of failing without a word.
  bool needsVoiceData = false;

  /// Playback rate. 1.0 is the voice's natural pace; a dense module is often
  /// better at 1.15 and a first read at 0.9.
  double speed = 1.0;

  Duration position = Duration.zero;
  Duration duration = Duration.zero;

  /// The device tier reads a module in chunks (see [chunkSentences]); these say
  /// where it is, so the bar can show real progress.
  List<String> _chunks = const [];
  int _chunkIndex = 0;
  int get chunkIndex => _chunkIndex;
  int get chunkCount => _chunks.length;
  double get deviceProgress => _chunks.isEmpty ? 0 : _chunkIndex / _chunks.length;

  /// Bumped on every stop, pause and new start, so a loop that was told to stop
  /// can tell it is stale when its speak() call returns.
  int _run = 0;
  String? _textHash;

  bool _ttsWired = false;

  /// True when the phone has no text-to-speech engine, so the bar can say how to set one up.
  bool noEngine = false;

  /// A passage the voice could not read was skipped; the module carried on.
  String? notice;
  int _skipped = 0;
  bool _spokenAny = false;
  Map<String, String>? _voice;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<PlayerState>? _stateSub;

  bool get busy => state == NarrationState.loading;
  bool get active => state == NarrationState.playing || state == NarrationState.paused;

  static String key(String course, String file) => '$course/$file';
  static const _voiceKey = 'narration.voice.v1';
  static String _posKey(String k) => 'narration.pos.v1.$k';

  /// The best installed voice: British English, on the device, highest quality.
  /// Null when the engine lists no voices at all.
  static Map<String, String>? pickVoice(List<Map<String, String>> voices) {
    bool isGb(Map<String, String> v) =>
        (v['locale'] ?? '').toLowerCase().replaceAll('_', '-').startsWith('en-gb');
    bool local(Map<String, String> v) => (v['network_required'] ?? '0') != '1';
    int quality(Map<String, String> v) {
      final q = (v['quality'] ?? '').toLowerCase();
      if (q.contains('very high')) return 3;
      if (q.contains('high')) return 2;
      if (q.contains('normal')) return 1;
      return 0;
    }

    final usable = voices.where((v) => (v['name'] ?? '').isNotEmpty).toList();
    final gbLocal = usable.where((v) => isGb(v) && local(v)).toList()
      ..sort((a, b) => quality(b).compareTo(quality(a)));
    if (gbLocal.isNotEmpty) return gbLocal.first;
    final anyLocalEn =
        usable.where((v) => (v['locale'] ?? '').toLowerCase().startsWith('en') && local(v)).toList()
          ..sort((a, b) => quality(b).compareTo(quality(a)));
    return anyLocalEn.isEmpty ? null : anyLocalEn.first;
  }

  Future<void> _wireTts() async {
    if (_ttsWired) return;
    _ttsWired = true;
    // Wait for the engine before the first speak: a cold start that speaks too early gets refused.
    noEngine = !await _tts.engineReady();
    if (noEngine) {
      _ttsWired = false; // look again on the next try, in case one has been set up since
      return;
    }
    await _tts.awaitSpeakCompletion(true);
    try {
      await _tts.setLanguage('en-GB');
    } catch (_) {}
    // The reader's own choice wins; otherwise the best offline voice.
    try {
      final saved = await _store?.read(_voiceKey);
      final voices = await _tts.getVoices();
      Map<String, String>? chosen;
      if (saved is Map) {
        final name = '${saved['name']}';
        for (final v in voices) {
          if (v['name'] == name) chosen = v;
        }
      }
      chosen ??= pickVoice(voices);
      needsVoiceData = chosen == null || (chosen['network_required'] ?? '0') == '1';
      if (chosen != null) {
        _voice = chosen;
        await _tts.setVoice({'name': chosen['name']!, 'locale': chosen['locale'] ?? 'en-GB'});
      }
    } catch (_) {
      // No voice list: the engine default still speaks.
    }
  }

  /// The voices the reader can choose between, offline ones first.
  Future<List<Map<String, String>>> voices() async {
    final all = await _tts.getVoices();
    final en = all.where((v) => (v['locale'] ?? '').toLowerCase().startsWith('en')).toList();
    en.sort((a, b) =>
        ((a['network_required'] ?? '0') == '1' ? 1 : 0).compareTo((b['network_required'] ?? '0') == '1' ? 1 : 0));
    return en;
  }

  Future<void> chooseVoice(Map<String, String> voice) async {
    _voice = voice;
    await _tts.setVoice({'name': voice['name']!, 'locale': voice['locale'] ?? 'en-GB'});
    await _store?.write(_voiceKey, {'name': voice['name']!});
    needsVoiceData = (voice['network_required'] ?? '0') == '1';
    notifyListeners();
  }

  String? get voiceName => _voice?['name'];

  /// Read a module aloud with the device voice. Works offline, always. A module
  /// is spoken chunk by chunk, because Android refuses one call longer than
  /// about 4,000 characters and flutter_tts then re-queues it forever, which
  /// looked like "playing" with no sound.
  Future<void> speakDevice({
    required String course,
    required String file,
    required String markdown,
  }) async {
    await stop();
    await _wireTts();
    tier = NarrationTier.device;
    source = 'device';
    current = key(course, file);
    error = null;
    notice = null;
    _skipped = 0;
    _spokenAny = false;
    state = NarrationState.playing;
    position = Duration.zero;
    duration = Duration.zero;
    notifyListeners();

    if (noEngine) {
      _fail('No text-to-speech engine is set up. Install or enable one in Settings, then Accessibility, '
          'then Text-to-speech, and try again.');
      return;
    }
    final text = speakable(markdown);
    final chunks = chunkSentences(text);
    if (chunks.isEmpty) {
      error = 'Nothing in this module to read aloud.';
      state = NarrationState.idle;
      current = null;
      notifyListeners();
      return;
    }
    _chunks = chunks;
    _textHash = '${text.length}:${text.hashCode}';
    _chunkIndex = await _savedIndex(current!);
    await _tts.setSpeechRate(_ttsRate(speed));
    await _speakFrom();
  }

  Future<int> _savedIndex(String k) async {
    try {
      final v = await _store?.read(_posKey(k));
      if (v is Map && v['hash'] == _textHash) {
        final i = (v['chunk'] as num?)?.toInt() ?? 0;
        if (i > 0 && i < _chunks.length) return i;
      }
    } catch (_) {}
    return 0;
  }

  Future<void> _savePosition() async {
    final k = current;
    if (k == null) return;
    try {
      await _store?.write(_posKey(k), {'chunk': _chunkIndex, 'hash': _textHash ?? ''});
    } catch (_) {}
  }

  /// Speaks from [_chunkIndex] to the end, one chunk at a time. A newer run, a
  /// pause or a stop makes this one return without touching state.
  Future<void> _speakFrom() async {
    final run = ++_run;
    final k = current;
    while (_chunkIndex < _chunks.length) {
      if (run != _run) return;
      await _savePosition();
      notifyListeners();
      final spoke = await _speakOrSplit(_chunks[_chunkIndex], run);
      if (run != _run) return;
      if (spoke) {
        _spokenAny = true;
      } else {
        _skipped++;
        notice = 'Skipped $_skipped passage${_skipped == 1 ? '' : 's'} the voice could not read.';
      }
      _chunkIndex++;
      if (!_spokenAny && (_skipped >= 2 || _chunkIndex >= _chunks.length)) {
        // Nothing has been read and passages keep being refused: the engine itself is the problem, not the text.
        _fail('The device voice would not start. Check Text-to-speech in your phone settings, then try again.');
        return;
      }
    }
    if (run != _run) return;
    // Finished the whole module: forget the position so Listen starts over.
    try {
      if (k != null) await _store?.remove(_posKey(k));
    } catch (_) {}
    state = NarrationState.idle;
    current = null;
    _chunks = const [];
    _chunkIndex = 0;
    notifyListeners();
  }

  /// Speaks one chunk. When the engine refuses it (Android's -8, an invalid request) the chunk is split
  /// in two and each half tried once; a half that is refused again is skipped. Returns whether
  /// anything of the chunk was read. Only the length goes to the log, never the text.
  Future<bool> _speakOrSplit(String chunk, int run, {bool split = true}) async {
    if (await _speakOnce(chunk, run)) return true;
    if (run != _run) return false;
    if (!split || chunk.length < 2) return false;
    final cut = chunk.lastIndexOf(' ', chunk.length ~/ 2);
    final at = cut > 0 ? cut : chunk.length ~/ 2;
    final a = chunk.substring(0, at).trim();
    final b = chunk.substring(at).trim();
    var any = false;
    for (final half in [a, b]) {
      if (half.isEmpty) continue;
      if (run != _run) return any;
      if (await _speakOnce(half, run)) any = true;
    }
    return any;
  }

  Future<bool> _speakOnce(String chunk, int run) async {
    try {
      final result = await _tts.speak(chunk);
      if (result == 1 || result == true) return true;
      debugPrint('narration: the engine refused a chunk of ${chunk.length} characters (result $result)');
    } catch (e) {
      debugPrint('narration: speak failed for a chunk of ${chunk.length} characters: $e');
    }
    return false;
  }

  void _fail(String message) {
    error = message;
    state = NarrationState.idle;
    // Keep `current` so the bar that owns this module can show the message and
    // offer a retry instead of silently resetting.
    notifyListeners();
  }

  /// Tries the same module again after an error.
  Future<void> retry(String markdown) async {
    final k = current;
    if (k == null) return;
    final i = k.indexOf('/');
    await speakDevice(course: k.substring(0, i), file: k.substring(i + 1), markdown: markdown);
  }

  /// flutter_tts rates are not multiples of natural pace: its Android side
  /// doubles the number it is given, so 0.5 is natural speech and 1.0 is twice
  /// that. Mapped so the UI can talk in the multiples a person expects.
  double _ttsRate(double multiple) => (0.5 * multiple).clamp(0.1, 1.0);

  /// Play the agent's narration. Requires a connection the first time; once
  /// played, just_audio has it cached for the session.
  Future<void> playAgent({
    required String course,
    required String file,
    String? rev,
    String? fallbackMarkdown,
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
      // Order: the copy on the phone (only if it is this revision), then the
      // stream; a failure of both falls through to the device voice below.
      final saved = (rev == null || downloads == null) ? null : await downloads!.local(course, file, rev);
      final Duration? d;
      if (saved != null) {
        d = await p.setAudioSource(AudioSource.file(saved.path));
        source = 'downloaded';
      } else {
        d = await p.setAudioSource(AudioSource.uri(
          uri,
          headers: api.token.isEmpty ? null : {'Authorization': 'Bearer ${api.token}'},
        ));
        source = 'streamed';
      }
      duration = d ?? Duration.zero;
      await p.setSpeed(speed);
      await p.play();
      state = NarrationState.playing;
    } catch (e) {
      if (fallbackMarkdown != null && fallbackMarkdown.trim().isNotEmpty) {
        // Neither a local file nor the stream worked (airplane mode, narration not made
        // yet): the device voice still reads it.
        await speakDevice(course: course, file: file, markdown: fallbackMarkdown);
        return;
      }
      error = 'Could not play the narration. It may not be made yet.';
      state = NarrationState.idle;
      current = null;
      source = null;
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
      // The speech rate applies from the next chunk.
      await _tts.setSpeechRate(_ttsRate(speed));
    }
    notifyListeners();
  }

  Future<void> pause() async {
    if (tier == NarrationTier.agent) {
      await _player?.pause();
    } else if (state == NarrationState.playing) {
      // Stop the engine and keep the place: Resume carries on from the start of
      // the chunk that was being read.
      _run++;
      state = NarrationState.paused;
      await _tts.stop();
    }
    notifyListeners();
  }

  Future<void> resume() async {
    if (tier == NarrationTier.agent) {
      await _player?.play();
      state = NarrationState.playing;
      notifyListeners();
    } else if (state == NarrationState.paused) {
      state = NarrationState.playing;
      await _tts.setSpeechRate(_ttsRate(speed));
      notifyListeners();
      unawaited(_speakFrom());
    }
  }

  /// Jumps a chunk forward or back (about a minute of speech) on the device
  /// tier. The engine reports no timeline, so a chunk is the honest unit.
  Future<void> skip(int chunks) async {
    if (tier != NarrationTier.device || _chunks.isEmpty) return;
    final target = (_chunkIndex + chunks).clamp(0, _chunks.length - 1);
    final wasPlaying = state == NarrationState.playing;
    _run++;
    await _tts.stop();
    _chunkIndex = target;
    notifyListeners();
    if (wasPlaying) unawaited(_speakFrom());
  }

  Future<void> seek(Duration d) async {
    if (tier == NarrationTier.agent) await _player?.seek(d);
  }

  Future<void> stop() async {
    _run++;
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
    _chunks = const [];
    _chunkIndex = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}

/// The most characters one speak call is given. Android's limit is 4,000 on most engines.
const maxChunkChars = 3500;

/// Drops what some engines refuse outright: control characters (newlines and tabs are kept), lone
/// surrogates, and the pipes of a table row, which are read as noise at best.
String cleanForSpeech(String text) {
  final out = StringBuffer();
  final units = text.codeUnits;
  for (var i = 0; i < units.length; i++) {
    final u = units[i];
    if (u == 0x0A || u == 0x09) {
      out.writeCharCode(u);
    } else if (u < 0x20 || u == 0x7F || (u >= 0x80 && u < 0xA0)) {
      continue;
    } else if (u == 0x7C) {
      out.write(' ');
    } else if (u >= 0xD800 && u <= 0xDBFF) {
      if (i + 1 < units.length && units[i + 1] >= 0xDC00 && units[i + 1] <= 0xDFFF) {
        out.writeCharCode(u);
        out.writeCharCode(units[++i]);
      }
    } else if (u >= 0xDC00 && u <= 0xDFFF) {
      continue;
    } else {
      out.writeCharCode(u);
    }
  }
  return out.toString().replaceAll(RegExp(r'[ \t]{2,}'), ' ');
}

/// Splits [text] into pieces of at most [max] characters for the engine, never
/// in the middle of a sentence unless one sentence alone is longer than [max],
/// in which case it breaks at the last comma or space that fits.
///
/// Android's text-to-speech refuses input past `getMaxSpeechInputLength()`
/// (4,000 characters), so 3,000 leaves headroom. Mirrors the sentence chunker in
/// `vault/scripts/tts_service.py`.
List<String> chunkSentences(String text, {int max = 3000}) {
  // BI26101522: no chunk past 3,500 characters whatever the caller asks, and nothing the engine rejects.
  if (max > maxChunkChars) max = maxChunkChars;
  text = cleanForSpeech(text);
  final sentences = <String>[];
  for (final para in text.replaceAll('\r\n', '\n').split(RegExp(r'\n{2,}'))) {
    final p = para.replaceAll('\n', ' ').trim();
    if (p.isEmpty) continue;
    sentences.addAll(p.split(RegExp(r'(?<=[.!?])\s+')));
    // A paragraph break is a pause: mark it so a chunk can end there.
    sentences.add('\u0000');
  }
  final chunks = <String>[];
  var buf = StringBuffer();
  void flush() {
    final s = buf.toString().trim();
    if (s.isNotEmpty) chunks.add(s);
    buf = StringBuffer();
  }

  for (var s in sentences) {
    if (s == '\u0000') {
      continue;
    }
    while (s.length > max) {
      var cut = s.lastIndexOf(RegExp(r'[,;:]\s'), max - 1);
      if (cut <= 0) cut = s.lastIndexOf(' ', max - 1);
      if (cut <= 0) cut = max;
      flush();
      chunks.add(s.substring(0, cut + 1).trim());
      s = s.substring(cut + 1).trim();
    }
    if (s.isEmpty) continue;
    if (buf.length + s.length + 1 > max) flush();
    if (buf.isNotEmpty) buf.write(' ');
    buf.write(s);
  }
  flush();
  return chunks;
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
/// announced at the end instead of vanishing. Module furniture goes too: the
/// YAML front matter, HTML comments, LaTeX (spoken as "formula"), the
/// `[[term|definition]]` glossary markers (the term is read, the definition is
/// not) and images (their alt text is read).
String speakable(String markdown) {
  var src = markdown.replaceAll('\r\n', '\n');
  // YAML front matter, only at the very top.
  src = src.replaceFirst(RegExp(r'^\s*---\n[\s\S]*?\n---[ \t]*(\n|$)'), '');
  src = src.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
  src = src.replaceAllMapped(RegExp(r'\$\$[\s\S]+?\$\$'), (_) => '(formula, see screen)');
  src = src.replaceAllMapped(RegExp(r'(?<![\\$])\$(?!\s)([^$\n]+?)(?<!\s)\$(?!\d)'), (_) => '(formula)');
  src = src.replaceAllMapped(RegExp(r'\[\[([^\]|]+)(?:\|[^\]]*)?\]\]'), (m) => m.group(1)!.trim());
  src = src.replaceAllMapped(RegExp(r'!\[([^\]]*)\]\([^)]*\)'), (m) {
    final alt = m.group(1)!.trim();
    return alt.isEmpty ? '' : alt;
  });

  final lines = src.split('\n');
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
