// BI26103094 (CI26103091, Sconl 30 Oct 2026): every medicine module carries one practical Health Tip near its end, and
// the reader draws it as its own callout: a "HEALTH TIP" label in the health green, the tip's text as the body, and
// never the `{healthtip}` tag. Both forms are read: the element tag and a bold "Health tip:" label.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/theme.dart';
import 'package:isconl/util/markdown.dart';

const _tagged = '''## {apply} Make It Real: Three Steps

1. **{now} Today Only:** Count your resting pulse for one minute.

**{healthtip} Stand Hourly:** Sitting for long stretches slows blood flow in the legs. Stand and walk for two minutes every hour; a phone timer is enough.

## {review} Looking Back: What Stays

**{return} Come Back:** Return to this list in a month.
''';

const _bold = '''Text before.

**Health tip:** Drink a glass of water when you wake; the night is the longest you go without fluid.
''';

Future<void> _pump(WidgetTester t, String src) async {
  await t.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: Markdown(src, variant: MarkdownVariant.reading))),
  ));
}

List<Text> _labels(WidgetTester t) => t.widgetList<Text>(find.byKey(const Key('callout-label'))).toList();

String _all(WidgetTester t) =>
    t.widgetList<RichText>(find.byType(RichText)).map((r) => r.text.toPlainText()).join('\n');

void main() {
  testWidgets('the {healthtip} element is a Health Tip callout with its body and no visible tag', (t) async {
    await _pump(t, _tagged);
    final tip = _labels(t).where((l) => (l.data ?? '').contains('HEALTH TIP')).toList();
    expect(tip, hasLength(1), reason: 'labels: ${_labels(t).map((l) => l.data).toList()}');
    expect(tip.single.style?.color, C.callHealth);
    final text = _all(t);
    expect(text, contains('Stand and walk for two minutes every hour'));
    expect(text, isNot(contains('{healthtip}')));
  });

  testWidgets('a bold "Health tip:" label is read as the same callout', (t) async {
    await _pump(t, _bold);
    expect(_labels(t).where((l) => (l.data ?? '').contains('HEALTH TIP')), hasLength(1));
    expect(_all(t), contains('Drink a glass of water when you wake'));
  });

  testWidgets('the Health Tip box has its own colour, apart from the objective and the illustration', (t) async {
    expect(C.callHealth, isNot(C.callLearn));
    expect(C.callHealth, isNot(C.callJargon));
    expect(C.callHealthBg, isNot(C.callLearnBg));
  });
}
