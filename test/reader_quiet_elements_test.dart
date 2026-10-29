// BI26102804: line elements are quiet text, section elements are subheadings, the APPLY rungs are one numbered
// ladder, and no callout is ever drawn empty. The fixture follows course standard 4.7.0 §3 and §8.1 (movements,
// line elements, section elements with their lists, and APPLY's three rungs); it is written here rather than copied
// from the library, which never enters git.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/util/markdown.dart';

const _module = '''## {orient} Setting Out: Where This Module Begins

**{prior} Before This:** Module zero sets the scene.
**{outcome} Your Goals:** You can tell an asset that pays from one that costs.
**{place} Course Map:** Module 1 of 8 in the course.

## {grasp} The Core: Assets That Pay

**{illustration} Two Flats:** One flat earns rent; the other only costs service charge.
**{point} Key Point:** An asset puts money in your pocket every month.
**{link} See Also:** [[link:Cash flow basics|module:applied-financial-intelligence/02]]

## {master} Going Deeper: Reading The Numbers

**{essentials} Core Numbers:**
- Rent received each month
- Costs paid each month

**{check} Quick Check:**
1. Which flat pays you?
2. Which costs you?

**{proof} The Evidence:** Rental yields in Nairobi run between five and eight per cent.

## {guard} Watch Out: Where This Goes Wrong

**{failure} Hidden Costs:** Service charge eats the rent.

## {apply} Make It Real: Three Steps

1. **{now} Today Only:** List what you own.
2. **{week} This Week:** Mark each one pays or costs.
3. **{role} At Work:** Ask which company assets pay.

**{expert} From Practice:**

## {review} Looking Back: What Stays

**{return} Come Back:** Return to this list in a month.
**{rescore} Score Again:** Rate your confidence from one to five.
''';

Future<void> _pump(WidgetTester t, String src) async {
  await t.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: Markdown(src, variant: MarkdownVariant.reading))),
  ));
}

Finder _keyed(String prefix) => find.byWidgetPredicate((w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith(prefix));

String _all(WidgetTester t) =>
    t.widgetList<RichText>(find.byType(RichText)).map((r) => r.text.toPlainText()).join('\n');

void main() {
  testWidgets('no Note box anywhere: every line element is a quiet line with its label in small caps', (t) async {
    await _pump(t, _module);
    final labels = t.widgetList<Text>(find.byKey(const Key('callout-label'))).map((x) => x.data ?? '').toList();
    expect(labels.where((l) => l.toUpperCase().contains('NOTE')), isEmpty, reason: 'no Note box: $labels');
    // point, link, proof, return, rescore (prior and place are section 0's own lines)
    expect(_keyed('quiet-line:'), findsNWidgets(5));
    final text = _all(t);
    expect(text, contains('KEY POINT'));
    expect(text, contains('An asset puts money in your pocket every month.'));
    expect(text, contains('SCORE AGAIN'), reason: 'rescore was missing from the element table and showed its tag');
    expect(text, isNot(contains('{rescore}')));
  });

  testWidgets('section elements read as subheadings with their list under them, never as callouts', (t) async {
    await _pump(t, _module);
    final text = _all(t);
    expect(text, contains('Core Numbers'));
    expect(text, contains('Rent received each month'));
    expect(text, contains('Quick Check'));
    expect(text, contains('Which flat pays you?'));
    final labels = t.widgetList<Text>(find.byKey(const Key('callout-label'))).map((x) => (x.data ?? '').toUpperCase()).toList();
    for (final l in labels) {
      expect(l, isNot(anyOf(contains('CORE NUMBERS'), contains('QUICK CHECK'))));
    }
  });

  testWidgets('the APPLY rungs read as one numbered ladder', (t) async {
    await _pump(t, _module);
    for (final n in [1, 2, 3]) {
      expect(_keyed('rung-$n:'), findsOneWidget);
    }
    final text = _all(t);
    expect(text, contains('Today Only'));
    expect(text, contains('List what you own.'));
    expect(text, contains('At Work'));
  });

  testWidgets('no callout is ever drawn with empty text', (t) async {
    await _pump(t, _module);
    // `{expert} From Practice:` has no body and nothing under it: it shows as a subheading only, never an empty box.
    for (final label in find.byKey(const Key('callout-label')).evaluate()) {
      final box = find.ancestor(of: find.byWidget(label.widget), matching: find.byType(Container)).first;
      final body = t.widgetList<RichText>(find.descendant(of: box, matching: find.byType(RichText)))
          .map((r) => r.text.toPlainText().trim())
          .where((s) => s.isNotEmpty);
      expect(body, isNotEmpty);
    }
  });
}
