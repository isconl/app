// BI26103091 (Sconl, 30 Oct 2026: "ensure all the med images show, not the placeholder icon"). CachedNetworkImage
// decodes bitmaps only, so every SVG figure showed the "image not supported" icon: 82 of the medicine track's 122
// images are SVG. An SVG figure is now drawn with flutter_svg (through the same device cache); a bitmap keeps
// CachedNetworkImage.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/util/markdown.dart';

Future<void> _pump(WidgetTester t, String src) async {
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: Markdown(src,
            variant: MarkdownVariant.reading, courseId: 'med-human-anatomy', baseUrl: 'https://isconl.example', token: 't'),
      ),
    ),
  ));
}

void main() {
  testWidgets('an SVG figure is not handed to the bitmap decoder', (t) async {
    await _pump(t, 'Text.\n\n![Alveoli and gas exchange](_assets/alveoli_gas_exchange.svg)\n\n_Gas crosses a thin wall._\n');
    expect(find.byKey(const Key('module-image')), findsOneWidget);
    expect(find.byType(CachedNetworkImage), findsNothing, reason: 'an SVG must never go to CachedNetworkImage');
  });

  testWidgets('a bitmap figure still uses the cached bitmap loader', (t) async {
    await _pump(t, 'Text.\n\n![A heart](_assets/heart.png)\n');
    expect(find.byType(CachedNetworkImage), findsOneWidget);
  });

  testWidgets('a query string or upper-case extension is still read as SVG', (t) async {
    await _pump(t, 'Text.\n\n![Nerve](_assets/NERVE_PATHS.SVG)\n');
    expect(find.byType(CachedNetworkImage), findsNothing);
  });
}
