// BI26101804 items 8 and 9: section 0's prerequisite, objective and "where this fits", and probe answers behind a
// Reveal answer button. CI26101803 retags the content with `prerequisite`, `objective`, `aside` and `answer`.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/util/markdown.dart';

const _v4 = '''## {orient} Setting Out: Where This Module Begins

**{prior} Before This:** Module zero sets the scene.
**{outcome} Your Goals:** You can name the five parts.
**{place} Course Map:** Module 1 of 5 in the viva course.

## {grasp} The Core: One Idea Carries Everything

**{illustration} Lost Booking:** A mandate arrives late and nobody owns it.
''';

const _old = '''# Compounding

**Prior:** Module 01 on mindset.

**You will be able to:** calculate how small rate differences compound.

**Where this fits:** `finance`, module 02 of 08.

---

## The 10-second answer

Compounding is interest earning interest.
''';

const _tagged = '''## {orient} Setting Out: Where This Module Begins

**{prerequisite} Before This:** Module zero.
**{objective} Your Goal:** Name the five parts.
**{aside} Where Next:** Module two follows.
''';

const _probe = '''## {grasp} The Core: One Idea

**{probe} Check It:** Why does the mandate stall?

**{answer} Model Reply:** Nobody owns the handover.

A plain paragraph after.
''';

const _probeOld = '''## GRASP · The Core

**Probe:** Why does it stall?

**Answer:** Nobody owns it.
''';

Future<void> _pump(WidgetTester t, String src) async {
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(child: Markdown(src, variant: MarkdownVariant.reading)),
    ),
  ));
}

String _text(WidgetTester t) =>
    t.widgetList<RichText>(find.byType(RichText)).map((r) => r.text.toPlainText()).join('\n').toLowerCase();

List<String?> _labels(WidgetTester t) => t.widgetList<Text>(find.byKey(const Key('callout-label'))).map((x) => x.data).toList();

void main() {
  group('BI26101804: section 0', () {
    testWidgets('a 4.x module: the prerequisite is an italic line, the objective is the one callout, the place is a small aside', (t) async {
      await _pump(t, _v4);
      expect(find.byKey(const Key('prerequisite-line')), findsOneWidget);
      final line = t.widget<Text>(find.descendant(of: find.byKey(const Key('prerequisite-line')), matching: find.byType(Text)));
      final root = line.textSpan as TextSpan;
      final label = root.children!.first as TextSpan;
      expect(label.text!.trim(), 'Prerequisite');
      expect(label.style!.fontWeight, FontWeight.w700);
      expect(label.style!.fontStyle, FontStyle.italic);
      expect(_text(t), contains('module zero sets the scene'));

      expect(find.byKey(const Key('objective-callout')), findsOneWidget);
      expect(_labels(t).first, contains('OBJECTIVE'));

      final aside = find.byKey(const Key('where-this-fits'));
      expect(aside, findsOneWidget);
      final asideText = t.widget<Text>(find.descendant(of: aside, matching: find.byType(Text)));
      final asideSpan = (asideText.textSpan as TextSpan).children!.last as TextSpan;
      expect(asideSpan.style!.fontSize, lessThan(12), reason: 'tiny');
      // the aside has no box of its own
      expect(find.descendant(of: aside, matching: find.byType(DecoratedBox)), findsNothing);

      // exactly one callout in section 0 (the objective); the illustration in section 1 is its own section's
      expect(_labels(t).where((l) => l!.contains('OBJECTIVE')).length, 1);
      expect(_labels(t).where((l) => l!.contains('NOTE')).length, 0);
    });

    testWidgets('an older module without tags is drawn the same way, found by its labels', (t) async {
      await _pump(t, _old);
      expect(find.byKey(const Key('prerequisite-line')), findsOneWidget);
      expect(find.byKey(const Key('objective-callout')), findsOneWidget);
      expect(find.byKey(const Key('where-this-fits')), findsOneWidget);
      expect(_text(t), contains('module 01 on mindset'));
      expect(_text(t), isNot(contains('**')));
    });

    testWidgets('content carrying the new tags is drawn the same way', (t) async {
      await _pump(t, _tagged);
      expect(find.byKey(const Key('prerequisite-line')), findsOneWidget);
      expect(find.byKey(const Key('objective-callout')), findsOneWidget);
      expect(find.byKey(const Key('where-this-fits')), findsOneWidget);
    });

    testWidgets('the objective callout is the most prominent: thicker strip than an ordinary callout', (t) async {
      await _pump(t, '$_v4\n**{illustration} Another One:** More.\n');
      final obj = t.widget<Container>(find.byKey(const Key('objective-callout')));
      final deco = obj.decoration as BoxDecoration;
      expect((deco.border as Border).left.width, 5);
    });
  });

  group('BI26101804: probe answers', () {
    for (final entry in {'4.x': _probe, 'older': _probeOld}.entries) {
      testWidgets('${entry.key}: the answer is hidden behind Reveal answer, opens in place and folds again', (t) async {
        await _pump(t, entry.value);
        final reveal = find.byKey(const Key('reveal-answer'));
        expect(reveal, findsOneWidget);
        expect(find.text('Reveal answer'), findsOneWidget);
        expect(_text(t), contains('mandate stall').or(contains('why does it stall')));
        expect(_text(t), isNot(contains('nobody owns')));
        expect(_labels(t).any((l) => l!.contains('ANSWER')), isFalse, reason: 'never a second callout');

        await t.tap(reveal);
        await t.pumpAndSettle();
        expect(_text(t), contains('nobody owns'));
        expect(_labels(t).any((l) => l!.contains('ANSWER')), isTrue);
        expect(find.text('Hide answer'), findsOneWidget);

        await t.tap(reveal);
        await t.pumpAndSettle();
        expect(_text(t), isNot(contains('nobody owns')));
        expect(find.text('Reveal answer'), findsOneWidget);
      });
    }

    testWidgets('an answer that does not follow a probe is still hidden behind its own button', (t) async {
      await _pump(t, '## {grasp} The Core: One Idea\n\nA paragraph.\n\n**{answer} Model Reply:** Nobody owns it.\n');
      expect(find.byKey(const Key('reveal-answer')), findsOneWidget);
      expect(_text(t), isNot(contains('nobody owns')));
    });

    testWidgets('a module with no probe answer has no Reveal button', (t) async {
      await _pump(t, _v4);
      expect(find.byKey(const Key('reveal-answer')), findsNothing);
    });
  });
}

extension on Matcher {
  Matcher or(Matcher other) => anyOf(this, other);
}
