import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/api/client.dart';
import 'package:isconl/services/narration.dart';

/// A fake engine. `hold` makes speak() wait until stop() or release(), the way a
/// real engine does while it is talking.
class FakeTts implements TtsDriver {
  final spoken = <String>[];
  final attempts = <String>[];
  Object? result = 1;
  bool hold = false;
  Completer<Object?>? _gate;
  List<Map<String, String>> voiceList = [];
  Map<String, String>? setTo;
  double? rate;

  @override
  Future<void> awaitSpeakCompletion(bool wait) async {}
  @override
  Future<void> setLanguage(String language) async {}
  @override
  Future<void> setSpeechRate(double r) async => rate = r;
  @override
  Future<void> setVoice(Map<String, String> v) async => setTo = v;
  @override
  Future<List<Map<String, String>>> getVoices() async => voiceList;

  @override
  Future<Object?> speak(String text) {
    attempts.add(text);
    if (throwTimes > 0) {
      throwTimes--;
      return Future.error(Exception('error from TextToSpeech (speak) -8'));
    }
    if (refuseOver != null && text.length > refuseOver!) return Future.value(0);
    if (refuseContaining != null && text.contains(refuseContaining!)) return Future.value(0);
    spoken.add(text);
    if (!hold) return Future.value(result);
    _gate = Completer<Object?>();
    return _gate!.future;
  }

  void release([Object? r = 1]) {
    final g = _gate;
    _gate = null;
    g?.complete(r);
  }

  @override
  Future<void> stop() async => release(0);

  bool engine = true;
  @override
  Future<bool> engineReady() async => engine;

  /// speak() throws for the first [throwTimes] calls, the way Android's -8 surfaces.
  int throwTimes = 0;
  /// speak() refuses any text longer than this, like an engine with a small input limit.
  int? refuseOver;
  /// speak() refuses any text containing this.
  String? refuseContaining;
}

Narrator _narrator(FakeTts tts, [NarrationStore? store]) =>
    Narrator(() => ApiClient(baseUrl: ''), tts: tts, store: store);

String _long(int sentences) => List.generate(sentences, (i) => 'Sentence number $i is here.').join(' ');

void main() {
  group('chunkSentences', () {
    test('packs sentences up to the limit and never splits one', () {
      final text = _long(300);
      final chunks = chunkSentences(text, max: 1000);
      expect(chunks.length, greaterThan(1));
      for (final c in chunks) {
        expect(c.length, lessThanOrEqualTo(1000));
        expect(c.endsWith('.'), isTrue);
      }
      expect(chunks.join(' '), text);
    });

    test('a 20 minute module (about 18,000 characters) fits chunks under 3,000', () {
      final chunks = chunkSentences(_long(700));
      expect(chunks.every((c) => c.length <= 3000), isTrue);
      expect(chunks.length, greaterThanOrEqualTo(6));
    });

    test('one sentence longer than the limit breaks at a comma or space', () {
      final s = List.generate(80, (i) => 'word$i,').join(' ');
      final chunks = chunkSentences(s, max: 200);
      expect(chunks.every((c) => c.length <= 200), isTrue);
      expect(chunks.length, greaterThan(2));
    });

    test('paragraphs and blank text are handled', () {
      expect(chunkSentences('   '), isEmpty);
      expect(chunkSentences('One.\n\nTwo.'), ['One. Two.']);
    });
  });

  group('BI26101522: what the engine is given', () {
    test('no chunk passes 3,500 characters, even when the caller asks for more', () {
      final s = List.generate(2000, (i) => 'word$i').join(' ');
      final chunks = chunkSentences(s, max: 9000);
      expect(chunks.every((c) => c.length <= maxChunkChars), isTrue);
      expect(chunks.length, greaterThan(1));
    });

    test('empty and whitespace-only passages are dropped', () {
      expect(chunkSentences('\n\n   \n\n'), isEmpty);
      expect(chunkSentences('| | |'), isEmpty);
    });

    test('control characters, lone surrogates and table pipes are removed', () {
      final dirty = 'One\u0000 two\u0007 three \uD800 four | five \u{1F600} six.';
      final clean = cleanForSpeech(dirty);
      expect(clean, isNot(contains('\u0000')));
      expect(clean, isNot(contains('\u0007')));
      expect(clean, isNot(contains('|')));
      expect(clean.codeUnits.contains(0xD800), isFalse);
      expect(clean, contains('\u{1F600}')); // a whole surrogate pair stays
      expect(cleanForSpeech('a\nb\tc'), 'a\nb\tc');
    });
  });

  group('BI26101522: a refused chunk', () {
    test('speak throwing -8 once is split in two and the module still finishes', () async {
      final tts = FakeTts()..throwTimes = 1;
      final n = _narrator(tts);
      await n.speakDevice(course: 'c', file: 'f.md', markdown: 'First half of it here and the second half there.');
      expect(n.state, NarrationState.idle);
      expect(n.error, isNull);
      expect(n.notice, isNull);
      expect(tts.attempts.length, 3); // the whole chunk (refused), then its two halves
      expect(tts.spoken.join(' '), 'First half of it here and the second half there.');
    });

    test('a passage the engine refuses even in halves is skipped, with a note, and the rest is read', () async {
      final tts = FakeTts()..refuseContaining = 'POISON';
      final n = _narrator(tts);
      // Two sentences of about 1,800 characters each make two chunks; the first holds the refused word at
      // both ends, so neither half of it can be read.
      final bad = 'POISON ${List.filled(900, 'a').join(' ')} POISON.';
      final good = '${List.filled(900, 'b').join(' ')}.';
      await n.speakDevice(course: 'c', file: 'f.md', markdown: '$bad $good');
      expect(n.state, NarrationState.idle);
      expect(n.error, isNull);
      expect(n.notice, 'Skipped 1 passage the voice could not read.');
      expect(tts.spoken.length, 1);
      expect(tts.spoken.first, good);
    });

    test('when nothing can be read the message is plain and carries no raw error', () async {
      final tts = FakeTts()..result = 0;
      final n = _narrator(tts);
      await n.speakDevice(course: 'c', file: 'f.md', markdown: 'Hello there.');
      expect(n.error, contains('would not start'));
      expect(n.error, isNot(contains('-8')));
      expect(n.error, isNot(contains('Exception')));
    });

    test('with no engine installed it says how to set one up, and tries again on retry', () async {
      final tts = FakeTts()..engine = false;
      final n = _narrator(tts);
      await n.speakDevice(course: 'c', file: 'f.md', markdown: 'Hello there.');
      expect(n.error, contains('No text-to-speech engine'));
      expect(n.error, contains('Settings'));
      expect(tts.attempts, isEmpty);
      tts.engine = true;
      await n.retry('Hello there.');
      expect(n.error, isNull);
      expect(tts.spoken, ['Hello there.']);
    });
  });

  group('speakable module furniture', () {
    test('front matter, comments, formulas, glossary markers and images', () {
      final s = speakable('---\ntitle: X\nlevel: 3\n---\n'
          'Intro <!-- editor note --> text with \$x^2\$ inline.\n\n'
          '\$\$\\int f\$\$\n\n'
          'A [[ohm|the unit of resistance]] is used. ![A resistor diagram](a.png)\n');
      expect(s, isNot(contains('title:')));
      expect(s, isNot(contains('editor note')));
      expect(s, isNot(contains('x^2')));
      expect(s, contains('(formula)'));
      expect(s, contains('(formula, see screen)'));
      expect(s, contains('A ohm is used.'));
      expect(s, isNot(contains('unit of resistance')));
      expect(s, contains('A resistor diagram'));
      expect(s, isNot(contains('a.png')));
    });

    test('money is not mistaken for a formula', () {
      final s = speakable('It costs \$5 and then \$10 more.');
      expect(s, 'It costs \$5 and then \$10 more.');
    });
  });

  group('pickVoice', () {
    final voices = [
      {'name': 'en-us-x-a', 'locale': 'en-US', 'network_required': '0', 'quality': 'high'},
      {'name': 'en-gb-net', 'locale': 'en-GB', 'network_required': '1', 'quality': 'very high'},
      {'name': 'en-gb-low', 'locale': 'en_GB', 'network_required': '0', 'quality': 'normal'},
      {'name': 'en-gb-hi', 'locale': 'en-GB', 'network_required': '0', 'quality': 'very high'},
    ];

    test('prefers British English on the device, best quality, never a network voice', () {
      expect(Narrator.pickVoice(voices)!['name'], 'en-gb-hi');
    });

    test('falls back to any local English voice, then to none', () {
      expect(Narrator.pickVoice([voices[0], voices[1]])!['name'], 'en-us-x-a');
      expect(Narrator.pickVoice([voices[1]]), isNull);
      expect(Narrator.pickVoice([]), isNull);
    });
  });

  group('Narrator device tier', () {
    test('speaks a long module chunk by chunk, in order, then goes idle', () async {
      final tts = FakeTts();
      final n = _narrator(tts);
      final md = _long(700);
      await n.speakDevice(course: 'c', file: 'f.md', markdown: md);
      expect(tts.spoken.length, greaterThanOrEqualTo(6));
      expect(tts.spoken.every((c) => c.length <= 3000), isTrue);
      expect(tts.spoken.join(' '), md);
      expect(n.state, NarrationState.idle);
      expect(n.error, isNull);
    });

    test('a refused speak shows a message and keeps the module for a retry', () async {
      final tts = FakeTts()..result = 0;
      final n = _narrator(tts);
      await n.speakDevice(course: 'c', file: 'f.md', markdown: 'Hello there.');
      expect(n.error, contains('would not start'));
      expect(n.state, NarrationState.idle);
      expect(n.current, 'c/f.md');
      tts.result = 1;
      await n.retry('Hello there.');
      expect(n.error, isNull);
    });

    test('pause stops the engine and keeps the place, resume carries on from it', () async {
      final tts = FakeTts()..hold = true;
      final n = _narrator(tts);
      final md = _long(700);
      unawaited(n.speakDevice(course: 'c', file: 'f.md', markdown: md));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(tts.spoken.length, 1);
      tts.release(); // chunk 0 finished, chunk 1 starts
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(tts.spoken.length, 2);
      await n.pause();
      expect(n.state, NarrationState.paused);
      expect(n.chunkIndex, 1);
      final before = tts.spoken.length;
      await n.resume();
      await Future<void>.delayed(Duration.zero);
      expect(tts.spoken.length, before + 1);
      expect(tts.spoken.last, tts.spoken[1]); // the paused chunk is read again from its start
      await n.stop();
    });

    test('skip moves a chunk and the position survives a restart', () async {
      final store = MemoryNarrationStore();
      final tts = FakeTts()..hold = true;
      final n = _narrator(tts, store);
      final md = _long(700);
      unawaited(n.speakDevice(course: 'c', file: 'f.md', markdown: md));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await n.skip(2);
      await Future<void>.delayed(Duration.zero);
      expect(n.chunkIndex, 2);
      await Future<void>.delayed(Duration.zero);
      await n.skip(-1);
      await Future<void>.delayed(Duration.zero);
      expect(n.chunkIndex, 1);
      // A new narrator (the app restarted) resumes from the saved chunk.
      final tts2 = FakeTts();
      final n2 = _narrator(tts2, store);
      await n2.speakDevice(course: 'c', file: 'f.md', markdown: md);
      final chunks = chunkSentences(speakable(md));
      expect(tts2.spoken.first, chunks[1]);
    });

    test('chooses the best offline voice and remembers a manual choice', () async {
      final store = MemoryNarrationStore();
      final tts = FakeTts()
        ..voiceList = [
          {'name': 'en-gb-hi', 'locale': 'en-GB', 'network_required': '0', 'quality': 'very high'},
          {'name': 'en-gb-other', 'locale': 'en-GB', 'network_required': '0', 'quality': 'normal'},
        ];
      final n = _narrator(tts, store);
      await n.speakDevice(course: 'c', file: 'f.md', markdown: 'Short.');
      expect(tts.setTo!['name'], 'en-gb-hi');
      expect(n.needsVoiceData, isFalse);
      await n.chooseVoice(tts.voiceList[1]);
      final n2 = _narrator(tts, store);
      await n2.speakDevice(course: 'c', file: 'g.md', markdown: 'Short.');
      expect(tts.setTo!['name'], 'en-gb-other');
    });

    test('with only a network voice, the bar is told to explain voice data', () async {
      final tts = FakeTts()
        ..voiceList = [
          {'name': 'net', 'locale': 'en-GB', 'network_required': '1'},
        ];
      final n = _narrator(tts);
      await n.speakDevice(course: 'c', file: 'f.md', markdown: 'Short.');
      expect(n.needsVoiceData, isTrue);
    });
  });
}
