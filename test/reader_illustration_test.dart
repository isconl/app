import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/util/markdown.dart';

const _head = '''---
archetype: Clinical
version: 4.8.0
---

# A module

## {orient} Body Primer: The Body Mapped

**{prior} Before This:** none.

''';

Future<void> _pump(WidgetTester t, String body) async {
  await t.pumpWidget(MaterialApp(
      home: Scaffold(
          body: SingleChildScrollView(child: Markdown('$_head## {see} Misread Scene: The Scene\n\n$body', variant: MarkdownVariant.reading)))));
  await t.pump();
}

String _rendered(WidgetTester t) => t
    .widgetList<RichText>(find.byType(RichText))
    .map((r) => r.text.toPlainText())
    .join('\n');

String? _label(WidgetTester t) => t.widget<Text>(find.byKey(const Key('callout-label')).last).data;

void main() {
  group('PI26103090: splitIllustrationCopy, every opening the library holds', () {
    const cases = {
      'ILLUSTRATION. A patient arrives.': ('', 'A patient arrives.'),
      'ILLUSTRATION. All names and details are invented. A patient arrives.': ('All names and details are invented.', 'A patient arrives.'),
      'All names are invented. A patient arrives.': ('All names are invented.', 'A patient arrives.'),
      'ILLUSTRATION, an invented case. A patient arrives.': ('An invented case.', 'A patient arrives.'),
      'ILLUSTRATION, with invented figures. Two founders.': ('With invented figures.', 'Two founders.'),
      'Invented figures, headed ILLUSTRATION. Two founders.': ('Invented figures.', 'Two founders.'),
      'A boat and a current, with invented figures, headed ILLUSTRATION. It drifts.': ('A boat and a current, with invented figures.', 'It drifts.'),
      '_Invented case, real names not used._ A patient arrives.': ('Invented case, real names not used.', 'A patient arrives.'),
      'A patient arrives breathing fast. Nothing else is said.': ('', 'A patient arrives breathing fast. Nothing else is said.'),
      'Ten salaries (ILLUSTRATION, invented): 60 and 65.': ('', 'Ten salaries (invented): 60 and 65.'),
    };
    cases.forEach((raw, want) {
      test(raw, () {
        final got = splitIllustrationCopy(raw);
        expect(got.note, want.$1);
        expect(got.text, want.$2);
      });
    });

    test('a callout that is only a disclosure keeps it as the copy', () {
      expect(splitIllustrationCopy('All names are invented.').text, 'All names are invented.');
    });
  });

  group('PI26103090: the sort in the header', () {
    test('a standard label is taken as written', () {
      expect(illustrationKindFor('Case Study', '', ''), 'CASE STUDY');
      expect(illustrationKindFor('Worked Example', '', ''), 'WORKED EXAMPLE');
      expect(illustrationKindFor('Real Story', '', ''), 'STORY');
    });
    test('an older label or bracket is read for a telling word', () {
      expect(illustrationKindFor('Misread Story', '', ''), 'STORY');
      expect(illustrationKindFor('', 'worked, hypothetical numbers', ''), 'WORKED EXAMPLE');
      expect(illustrationKindFor('', 'fictional composite', ''), 'STORY');
    });
    test('with nothing to go on, the copy decides', () {
      expect(illustrationKindFor('Dusk Path', '', 'A patient arrives.'), 'CASE STUDY');
      expect(illustrationKindFor('Dusk Path', '', 'Stand outside at dusk and look west.'), 'EXAMPLE');
    });
  });

  group('PI26103090: as drawn', () {
    testWidgets('the eleven systems: no ILLUSTRATION in the copy, the sort in the header', (t) async {
      await _pump(t, '**{illustration} Misread Story:** ILLUSTRATION. A patient arrives breathing fast.\n');
      expect(_label(t), contains('ILLUSTRATION · STORY'));
      expect(_rendered(t), contains('A patient arrives breathing fast.'));
      expect(_rendered(t), isNot(contains('ILLUSTRATION.')));
    });

    testWidgets('the disclosure is a small note above the copy, not part of it', (t) async {
      await _pump(t, '**{illustration} Invented Case:** ILLUSTRATION. All names and details are invented. Wanjiru is 58.\n');
      expect(find.byKey(const Key('callout-note')), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const Key('callout-note'))).data, 'All names and details are invented.');
      final note = t.widget<Text>(find.byKey(const Key('callout-note')));
      expect(note.style!.fontSize, lessThan(13));
      expect(_label(t), contains('CASE STUDY'));
    });

    testWidgets('a hard-wrapped callout stays whole in the box', (t) async {
      await _pump(t, '**{illustration} Founders Story:** ILLUSTRATION. All numbers here are invented to show the\narithmetic. Two founders each bring in \$1,000,000 of revenue\nthis year.\n\nCommentary sits outside the box.\n');
      final box = find.ancestor(of: find.byKey(const Key('callout-note')), matching: find.byType(Column)).first;
      final inBox = find.descendant(of: box, matching: find.byType(RichText));
      final text = t.widgetList<RichText>(inBox).map((r) => r.text.toPlainText()).join(' ');
      expect(text, contains('Two founders each bring in \$1,000,000 of revenue this year.'));
      expect(text, isNot(contains('Commentary')));
      expect(_rendered(t), contains('Commentary sits outside the box.'));
      expect(t.widget<Text>(find.byKey(const Key('callout-note'))).data, 'All numbers here are invented to show the arithmetic.');
    });

    testWidgets('the older bracket marker, wrapped or not, is a real callout', (t) async {
      await _pump(t, '**Illustration (worked, hypothetical numbers, consistent with module 0\'s\nown invented example):** forty phones, each drawing power.\n');
      expect(_rendered(t), isNot(contains('**')));
      expect(_rendered(t), contains('Forty phones, each drawing power.'));
      expect(_label(t), contains('WORKED EXAMPLE'));
      expect(t.widget<Text>(find.byKey(const Key('callout-note'))).data, contains('hypothetical numbers'));
    });

    testWidgets('a demoted illustration keeps its disclosure, in front of the copy', (t) async {
      await _pump(t, '**{research} First One:** Comes first, so it is the callout.\n\n**{illustration} Case Study:** ILLUSTRATION. All names are invented. Wanjiru is 58.\n');
      expect(_rendered(t), contains('All names are invented. Wanjiru is 58.'));
      expect(_rendered(t), isNot(contains('ILLUSTRATION.')));
    });

    test('a figure that fails says why', () {
      expect(figureFailureReason(Exception('HttpExceptionWithStatus: 404 url')), contains('sign out and back in'));
      expect(figureFailureReason(Exception('Invalid statusCode: 530')), contains('HTTP 530'));
      expect(figureFailureReason(Exception('SocketException')), contains('connection'));
    });

    test('a stored error page is not taken for an SVG', () {
      expect(looksLikeSvg('<?xml version="1.0"?><svg viewBox="0 0 1 1"/>'.codeUnits), isTrue);
      expect(looksLikeSvg('{"error":"Not Found"}'.codeUnits), isFalse);
      expect(looksLikeSvg('<!doctype html><html></html>'.codeUnits), isFalse);
    });

    testWidgets('a table after the callout stays out of the box and is still drawn', (t) async {
      await _pump(t, '**{illustration} Mode Table:** The beds swap.\n| Step | Bed A |\n|---|---|\n| 1 | On |\n');
      expect(_rendered(t), contains('The beds swap.'));
      expect(_rendered(t), isNot(contains('| Step')));
    });
  });
}
