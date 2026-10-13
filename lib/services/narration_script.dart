/// BI26101394: the device voice's script, split so Android can actually speak it.
///
/// Android refuses any utterance longer than `getMaxSpeechInputLength()` (4000 characters), and flutter_tts
/// re-queues a refused call forever, so a whole module sent in one `speak` played nothing and reported
/// "playing". The script is split into sentences and spoken in chunks of whole sentences, at most
/// [kMaxChunkChars] each. Sentences are also the unit of position: pause and resume, the 30-second skips and
/// the saved place in a module all land on a sentence start, which is where a listener expects to pick up.
///
/// Pure Dart, no plugin, so every rule here is tested without a phone.
library;

/// Well under Android's 4000-character limit, leaving room for engines that count differently.
const int kMaxChunkChars = 3000;

/// Words a minute at 1x, for the estimated timeline (a device voice reports no position of its own).
const double kWordsPerMinute = 150;

class NarrationScript {
  NarrationScript._(this.sentences, this._words, this._wordsBefore);

  /// Splits speakable text into sentences. A paragraph break always ends a sentence; inside a paragraph a
  /// sentence ends at `.`, `!` or `?` (with any closing quotes or brackets) followed by a space. A
  /// sentence longer than [kMaxChunkChars] is split at the last comma, semicolon or space that fits.
  factory NarrationScript(String text) {
    final sentences = <String>[];
    for (final para in text.replaceAll('\r\n', '\n').split(RegExp(r'\n\s*\n'))) {
      final flat = para.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (flat.isEmpty) continue;
      var start = 0;
      for (final m in RegExp(r'''[.!?]+["'”’)\]]*\s+''').allMatches(flat)) {
        _add(sentences, flat.substring(start, m.end));
        start = m.end;
      }
      _add(sentences, flat.substring(start));
    }
    final words = [for (final s in sentences) _wordCount(s)];
    final before = <int>[0];
    for (final w in words) {
      before.add(before.last + w);
    }
    return NarrationScript._(List.unmodifiable(sentences), words, before);
  }

  final List<String> sentences;
  final List<int> _words;

  /// _wordsBefore[i] is the number of words in sentences 0..i-1; the last entry is the total.
  final List<int> _wordsBefore;

  int get length => sentences.length;
  bool get isEmpty => sentences.isEmpty;
  int get totalWords => _wordsBefore.last;

  /// The chunk that starts at sentence [from]: whole sentences joined, at most [maxChars] long (a single
  /// sentence is never longer, see the factory). Returns the text and the index of the first sentence after
  /// it.
  ({String text, int next}) chunkAt(int from, {int maxChars = kMaxChunkChars}) {
    if (from >= length) return (text: '', next: length);
    final buf = StringBuffer(sentences[from]);
    var i = from + 1;
    while (i < length && buf.length + 1 + sentences[i].length <= maxChars) {
      buf
        ..write(' ')
        ..write(sentences[i]);
      i++;
    }
    return (text: buf.toString(), next: i);
  }

  /// Which sentence a character offset inside the chunk starting at [chunkStart] falls in, for the engine's
  /// progress callback.
  int sentenceAtOffset(int chunkStart, int offset) {
    var pos = 0;
    for (var i = chunkStart; i < length; i++) {
      final end = pos + sentences[i].length;
      if (offset < end + 1) return i;
      pos = end + 1; // the joining space
    }
    return length - 1;
  }

  /// The estimated time from the start to the beginning of sentence [index], at [speed].
  Duration positionOf(int index, double speed) => _minutes(_wordsBefore[index.clamp(0, length)], speed);

  /// The estimated length of the whole module at [speed].
  Duration durationAt(double speed) => _minutes(totalWords, speed);

  /// The sentence to resume from after skipping [seconds] (negative is back) from sentence [index].
  int skip(int index, int seconds, double speed) {
    final target = _wordsBefore[index.clamp(0, length)] + (seconds / 60 * kWordsPerMinute * speed).round();
    if (target <= 0) return 0;
    for (var i = 0; i < length; i++) {
      if (_wordsBefore[i + 1] > target) return i;
    }
    return length; // past the end
  }

  static Duration _minutes(int words, double speed) =>
      Duration(milliseconds: (words / (kWordsPerMinute * speed) * 60000).round());

  static int _wordCount(String s) => s.split(' ').where((w) => w.isNotEmpty).length;

  static void _add(List<String> out, String raw) {
    var s = raw.trim();
    while (s.length > kMaxChunkChars) {
      var cut = -1;
      for (final sep in const [', ', '; ', ': ', ' ']) {
        cut = s.lastIndexOf(sep, kMaxChunkChars - 1);
        if (cut > 0) {
          cut += sep.length;
          break;
        }
      }
      if (cut <= 0) cut = kMaxChunkChars;
      out.add(s.substring(0, cut).trim());
      s = s.substring(cut).trim();
    }
    if (s.isNotEmpty) out.add(s);
  }
}
