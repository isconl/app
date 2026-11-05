// BI26101106: the study module view. One callout per section, labels hidden, prose styling,
// citation lines, image placeholders and credits, the figure viewer, and the up chevron.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/theme.dart';
import 'package:isconl/util/markdown.dart';
import 'package:cached_network_image/cached_network_image.dart';

Future<void> pumpMd(WidgetTester t, String src, {Map<String, Size> sizes = const {}}) async {
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: Markdown(src,
            variant: MarkdownVariant.reading,
            courseId: 'c',
            baseUrl: 'https://example.invalid',
            token: 'secret-token',
            imageSizes: sizes),
      ),
    ),
  ));
}

const three = '''## A section
**{illustration} First One:** The first callout-kind element.
**{fact} Second One:** The second element.
**{failure} Third One:** The third element.
''';

void main() {
  testWidgets('a section with three callout-kind elements renders one callout and two paragraphs', (t) async {
    await pumpMd(t, three);
    expect(find.byKey(const Key('callout-label')), findsOneWidget);
    expect(find.textContaining('The first callout-kind element.', findRichText: true), findsOneWidget);
    expect(find.textContaining('The second element.', findRichText: true), findsOneWidget);
    expect(find.textContaining('The third element.', findRichText: true), findsOneWidget);
  });

  testWidgets('each section gets its own callout', (t) async {
    await pumpMd(t, '$three\n## Another\n**{fact} Lone Fact:** Only one here.\n');
    expect(find.byKey(const Key('callout-label')), findsNWidgets(2));
  });

  testWidgets('labels are hidden, and inline bold, italics and jargon marks survive in prose', (t) async {
    await pumpMd(t, '## S\n**{illustration} One Two:** Kept.\n**{fact} Hidden Label:** Has **bold** and *italic* and [[term|a plain definition]].\n');
    final all = t.widgetList<RichText>(find.byType(RichText)).map((r) => r.text.toPlainText()).join('\n');
    expect(all.contains('Hidden Label'), isFalse);
    expect(all.contains('Has bold and italic and'), isTrue);
    expect(all.contains('a plain definition'), isFalse, reason: 'the jargon definition stays behind its tap');
  });

  testWidgets('a demoted Book or Research element shows its citation as a muted italic line', (t) async {
    await pumpMd(t, '## S\n**{illustration} One Two:** Kept.\n**{research} Some Study:** A finding. [Smith, Journal, 2020]\n');
    final cite = t.widget<Text>(find.byKey(const Key('prose-cite')));
    expect(cite.data, 'Smith, Journal, 2020');
    expect(cite.style?.fontStyle, FontStyle.italic);
    expect(cite.style?.color, C.text3);
  });

  testWidgets('prose is 16.5 px at 1.65 line height, and the lead paragraph after a heading is larger', (t) async {
    await pumpMd(t, '## Heading\n\nLead paragraph here.\n\nSecond paragraph here.\n');
    // Text.rich wraps our span in the default style; the paragraph's own span is its first child.
    TextSpan span(String needle) => t
        .widgetList<RichText>(find.byType(RichText))
        .map((r) => r.text as TextSpan)
        .where((s) => s.children?.length == 1 && s.toPlainText().contains(needle))
        .map((s) => s.children!.first as TextSpan)
        .first;
    expect(span('Second paragraph').style?.fontSize, 16.5);
    expect(span('Second paragraph').style?.height, closeTo(1.65, 0.001));
    expect(span('Lead paragraph').style?.fontSize, 17.5);
  });

  testWidgets('an image reserves its aspect ratio before it loads, behind a placeholder, with caption and credit', (t) async {
    await pumpMd(t, '![A ridge at dawn](_assets/ridge.png "The ridge at dawn. Credit: Jane Doe")\n',
        sizes: {'ridge.png': const Size(400, 200)});
    await t.pump();
    expect(find.byType(CachedNetworkImage), findsOneWidget);
    final box = t.getSize(find.byType(AspectRatio));
    expect(box.width / box.height, closeTo(2.0, 0.01));
    expect(find.text('The ridge at dawn.'), findsOneWidget);
    expect(t.widget<Text>(find.byKey(const Key('image-credit'))).data, 'Jane Doe');
  });

  testWidgets('with no manifest size the placeholder is 16:10', (t) async {
    await pumpMd(t, '![A ridge](_assets/ridge.png "Ridge")\n');
    await t.pump();
    final box = t.getSize(find.byType(AspectRatio));
    expect(box.width / box.height, closeTo(1.6, 0.01));
  });

  testWidgets('the image is cached by asset path, never by the URL with its token', (t) async {
    await pumpMd(t, '![A ridge](_assets/ridge.png "Ridge")\n');
    final img = t.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
    expect(img.cacheKey, 'asset:c/ridge.png');
    expect(img.cacheKey!.contains('secret-token'), isFalse);
  });

  testWidgets('tapping a figure opens a viewer that swipes between every figure of the module', (t) async {
    await pumpMd(t, '![One](_assets/a.png "First figure")\n\n![Two](_assets/b.png "Second figure")\n');
    await t.pump();
    await t.tap(find.byType(CachedNetworkImage).first);
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('figure-pages')), findsOneWidget);
    expect(find.byKey(const Key('figure-caption')), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);
    await t.fling(find.byKey(const Key('figure-pages')), const Offset(-300, 0), 1500);
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.text('Second figure'), findsWidgets);
    await t.tap(find.byKey(const Key('figure-close')));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const Key('figure-pages')), findsNothing);
  });

  test('scroll to top is an up chevron, not the bar-and-arrow icon', () {
    final src = File('lib/ui/views/learning.dart').readAsStringSync();
    final at = src.indexOf("heroTag: 'fab_lesson_scroll_top'");
    expect(at, greaterThan(0));
    final near = src.substring(at, at + 200);
    expect(near.contains('Icons.keyboard_arrow_up_rounded'), isTrue);
    expect(src.contains('Icons.vertical_align_top_rounded'), isFalse);
  });
}
