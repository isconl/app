import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/services/narration.dart';
import 'package:isconl/util/fmt.dart' as fmt;

/// speakable() is duplicated in Dart and in the agent's lib/voice.js, because the
/// device tier has to work with no signal and an offline feature cannot ask a
/// server what to say. Duplication that must agree needs tests on both sides;
/// these are this side's.
void main() {
  group('speakable', () {
    test('headings become sentences, not announced syntax', () {
      final s = speakable('# The directive\n\nBody text here.');
      expect(s, contains('The directive.'));
      expect(s, isNot(contains('#')));
    });

    test('emphasis and inline code lose their marks but keep their words', () {
      final s = speakable('Some **bold** and *italic* and `code` here.');
      expect(s, 'Some bold and italic and code here.');
    });

    test('links keep the text and drop the URL', () {
      final s = speakable('See [the register](https://example.com/x) for detail.');
      expect(s, 'See the register for detail.');
      expect(s, isNot(contains('http')));
    });

    // Reading Kotlin aloud is worse than acknowledging it exists.
    test('code blocks are skipped and acknowledged', () {
      final s = speakable('Before.\n\n```\nfn main() {}\n```\n\nAfter.');
      expect(s, contains('Before.'));
      expect(s, contains('After.'));
      expect(s, isNot(contains('fn main')));
      expect(s, contains('1 code block'));
      expect(s, contains('not read aloud'));
    });

    // A table narrated row-major is actively misleading, so it is skipped - but
    // never silently, or the listener does not know something was there.
    test('tables are skipped and acknowledged', () {
      final s = speakable('Intro.\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\nOutro.');
      expect(s, contains('Intro.'));
      expect(s, contains('Outro.'));
      expect(s, isNot(contains('|')));
      expect(s, contains('1 table'));
    });

    test('both skips are counted together', () {
      final s = speakable('```\nx\n```\n\n| a |\n|---|\n| 1 |\n');
      expect(s, contains('1 code block and 1 table'));
    });

    test('list markers and blockquote carets go', () {
      final s = speakable('- first\n- second\n\n> quoted line');
      expect(s, isNot(contains('- ')));
      expect(s, isNot(contains('>')));
      expect(s, contains('first'));
      expect(s, contains('quoted line'));
    });

    test('horizontal rules do not become spoken dashes', () {
      final s = speakable('One.\n\n---\n\nTwo.');
      expect(s, isNot(contains('---')));
      expect(s, contains('One.'));
      expect(s, contains('Two.'));
    });

    test('empty input yields nothing to speak', () {
      expect(speakable('').trim(), isEmpty);
      expect(speakable('   \n\n  ').trim(), isEmpty);
    });

    test('a module with only a table still says what it held', () {
      final s = speakable('| a | b |\n|---|---|\n| 1 | 2 |');
      expect(s, contains('1 table'));
    });
  });

  group('clock', () {
    test('drops the hour until there is one', () {
      expect(fmt.clock(const Duration(seconds: 9)), '0:09');
      expect(fmt.clock(const Duration(minutes: 9, seconds: 5)), '9:05');
      expect(fmt.clock(const Duration(minutes: 59, seconds: 59)), '59:59');
      expect(fmt.clock(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
    });
  });

  group('Narrator keys', () {
    test('the key matches the module library so state lines up', () {
      expect(Narrator.key('viva-tasks', '16-module.md'), 'viva-tasks/16-module.md');
    });
  });
}
