import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/services/recall.dart';
import 'package:isconl/ui/widgets/recall_card.dart';
import 'package:isconl/util/markdown.dart' show headingSlug;

class FakeRecall implements RecallApi {
  FakeRecall({this.prompts = const [], this.summaryValue = const RecallSummary(dueToday: 2, retiredThisMonth: 1)});
  List<RecallPrompt> prompts;
  RecallSummary summaryValue;
  final answers = <String>[];
  final flagged = <String>[];
  bool right = true;
  bool retire = false;

  @override
  Future<List<RecallPrompt>> due() async => prompts;
  @override
  Future<RecallSummary> summary() async => summaryValue;
  @override
  Future<RecallResult> answer(String qId, int choice) async {
    answers.add('$qId:$choice');
    return RecallResult(
      correct: right,
      answer: 'Money in minus money out',
      why: 'It is in minus out.',
      retired: retire,
      reopen: right ? null : const RecallReopen('money', '01.md', 'the-idea'),
    );
  }

  @override
  Future<void> flag(String qId) async => flagged.add(qId);
}

const p1 = RecallPrompt(qId: 'q1', course: 'money', lesson: '01.md', question: 'What is cash flow?', choices: ['Money in minus money out', 'Profit', 'Savings']);
const p2 = RecallPrompt(qId: 'q2', course: 'money', lesson: '02.md', question: 'How long do you track?', choices: ['A day', 'A week', 'A year'], generated: true);

Widget host(Widget w) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: w)));

void main() {
  test('the summary line and heading slugs', () {
    expect(const RecallSummary(dueToday: 3, retiredThisMonth: 2).line, 'Recall: 3 due today, 2 retired this month');
    expect(headingSlug('The idea'), 'the-idea');
    expect(headingSlug('  Week 7: Cash & Flow! '), 'week-7-cash-flow');
  });

  testWidgets('nothing due and nothing retired: no card at all', (t) async {
    await t.pumpWidget(host(RecallCard(api: FakeRecall(summaryValue: const RecallSummary()), onReopen: (_) {})));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('recall-card')), findsNothing);
    expect(find.byKey(const Key('recall-summary')), findsNothing);
  });

  testWidgets('one question at a time: tap, see right or wrong with the reason, then next', (t) async {
    final api = FakeRecall(prompts: const [p1, p2]);
    await t.pumpWidget(host(RecallCard(api: api, onReopen: (_) {})));
    await t.pumpAndSettle();
    expect(find.text('What is cash flow?'), findsOneWidget);
    expect(find.text('1 of 2'), findsOneWidget);
    await t.tap(find.byKey(const Key('recall-choice-0')));
    await t.pumpAndSettle();
    expect(api.answers, ['q1:0']);
    expect(find.text('Right.'), findsOneWidget);
    expect(find.text('It is in minus out.'), findsOneWidget);
    expect(find.byKey(const Key('recall-reopen')), findsNothing);
    // Once answered the choices are locked, so a second tap does nothing.
    await t.tap(find.byKey(const Key('recall-choice-1')), warnIfMissed: false);
    expect(api.answers.length, 1);
    await t.tap(find.byKey(const Key('recall-next')));
    await t.pumpAndSettle();
    expect(find.text('How long do you track?'), findsOneWidget);
    expect(find.byKey(const Key('recall-flag')), findsOneWidget, reason: 'a generated question can be flagged');
  });

  testWidgets('a miss shows the answer and offers to reopen at that part', (t) async {
    final api = FakeRecall(prompts: const [p1])..right = false;
    RecallReopen? opened;
    await t.pumpWidget(host(RecallCard(api: api, onReopen: (r) => opened = r)));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('recall-choice-2')));
    await t.pumpAndSettle();
    expect(find.textContaining('Not quite. The answer is: Money in minus money out'), findsOneWidget);
    await t.tap(find.byKey(const Key('recall-reopen')));
    expect(opened!.anchor, 'the-idea');
    expect(opened!.lesson, '01.md');
  });

  testWidgets('flagging a drafted question removes it and moves on', (t) async {
    final api = FakeRecall(prompts: const [p2]);
    await t.pumpWidget(host(RecallCard(api: api, onReopen: (_) {})));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('recall-flag')));
    await t.pumpAndSettle();
    expect(api.flagged, ['q2']);
  });

  testWidgets('three in a row says so', (t) async {
    final api = FakeRecall(prompts: const [p1])..retire = true;
    await t.pumpWidget(host(RecallCard(api: api, onReopen: (_) {})));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('recall-choice-0')));
    await t.pumpAndSettle();
    expect(find.textContaining('Three in a row'), findsOneWidget);
  });
}
