import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/services/narration.dart';
import 'package:isconl/services/narration_script.dart';
import 'package:isconl/study/cdm/cdm_model.dart';
import 'package:isconl/study/cdm/cdm_speech.dart';

/// BI26101394: the device voice reads a whole module offline. Android refuses an utterance over 4000
/// characters, so the script is spoken in chunks of whole sentences, and nothing a listener should not hear
/// reaches the engine.
void main() {
  final module = File('test/fixtures/narration_module_looking_up.md').readAsStringSync();

  group('speakable on a real module', () {
    final s = speakable(module);

    test('the front matter is not read', () {
      expect(s, isNot(contains('archetype:')));
      expect(s, isNot(contains('course: astro-sky-cosmos')));
      expect(s.startsWith('Looking Up Properly.'), isTrue);
    });

    test('movement keys are labels for the eye; the heading title is what is said', () {
      expect(s, contains('Sky As Sphere.'));
      expect(s, isNot(contains('ORIENT')));
      expect(s, isNot(contains('·')));
    });

    test('an activity fence is announced as an activity, not as code', () {
      expect(s, isNot(contains('phyphox.org')));
      expect(s, contains('1 activity'));
      expect(s, isNot(contains('code block')));
    });

    test('no markdown markup reaches the voice', () {
      for (final mark in ['**', '##', '```', '](', '|---']) {
        expect(s, isNot(contains(mark)), reason: mark);
      }
    });
  });

  group('speakable on what 4.4.0 modules carry', () {
    test('a glossary term says just the term', () {
      expect(speakable('A [[sidereal day|the time to turn once against the stars|astronomy]] is short.'),
          'A sidereal day is short.');
    });

    test('LaTeX is pointed at, a plain inline formula is said', () {
      final s = speakable(r'Energy is $E = mc^2$ here, and $x + y$ there.'
          '\n\n'
          r'$$\int_0^1 x\,dx$$');
      expect(s, contains('(formula, see screen)'));
      expect(s, contains('x + y'));
      expect(s, isNot(contains(r'\int')));
      expect(s, isNot(contains(r'$')));
    });

    test('prices with a dollar sign are not mistaken for a formula', () {
      expect(speakable(r'It costs $5 and $10 later.'), r'It costs $5 and $10 later.');
    });

    test('an image says its alt text, comments and tags say nothing', () {
      final s = speakable('Before.\n\n![The Moon at first quarter](_assets/moon.png)\n\n<!-- author note -->'
          '\n\n<details>Hidden</details> After.');
      expect(s, contains('Image: The Moon at first quarter.'));
      expect(s, isNot(contains('author note')));
      expect(s, isNot(contains('<details>')));
      expect(s, isNot(contains('_assets')));
    });
  });

  group('NarrationScript', () {
    final script = NarrationScript(speakable(module));

    test('every chunk is whole sentences and under the limit, and together they are the whole module', () {
      var i = 0;
      final spoken = <String>[];
      while (i < script.length) {
        final c = script.chunkAt(i);
        expect(c.text.length, lessThanOrEqualTo(kMaxChunkChars));
        expect(c.next, greaterThan(i));
        spoken.add(c.text);
        i = c.next;
      }
      expect(spoken.join(' '), script.sentences.join(' '));
      expect(spoken.length, greaterThan(1), reason: 'a 12 KB module needs several chunks');
    });

    test('sentences end at a full stop with a space and at a paragraph break', () {
      final s = NarrationScript('One. Two? Three!\n\nFour (aside). "Five." Six');
      expect(s.sentences, ['One.', 'Two?', 'Three!', 'Four (aside).', '"Five."', 'Six']);
    });

    test('a sentence longer than the limit is split at a comma rather than mid-word', () {
      final long = List.generate(400, (i) => 'word$i,').join(' ');
      final s = NarrationScript(long);
      expect(s.sentences.every((x) => x.length <= kMaxChunkChars), isTrue);
      expect(s.sentences.first.endsWith(','), isTrue);
      expect(s.sentences.join(' '), long);
    });

    test('the progress offset maps back to the sentence being heard', () {
      final s = NarrationScript('Alpha one. Beta two. Gamma three.');
      final c = s.chunkAt(0).text;
      expect(s.sentenceAtOffset(0, c.indexOf('Alpha')), 0);
      expect(s.sentenceAtOffset(0, c.indexOf('Beta')), 1);
      expect(s.sentenceAtOffset(0, c.indexOf('three')), 2);
      expect(s.sentenceAtOffset(1, 0), 1, reason: 'offsets count from the chunk start');
    });

    test('the timeline is estimated from words and skips land on sentences', () {
      // 30 sentences of 10 words: 300 words, two minutes at 150 words a minute.
      final s = NarrationScript(List.generate(30, (i) => 'one two three four five six seven eight nine ten.')
          .join(' '));
      expect(s.durationAt(1.0), const Duration(minutes: 2));
      expect(s.durationAt(2.0), const Duration(minutes: 1));
      expect(s.positionOf(15, 1.0), const Duration(minutes: 1));
      expect(s.skip(0, 30, 1.0), 7, reason: '75 words in: sentence 7 holds word 75');
      expect(s.skip(7, -30, 1.0), 0);
      expect(s.skip(0, -30, 1.0), 0);
      expect(s.skip(25, 60, 1.0), 30, reason: 'past the end');
    });
  });

  group('chooseVoice', () {
    final voices = [
      {'name': 'en-us-x-net', 'locale': 'en-US', 'quality': '500', 'network_required': '1'},
      {'name': 'en-us-x-local', 'locale': 'en-US', 'quality': '400', 'network_required': '0'},
      {'name': 'en-gb-x-local', 'locale': 'en-GB', 'quality': '300', 'network_required': '0'},
      {'name': 'sw-ke-x-local', 'locale': 'sw-KE', 'quality': '500', 'network_required': '0'},
    ];

    test('British English on the phone first, never a network voice', () {
      expect(chooseVoice(voices)!['name'], 'en-gb-x-local');
    });

    test('the saved choice wins while it is installed and local', () {
      expect(chooseVoice(voices, saved: 'en-us-x-local')!['name'], 'en-us-x-local');
      expect(chooseVoice(voices, saved: 'en-us-x-net')!['name'], 'en-gb-x-local');
    });

    test('no English voice on the phone means none is chosen, so the bar can say so', () {
      expect(chooseVoice([voices[0], voices[3]]), isNull);
    });
  });

  test('a document-only module reads its blocks, not its author notes', () {
    final doc = CdmDoc.fromJson({
      'ddm': '1',
      'headline': 'Looking Up',
      'sections': [
        {'type': 'heading', 'level': 2, 'text': 'Two angles'},
        {'type': 'paragraph', 'text': 'Altitude and azimuth place a star.'},
        {'type': 'callout', 'kind': 'story', 'title': 'Story', 'text': 'Hold out your fist.'},
        {'type': 'bullets', 'items': ['Fist, ten degrees.', 'Span, twenty degrees.']},
        {'type': 'equation', 'tex': r'\theta = 2\arctan(w/2d)'},
        {'type': 'truth_check', 'claim': 'secret'},
        {
          'type': 'audience',
          'aud': ['author'],
          'nodes': [
            {'type': 'paragraph', 'text': 'Only for the author.'}
          ]
        },
        {'type': 'table', 'header': ['a', 'b'], 'rows': [['1', '2']]},
      ],
    });
    final s = speakable(cdmSpeakableMarkdown(doc));
    expect(s, startsWith('Looking Up.'));
    expect(s, contains('Two angles.'));
    expect(s, contains('Story. Hold out your fist.'));
    expect(s, contains('Span, twenty degrees.'));
    expect(s, contains('(formula, see screen)'));
    expect(s, contains('1 table'));
    expect(s, isNot(contains('Only for the author')));
    expect(s, isNot(contains('secret')));
    expect(s, isNot(contains(r'\theta')));
  });
}
