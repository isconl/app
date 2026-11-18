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
  mainDocument();
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

const _document = '''## {prologue} About This Part: Recruitment And Probation

**{outcome} You Will:** say what chapter three requires.

**{source} The Manual:** HR Manager Manual v1.0.

## {part} Section 3.2: Notice And Probation

The manual sets a probation period for every hire.

**{verbatim} Probation Terms:** "Every new hire serves a probation of three months." [HR Manual v1.0, §3.2]

**{commentary} In Practice:** the clock starts on the first working day.

**{gap} Unclear Start:** the manual does not say who signs the confirmation.

**{keyidea} Probation First:** Nobody is confirmed before three months of checked work.

## {epilogue} Keep This: What Chapter Three Asks

**{keypoints} Key Points:**
- Three months of probation.
''';

// BI26111891 (4.9.0 §21): the Document module keeps the document's own numbering and marks its words apart from ours.
void mainDocument() {
  testWidgets('a Document module shows the document\'s section number and its word-for-word, commentary and open-point boxes', (t) async {
    await _pump(t, _document);
    final eyebrows = t.widgetList<Text>(find.byKey(const Key('movement-eyebrow'))).map((x) => x.data).toList();
    expect(eyebrows, ['PROLOGUE', 'SECTION 3.2', 'EPILOGUE']);
    final labels = _labels(t);
    for (final l in ['WORD FOR WORD', 'COMMENTARY', 'OPEN POINT', 'KEY IDEA']) {
      expect(labels.any((x) => x!.contains(l)), isTrue, reason: l);
    }
    expect(find.byKey(const Key('callout-cite')), findsOneWidget, reason: 'the locator is the credit line');
  });
}
