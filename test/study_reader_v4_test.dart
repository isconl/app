// BI26100537: the study reader for course standards 4.x (numbered sections, two-word labels, the
// Illustration callout, section anchors and deep links). A 3.1.0 module must still render.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/util/markdown.dart';

const _v4 = '''---
title: The worked example
---
## {orient} Setting Out: Where This Module Begins

**{prior} Before This:** Module zero sets the scene.
**{outcome} Your Goals:** You can name the five parts.

## {grasp} The Core: One Idea Carries Everything

**{illustration} Lost Booking:** A mandate arrives late and nobody owns it.

A plain paragraph of the module follows here.

## {apply} Run It: Do It This Week

1. **{now} Two Minutes:** Write one line.
2. **{week} This Week:** Ship it.
''';

const _v31 = '''## ORIENT · Where You Stand

**Prior:** Module zero.

**Story:** A mandate arrives late.

## GRASP · The Core Idea

Some prose.
''';

Future<void> _pump(WidgetTester t, String src, {MarkdownAnchors? anchors, void Function(ModuleLink)? onLink}) async {
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: Markdown(src, variant: MarkdownVariant.reading, anchors: anchors, onModuleLink: onLink),
      ),
    ),
  ));
}

/// Every piece of text on screen, including rich text, lowercased.
String _allText(WidgetTester t) =>
    t.widgetList<RichText>(find.byType(RichText)).map((r) => r.text.toPlainText()).join('\n').toLowerCase();

void main() {
  group('BI26100537: standard 4.x reader', () {
    testWidgets('sections are numbered from 0 as k.0 with their two-word label, and no canonical id shows', (t) async {
      await _pump(t, _v4);
      final eyebrows = t.widgetList<Text>(find.byKey(const Key('movement-eyebrow'))).map((x) => x.data).toList();
      // BI26101106: the two-word label is gone from headings; only the computed number stays.
      expect(eyebrows, ['0.0', '1.0', '2.0']);
      expect(find.text('Setting Out'), findsNothing);
      expect(find.textContaining('Where This Module Begins', findRichText: true), findsOneWidget);
      final text = _allText(t);
      for (final id in ['orient', 'grasp', 'apply', '{', '}']) {
        expect(text.contains(id), isFalse, reason: 'the canonical id or its braces showed: $id');
      }
    });

    testWidgets('one callout per section: the first element, numbered k.j, with its kind name, not its authored label', (t) async {
      await _pump(t, _v4);
      final labels = t.widgetList<Text>(find.byKey(const Key('callout-label'))).map((x) => x.data).toList();
      // BI26101804: section 0's callout is its objective (the prior line is a plain italic prerequisite).
      // BI26102804: APPLY's rungs are a numbered ladder, not a Note box.
      expect(labels, ['0.2  OBJECTIVE', '1.1  ILLUSTRATION']);
      expect(find.textContaining('A mandate arrives late', findRichText: true), findsOneWidget);
      // The demoted elements are still read, as prose, with no label.
      expect(find.textContaining('You can name the five parts.', findRichText: true), findsOneWidget);
      expect(find.textContaining('Ship it.', findRichText: true), findsOneWidget);
      final text = _allText(t);
      // BI26102804: a rung shows its two-word label in bold ("Two Minutes"), so it is no longer in this list.
      for (final label in ['your goals', 'before this']) {
        expect(text.contains(label), isFalse, reason: 'an authored element label showed: $label');
      }
    });

    testWidgets('the element marked {id!} is the callout, not the first one', (t) async {
      await _pump(t, _v4.replaceFirst('{outcome}', '{outcome!}'));
      final labels = t.widgetList<Text>(find.byKey(const Key('callout-label'))).map((x) => x.data).toList();
      expect(labels.first, '0.2  OBJECTIVE');
      expect(labels, hasLength(2));
    });

    testWidgets('the blue callout is labelled Illustration when no label is authored', (t) async {
      await _pump(t, _v31);
      final labels = t.widgetList<Text>(find.byKey(const Key('callout-label'))).map((x) => x.data).toList();
      expect(labels, contains('ILLUSTRATION'));
      expect(labels.any((l) => l!.contains('STORY')), isFalse);
    });

    testWidgets('a 3.1.0 module still renders: its headings stay, numbered, and nothing breaks', (t) async {
      await _pump(t, _v31);
      expect(find.textContaining('ORIENT · Where You Stand', findRichText: true), findsOneWidget);
      final eyebrows = t.widgetList<Text>(find.byKey(const Key('movement-eyebrow'))).map((x) => x.data).toList();
      expect(eyebrows, ['0.0', '1.0']);
    });

    test('numbers and anchors come from reading order, and an omitted movement closes the gap', () {
      final s = moduleSections(_v4);
      expect([for (final x in s) x.number], ['0.0', '0.1', '0.2', '1.0', '1.1', '2.0', '2.1', '2.2']);
      expect([for (final x in s) x.anchor], [
        'orient-0', 'prior-0-1', 'outcome-0-2', 'grasp-1', 'illustration-1-1', 'apply-2', 'now-2-1', 'week-2-2',
      ]);
      // With GRASP omitted, APPLY is 1, not 2: links resolve from the real order.
      final omitted = moduleSections(_v4.replaceAll(RegExp(r'## \{grasp\}[\s\S]*?(?=## \{apply\})'), ''));
      expect(omitted.map((x) => x.anchor), contains('apply-1'));
      expect(omitted.map((x) => x.anchor), isNot(contains('apply-2')));
    });

    test('module links name a module, and optionally a section; a course-index link does not parse', () {
      final a = ModuleLink.parse('module:viva-swen-vision/01#build-3')!;
      expect((a.course, a.index, a.anchor), ('viva-swen-vision', '01', 'build-3'));
      expect(ModuleLink.parse('module:viva-swen-vision/01')!.anchor, '');
      expect(ModuleLink.parse('module:viva-swen-vision'), isNull, reason: 'a course-index link is a defect');
      expect(ModuleLink.parse('https://example.com'), isNull);
      expect(ModuleLink.parse('module:../x/01'), isNull);
    });

    testWidgets('tapping a module link calls the handler with that exact module and section', (t) async {
      ModuleLink? tapped;
      await _pump(t, 'See [[link:the spine|module:viva-swen-vision/01#grasp-1]] for more.', onLink: (l) => tapped = l);
      final rich = t.widget<RichText>(find.byType(RichText).first);
      final span = _findSpan(rich.text, 'the spine')!;
      (span.recognizer as dynamic).onTap();
      expect(tapped.toString(), 'module:viva-swen-vision/01#grasp-1');
    });

    testWidgets('a section anchor scrolls to its section and highlights it briefly', (t) async {
      final anchors = MarkdownAnchors();
      final long = '$_v4\n\n${List.filled(60, 'Padding line to make the module scroll.\n').join('\n')}';
      await _pump(t, long, anchors: anchors);
      expect(anchors.hasAnchor('week-2-2'), isTrue);
      expect(anchors.hasAnchor('week-9-9'), isFalse);
      expect(anchors.revealAnchor('week-9-9'), isFalse);
      expect(anchors.revealAnchor('week-2-2'), isTrue);
      expect(anchors.highlighted.value, isNotNull);
      await t.pump(const Duration(seconds: 2));
      expect(anchors.highlighted.value, isNull, reason: 'the highlight is brief');
    });
  });

  group('BI26102803: GUARD movement 5', () {
    const guardSnippet = '''## {guard} Misreading Risk: Where The Numbers Mislead

**{failure} Core Failure:** The primary failure mode that kills the initiative.
**{failure} Second Mistake:** Giving away ownership cheaply before traction.
**{failure} Third Mistake:** Starving the core engine of cash.

**{pitfalls} Common Pitfalls:**
- **Calling a job an asset.** A business that stops when you stop.
- **Copying someone else's split.** Borrowed percentages are guesses.
''';

    testWidgets('a GUARD section with three failure lines and a pitfalls list renders one callout, one subheading, and a numbered list carrying every remaining item in order', (t) async {
      await _pump(t, guardSnippet);

      // 1. Exactly one callout rendered (the core failure)
      final calloutLabels = t.widgetList<Text>(find.byKey(const Key('callout-label'))).map((x) => x.data).toList();
      expect(calloutLabels, hasLength(1));
      expect(calloutLabels.first, contains('FAILURE'));
      expect(find.textContaining('The primary failure mode that kills the initiative', findRichText: true), findsOneWidget);

      // 2. Exactly one subheading (from pitfalls two-word label)
      expect(find.text('Common Pitfalls'), findsOneWidget);

      // 3. Numbered list carrying remaining failures and pitfall items in order (1 to 4)
      expect(find.text('1.'), findsOneWidget);
      expect(find.text('2.'), findsOneWidget);
      expect(find.text('3.'), findsOneWidget);
      expect(find.text('4.'), findsOneWidget);
      expect(find.text('5.'), findsNothing);

      // Verify each item opened with its two-word label in bold
      expect(find.textContaining('Second Mistake', findRichText: true), findsOneWidget);
      expect(find.textContaining('Third Mistake', findRichText: true), findsOneWidget);
      expect(find.textContaining('Calling a job an asset.', findRichText: true), findsOneWidget);
      expect(find.textContaining("Copying someone else's split.", findRichText: true), findsOneWidget);

      // No failure mode is rendered as a bare paragraph (they are list items in Rows)
      final secondFailureFinder = find.textContaining('Giving away ownership cheaply', findRichText: true);
      expect(secondFailureFinder, findsOneWidget);
      expect(find.ancestor(of: secondFailureFinder, matching: find.byType(Row)), findsOneWidget);

      final thirdFailureFinder = find.textContaining('Starving the core engine', findRichText: true);
      expect(thirdFailureFinder, findsOneWidget);
      expect(find.ancestor(of: thirdFailureFinder, matching: find.byType(Row)), findsOneWidget);
    });

    testWidgets('an element marked {failure!} is the callout, and remaining failures precede pitfalls in the numbered list', (t) async {
      const markedSnippet = '''## {guard} Misreading Risk: Where The Numbers Mislead

**{failure} First Mistake:** The first failure mode.
**{failure!} Key Failure:** The marked failure mode that must stand out.
**{failure} Third Mistake:** The third failure mode.

**{pitfalls} Avoid Traps:**
- **Pitfall Alpha.** First pitfall detail.
''';
      await _pump(t, markedSnippet);

      // Callout holds Key Failure
      final calloutLabels = t.widgetList<Text>(find.byKey(const Key('callout-label'))).map((x) => x.data).toList();
      expect(calloutLabels, hasLength(1));
      expect(find.textContaining('The marked failure mode that must stand out', findRichText: true), findsOneWidget);

      // Subheading is Avoid Traps
      expect(find.text('Avoid Traps'), findsOneWidget);

      // Numbered list items 1..3
      expect(find.text('1.'), findsOneWidget);
      expect(find.text('2.'), findsOneWidget);
      expect(find.text('3.'), findsOneWidget);
      expect(find.text('4.'), findsNothing);

      // First Mistake is item 1, Third Mistake is item 2, Pitfall Alpha is item 3
      expect(find.textContaining('First Mistake', findRichText: true), findsOneWidget);
      expect(find.textContaining('Third Mistake', findRichText: true), findsOneWidget);
      expect(find.textContaining('Pitfall Alpha', findRichText: true), findsOneWidget);
    });

    testWidgets('three failure lines with no pitfalls element renders subheading Failure modes and numbered list', (t) async {
      const noPitfallsSnippet = '''## {guard} Misreading Risk: Where The Numbers Mislead

**{failure} Core Risk:** Main risk text.
**{failure} Second Risk:** Second risk text.
**{failure} Third Risk:** Third risk text.
''';
      await _pump(t, noPitfallsSnippet);

      expect(find.byKey(const Key('callout-label')), findsOneWidget);
      expect(find.text('Failure modes'), findsOneWidget);
      expect(find.text('1.'), findsOneWidget);
      expect(find.text('2.'), findsOneWidget);
      expect(find.text('3.'), findsNothing);
    });

    testWidgets('real v4 module fixture renders one callout and numbered pitfalls under subheading', (t) async {
      const fixtureGuard = '''## {guard} Where Trap: Where Ownership Leaks

**{failure} Where Mistake:** Four common ways this goes wrong. Treating revenue as wealth: \$5,000,000 of sales means nothing if costs and tax take \$4,900,000.

**{pitfalls} Common Pitfalls:**
- **Calling a job an asset.** A business that stops when you stop is a job with extra paperwork, however it is registered.
- **Copying someone else's split.** The bucket shares depend on your age, debts, dependants and risk. Borrowed percentages are guesses.
- **Mistaking a possible gain for a likely one.** Growth-bucket assets can and often do go to zero. Size them so that loss is survivable.
''';
      await _pump(t, fixtureGuard);

      expect(find.byKey(const Key('callout-label')), findsOneWidget);
      expect(find.text('Common Pitfalls'), findsOneWidget);
      expect(find.text('1.'), findsOneWidget);
      expect(find.text('2.'), findsOneWidget);
      expect(find.text('3.'), findsOneWidget);
      expect(find.text('4.'), findsNothing);
    });
  });
}

TextSpan? _findSpan(InlineSpan root, String text) {
  TextSpan? found;
  root.visitChildren((s) {
    if (s is TextSpan && s.text == text) {
      found = s;
      return false;
    }
    return true;
  });
  return found;
}
