import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/util/markdown.dart';

void main() {
  Future<void> pump(WidgetTester tester, String source) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: Markdown(source))),
    ));
  }

  testWidgets('renders headings, lists and bold', (tester) async {
    await pump(tester, '''
# Title
Some **bold** text and *italic*.

- first item
- second item

1. numbered
''');
    expect(find.textContaining('Title'), findsOneWidget);
    expect(find.textContaining('first item'), findsOneWidget);
    expect(find.textContaining('numbered'), findsOneWidget);
  });

  testWidgets('renders fenced code without crashing', (tester) async {
    await pump(tester, 'before\n```\ncode line\n```\nafter');
    expect(find.text('code line'), findsOneWidget);
  });

  testWidgets('renders tables', (tester) async {
    await pump(tester, '| a | b |\n|---|---|\n| 1 | 2 |');
    expect(find.text('a'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('empty input renders nothing', (tester) async {
    await pump(tester, '');
    expect(find.byType(Markdown), findsOneWidget);
  });

  // ── THE FIVE LESSON CALLOUTS ───────────────────────────────────────────────
  // The phone and the console have separate renderers, so the only thing
  // keeping them honest is that both are tested against the same openers. If a
  // sixth kind lands on one side, these tests are where the other side finds
  // out.

  testWidgets('renders all five callouts with canonical labels', (tester) async {
    await pump(tester, [
      '**What you will learn:** how a handoff fails.',
      '',
      '**Jargon:** handoff - work crossing from one portal to another.',
      '',
      '**What to watch for:** a success screen promising an uncalendared call.',
      '',
      '**In a book:** the system must show its own state.',
      '',
      '**Book quote:** The user needs to know what state the system is in.',
    ].join('\n'));

    expect(find.text('WHAT YOU WILL LEARN'), findsOneWidget);
    expect(find.text('JARGON'), findsOneWidget);
    expect(find.text('WHAT TO WATCH FOR'), findsOneWidget);
    expect(find.text('IN A BOOK'), findsOneWidget);
    expect(find.text('BOOK QUOTE'), findsOneWidget);
  });

  testWidgets('older openers fold into the canonical label', (tester) async {
    await pump(tester, [
      '**You will be able to:** read a module written in July.',
      '',
      '**In plain language:** an alias that predates the canon.',
      '',
      '**Watch for:** another one.',
    ].join('\n'));

    expect(find.text('WHAT YOU WILL LEARN'), findsOneWidget);
    expect(find.text('JARGON'), findsOneWidget);
    expect(find.text('WHAT TO WATCH FOR'), findsOneWidget);
  });

  testWidgets('a book citation is split onto its own line', (tester) async {
    await pump(tester,
        '**In a book:** the gulf of evaluation. '
        '[Donald Norman, The Design of Everyday Things, 2013, ch. 2]');

    expect(find.text('Donald Norman, The Design of Everyday Things, 2013, ch. 2'),
        findsOneWidget);
    // The bracket text must not still be sitting in the body.
    expect(find.textContaining('[Donald Norman'), findsNothing);
  });

  testWidgets('a callout is not swallowed into the paragraph above it',
      (tester) async {
    await pump(tester, 'Some prose leading in.\n**Jargon:** a term.');
    expect(find.text('JARGON'), findsOneWidget);
  });
}
