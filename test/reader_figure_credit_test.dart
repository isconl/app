// BI26103092 (Sconl, 30 Oct 2026: "for images, the credits, i would like them rendered as blue small text, clickable
// to the source where necessary"). Standard §7 puts an italic caption line and a `_Credit: ..._` line under a figure;
// the figure now takes both in: the caption under the picture, the credit in small blue type with its source link
// tappable, and the "captured <date>" stamp on its own line. Neither shows again as a loose italic paragraph.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/theme.dart';
import 'package:isconl/util/markdown.dart';

const _linked = '''Before.

![Organ systems](_assets/organ_systems.png)

_Overview of Human Organ Systems._

_Credit: [Connexions, CC BY 3.0, via Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Organ_Systems_I.jpg). captured 12 October 2026._

After.
''';

const _plain = '''![Skeleton](_assets/skeleton.png)

_Human Skeleton Anterior View._

_Credit: LadyofHats Mariana Ruiz Villarreal, Public domain, via Wikimedia Commons. captured 12 October 2026._
''';

Future<void> _pump(WidgetTester t, String src) async {
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: Markdown(src, variant: MarkdownVariant.reading, courseId: 'med-human-anatomy', baseUrl: 'https://x.example', token: 't'),
      ),
    ),
  ));
}

String _all(WidgetTester t) => t.widgetList<RichText>(find.byType(RichText)).map((r) => r.text.toPlainText()).join('\n');

void main() {
  testWidgets('the credit is small blue text whose source opens on tap; caption and date stay with the figure', (t) async {
    await _pump(t, _linked);
    final credit = find.byKey(const Key('image-credit'));
    expect(credit, findsOneWidget);
    final rich = t.widget<Text>(credit);
    final span = rich.textSpan! as TextSpan;
    expect(span.style?.color, C.blue);
    final linked = span.children!.whereType<TextSpan>().where((s) => s.recognizer is TapGestureRecognizer).toList();
    expect(linked.single.text, 'Connexions, CC BY 3.0, via Wikimedia Commons');
    final text = _all(t);
    expect(text, contains('Overview of Human Organ Systems.'));
    expect(text, contains('captured 12 October 2026'));
    expect('_Credit:'.allMatches(text), isEmpty, reason: 'the credit line is not drawn again as a paragraph');
    expect(text, contains('After.'));
  });

  testWidgets('a credit without a link is still small blue text', (t) async {
    await _pump(t, _plain);
    final credit = t.widget<Text>(find.byKey(const Key('image-credit')));
    expect(credit.data, 'LadyofHats Mariana Ruiz Villarreal, Public domain, via Wikimedia Commons');
    expect(credit.style?.color, C.blue);
    expect(_all(t), contains('Human Skeleton Anterior View.'));
  });
}
