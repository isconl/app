import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/ui/widgets/reader.dart';
import 'package:isconl/util/markdown.dart';

void main() {
  group('reading variant', () {
    // The whole point of the variant is that a reading page carries no boxes.
    // Assert it structurally, because "looks borderless" is not a test.
    testWidgets('a table renders without an enclosing outline', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Markdown('| a | b |\n|---|---|\n| 1 | 2 |',
                variant: MarkdownVariant.reading),
          ),
        ),
      ));
      final table = tester.widget<Table>(find.byType(Table));
      expect(table.border?.left, BorderSide.none);
      expect(table.border?.right, BorderSide.none);
      // Horizontal rules stay - they are what keeps rows legible.
      expect(table.border?.horizontalInside.width, greaterThan(0));
    });

    testWidgets('a code block renders without a border', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Markdown('```\ncode line\n```',
                variant: MarkdownVariant.reading),
          ),
        ),
      ));
      final box = tester
          .widgetList<Container>(find.byType(Container))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .toList();
      expect(box.any((d) => d.border != null), isFalse);
      expect(find.text('code line'), findsOneWidget);
    });

    testWidgets('compact keeps its borders', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Markdown('| a | b |\n|---|---|\n| 1 | 2 |'),
          ),
        ),
      ));
      final table = tester.widget<Table>(find.byType(Table));
      expect(table.border?.verticalInside.width, greaterThan(0));
    });
  });

  group('reading surface', () {
    testWidgets('caps the measure on a wide window', (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: ReadingSurface(children: [Text('body')]),
        ),
      ));
      final width = tester.getSize(find.byType(ReadingSurface).first).width;
      expect(width, 1600);
      // The prose itself is held to the measure, not the window.
      final textWidth = tester.getSize(find.text('body')).width;
      expect(textWidth, lessThanOrEqualTo(700));
    });

    testWidgets('header renders kicker, title and meta', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: ReadingSurface(children: [
            ReadingHeader(
                title: 'Module 16', kicker: 'viva-tasks', meta: '900 words'),
          ]),
        ),
      ));
      expect(find.text('Module 16'), findsOneWidget);
      expect(find.text('VIVA-TASKS'), findsOneWidget);
      expect(find.text('900 words'), findsOneWidget);
    });
  });

  group('readingMeta', () {
    test('counts words and rounds reading time up', () {
      expect(readingMeta(''), '');
      expect(readingMeta('one two three'), '3 words · 1 min read');
      final long = List.filled(440, 'word').join(' ');
      expect(readingMeta(long), '440 words · 2 min read');
    });
  });
}
