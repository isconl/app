// BI26111891 (course standard 4.9.0): the section takeaways (§8.5) and the Chronicle module (§19).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/util/markdown.dart';

const _takeaways = '''## {build} The Detail: Market And Law

**{research} Price Range:** Guides put a seat at USD 400 to 1,600 a month [Example, 2026].

Prose about the law.

**{keyidea} Price Last:** No seat gets a price until the real cost per person is on record.

## {master} Expert Eye: Week One Quality

Experienced managers brief both sides together.

**{takeaway} Week One:** Agree three tasks before day one and check the work every evening.

**{link} Next Module:** module 12.
''';

const _chronicle = '''## {prologue} Before We Begin: A Gambler's Unfinished Game

**{outcome} You Will:** explain how two letters founded probability.

The story opens in Paris.

## {chapter} Chapter One: A Question From Paris

**{dateline} Paris, Summer:** 1654

Pascal took the question seriously and wrote to Fermat.

**{player} Blaise Pascal:** a mathematician who wrote to Fermat about the game.

**{record} First Letter:** The letter of 29 July 1654 sets out the method [Pascal, 1654].

**{keyidea} Split Fairly:** Divide the stakes by what each player could still win.

## {chapter} Chapter Two: Fermat Replies

Fermat counted every way the game could end.

**{keyidea} Count Futures:** Listing every possible ending turns a dispute into arithmetic.

## {epilogue} Looking Back: What The Story Teaches

**{keypoints} Key Points:**
- Expected value began as a fair split.
- Counting futures settles arguments.
''';

Future<void> _pump(WidgetTester t, String src) async {
  await t.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: Markdown(src, variant: MarkdownVariant.reading))),
  ));
}

List<String?> _labels(WidgetTester t) => t.widgetList<Text>(find.byKey(const Key('callout-label'))).map((x) => x.data).toList();
String _text(WidgetTester t) =>
    t.widgetList<RichText>(find.byType(RichText)).map((r) => r.text.toPlainText()).join('\n');

void main() {
  testWidgets('a Key Idea and a Takeaway are boxed with their fixed names, beside the section\'s other callout', (t) async {
    await _pump(t, _takeaways);
    final labels = _labels(t);
    expect(labels.any((l) => l!.contains('RESEARCH')), isTrue, reason: 'the section\'s one callout stays');
    expect(labels.any((l) => l!.contains('KEY IDEA')), isTrue, reason: 'the key idea is not demoted to prose');
    expect(labels.any((l) => l!.contains('TAKEAWAY')), isTrue);
    expect(_text(t), contains('No seat gets a price'));
    // the authored two-word label is never shown
    expect(_text(t), isNot(contains('Price Last')));
  });

  testWidgets('a Chronicle reads as a book: PROLOGUE, CHAPTER n and EPILOGUE, unnumbered callouts', (t) async {
    await _pump(t, _chronicle);
    final eyebrows = t.widgetList<Text>(find.byKey(const Key('movement-eyebrow'))).map((x) => x.data).toList();
    expect(eyebrows, ['PROLOGUE', 'CHAPTER 1', 'CHAPTER 2', 'EPILOGUE']);
    final labels = _labels(t);
    expect(labels.where((l) => l!.contains('KEY IDEA')).length, 2);
    expect(labels.any((l) => l!.contains('PLAYER')), isTrue);
    expect(labels.any((l) => l!.contains('ON RECORD')), isTrue);
    expect(labels.any((l) => l!.contains('KEY POINTS')), isTrue);
    // no k.j numbers in a chronicle
    expect(labels.any((l) => RegExp(r'^\d+\.\d+').hasMatch(l!)), isFalse);
    // the dateline is a small line, not a box
    expect(find.byKey(const Key('chronicle-dateline')), findsOneWidget);
    expect(_text(t), contains('Paris, Summer · 1654'));
    // the key points box holds its list
    expect(_text(t), contains('• Counting futures settles arguments.'));
  });
}
