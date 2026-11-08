import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/util/markdown.dart';

// Sconl, 8 Nov 2026: a module's change notes leave the copy and fold into one pill above the first movement.
void main() {
  const module = '''
# Choosing One Country

The CEO's pick, our earlier score

## {orient} Market Brief: The Decision Made

**{place} Course Map:** module 1 of 22.

_Changed 8 November 2026: the module no longer recommends Estonia first. Why: the CEO decided on 7 November._

_Changed 6 October 2026: first version at standard 4.0.0._

## {grasp} The Answer: UAE, Romania, Bulgaria

Body text.
''';

  test('parses a note with a why', () {
    final n = parseChangeNote('_Changed 8 November 2026: tables added. Why: the plan arrived._')!;
    expect(n.date, '8 November 2026');
    expect(n.shortDate, '8 Nov 2026');
    expect(n.what, 'tables added.');
    expect(n.why, 'the plan arrived.');
  });

  test('a note without a why keeps its text and an empty why', () {
    final n = parseChangeNote('_Changed 6 October 2026: first version._')!;
    expect(n.what, 'first version.');
    expect(n.why, '');
  });

  test('ordinary italic paragraphs are not notes', () {
    expect(parseChangeNote('_The region where the ten markets sit._'), isNull);
    expect(parseChangeNote('Changed 8 November 2026: not italic'), isNull);
  });

  test('notes are found and ordered newest first', () {
    final notes = changeNotesOf(module);
    expect(notes.map((n) => n.date), ['8 November 2026', '6 October 2026']);
  });

  testWidgets('notes leave the copy and open from one pill', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: Markdown(module, variant: MarkdownVariant.reading))),
    ));
    expect(find.textContaining('_Changed'), findsNothing);
    expect(find.textContaining('no longer recommends Estonia'), findsNothing);
    expect(find.text('Updated 8 Nov 2026'), findsOneWidget);
    expect(find.textContaining('2 revisions'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('change-notes-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('the module no longer recommends Estonia first.'), findsOneWidget);
    expect(find.text('the CEO decided on 7 November.'), findsOneWidget);
    expect(find.text('WHY'), findsOneWidget);
    expect(find.text('6 OCT 2026'), findsOneWidget);
    expect(find.textContaining('Body text'), findsOneWidget);
  });

  testWidgets('a module without notes shows no pill', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Markdown('## {orient} A: B C D\n\nText.'))));
    expect(find.byType(ChangeNotesPill), findsNothing);
  });
}
