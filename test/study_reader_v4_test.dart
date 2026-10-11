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
      expect(labels, ['0.1  NOTE', '1.1  ILLUSTRATION', '2.1  NOTE']);
      expect(find.textContaining('A mandate arrives late', findRichText: true), findsOneWidget);
      // The demoted elements are still read, as prose, with no label.
      expect(find.textContaining('You can name the five parts.', findRichText: true), findsOneWidget);
      expect(find.textContaining('Ship it.', findRichText: true), findsOneWidget);
      final text = _allText(t);
      for (final label in ['your goals', 'before this', 'two minutes']) {
        expect(text.contains(label), isFalse, reason: 'an authored element label showed: $label');
      }
    });

    testWidgets('the element marked {id!} is the callout, not the first one', (t) async {
      await _pump(t, _v4.replaceFirst('{outcome}', '{outcome!}'));
      final labels = t.widgetList<Text>(find.byKey(const Key('callout-label'))).map((x) => x.data).toList();
      expect(labels.first, '0.2  OBJECTIVE');
      expect(labels, hasLength(3));
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
