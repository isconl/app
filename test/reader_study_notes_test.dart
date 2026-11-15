// BI26111594: Sconl's study notes of 14 Nov 2026 on the reader: {concept} is a callout, the answer toggle sits on the
// right, the APPLY rungs are plain bullets with the timeframe bold green, and a GUARD failure list is numbered in the
// failure callout's colour. Fixture written here; the library never enters git.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/theme.dart';
import 'package:isconl/util/markdown.dart';

const _module = '''## {build} The Detail: Lines And Money

**{concept} The Lines:** what each line sells, and what it has earned on the record.

## {probe} Recall Check: Name The Five

**{probe} The Five:** Name the five framings.

**{modelanswer} Worked Reply:** A portal, packages, a network, leasing, an environment.

## {guard} Common Slip: Numbers As Facts

**{failure} False Precision:** You repeat a guess as if it were measured.

**{pitfalls} Common Pitfalls:**
- **Mixing weights in one sentence.** Keep the fact and the reading apart.
- **Treating unknown as no.** An unknown is open.

## {apply} Your Move: Track The Buyer

1. **{now} Two Minutes:** Write the buyer of each framing.
2. **{week} This Week:** Write who pays before reading the rest.
3. **{role} In Role:** Build material only once someone has paid.

## {anchor} Keep This: What To Carry Forward

**{carry} The Takeaway:** A plan is not progress until someone pays under it.

**{essentials} Key Points:**
- Five framings in four months.
''';

Future<void> _pump(WidgetTester t) async {
  t.view.physicalSize = const Size(400, 3000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(const MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: Markdown(_module, variant: MarkdownVariant.reading))),
  ));
}

String _all(WidgetTester t) => t.widgetList<RichText>(find.byType(RichText)).map((r) => r.text.toPlainText()).join('\n');

void main() {
  testWidgets('{concept} is drawn as a callout, never as raw text', (t) async {
    await _pump(t);
    expect(_all(t), isNot(contains('{concept}')));
    expect(_all(t), contains('what each line sells'));
  });

  testWidgets('the answer toggle sits on the right edge', (t) async {
    await _pump(t);
    final r = t.getRect(find.byKey(const Key('reveal-answer')));
    expect(r.right, greaterThan(400 - 60), reason: 'right-aligned in the column');
    expect(r.left, greaterThan(200));
  });

  testWidgets('APPLY rungs are bullets, no numbered circles, the timeframe bold green', (t) async {
    await _pump(t);
    expect(find.byKey(const Key('rung-bullet')), findsNWidgets(3));
    final spans = <TextSpan>[];
    for (final rt in t.widgetList<RichText>(find.byType(RichText))) {
      rt.text.visitChildren((s) {
        if (s is TextSpan && (s.text ?? '').startsWith('Two Minutes')) spans.add(s);
        return true;
      });
    }
    expect(spans, isNotEmpty);
    expect(spans.first.style?.color, C.green);
    expect(spans.first.style?.fontWeight, FontWeight.w700);
  });

  testWidgets('the GUARD failure list is numbered in the failure colour', (t) async {
    await _pump(t);
    final numbers = t.widgetList<Text>(find.byWidgetPredicate((w) => w is Text && RegExp(r'^\d+\.$').hasMatch(w.data ?? '')));
    expect(numbers, isNotEmpty);
    for (final n in numbers) {
      expect(n.style?.color, C.callWatch);
    }
  });

  testWidgets('KEEP THIS opens with its carry-forward sentence in a callout', (t) async {
    await _pump(t);
    expect(_all(t), contains('A plan is not progress until someone pays under it.'));
    final labels = t.widgetList<Text>(find.byKey(const Key('callout-label'))).map((x) => (x.data ?? '').toUpperCase()).toList();
    expect(labels.any((l) => l.contains('TAKEAWAY') || l.contains('CARRY')), isTrue, reason: '$labels');
  });
}
