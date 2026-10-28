import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/api/client.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/ui/views/spaced_review_view.dart';
import 'package:isconl/util/spaced_review.dart';

import 'support/test_services.dart';

class _Api extends ApiClient {
  _Api() : super(baseUrl: 'http://test', token: 'test');
  @override
  Future<dynamic> getJson(String path, {bool cold = false, bool stored = true}) async => <String, dynamic>{};
}

const _module = '''
# Module

## MASTER · Who Writes Standards

Body text.

## PROBE · Test Your Reading

**Probe:** A dentist is the busiest in her town and cannot take a week off
without income stopping. Which side is she on?

**Probe:** What would have to change for that to reverse?

## Check yourself

- Why does a standard need an enforcer?
- Not a question, a statement
1. Who decides what counts as a safe line?

## GUARD · Where This Breaks
''';

void main() {
  final fin = DateTime(2026, 10, 1, 15); // finished 1 Oct

  test('finishing a module creates the first review for the next day', () {
    final i = enrolFinished(course: 'c', file: 'f.md', title: 'T', now: fin);
    expect(i.due, DateTime(2026, 10, 2));
    expect(i.step, 0);
  });

  test('perfect rounds walk 1, 7 and 30 days from the finish date, then retire', () {
    var i = enrolFinished(course: 'c', file: 'f.md', title: 'T', now: fin);
    i = afterRound(i, perfect: true, now: DateTime(2026, 10, 2));
    expect([i.step, i.due], [1, DateTime(2026, 10, 8)]);
    i = afterRound(i, perfect: true, now: DateTime(2026, 10, 8));
    expect([i.step, i.due], [2, DateTime(2026, 10, 31)]);
    i = afterRound(i, perfect: true, now: DateTime(2026, 10, 31));
    expect(i.retired, true);
    expect(i.history.length, 3);
  });

  test('a miss brings the module back in 3 days at the same step', () {
    var i = enrolFinished(course: 'c', file: 'f.md', title: 'T', now: fin);
    i = afterRound(i, perfect: false, now: DateTime(2026, 10, 2));
    expect([i.step, i.due, i.retired], [0, DateTime(2026, 10, 5), false]);
    i = afterRound(i, perfect: true, now: DateTime(2026, 10, 5));
    expect([i.step, i.due], [1, DateTime(2026, 10, 8)]);
  });

  test('a late perfect round never schedules in the past', () {
    var i = enrolFinished(course: 'c', file: 'f.md', title: 'T', now: fin);
    i = afterRound(i, perfect: true, now: DateTime(2026, 11, 20));
    expect(i.due, DateTime(2026, 11, 21));
  });

  test('due today: at most 3 modules, oldest first, retired and future ones left out', () {
    ReviewItem it(String f, DateTime due, {bool retired = false}) =>
        ReviewItem(course: 'c', file: f, title: f, finishedOn: DateTime(2026, 9, 1), due: due, retired: retired);
    final now = DateTime(2026, 10, 3, 9);
    final due = dueToday([
      it('a', DateTime(2026, 10, 3)),
      it('b', DateTime(2026, 10, 1)),
      it('c', DateTime(2026, 10, 2)),
      it('d', DateTime(2026, 9, 30)),
      it('e', DateTime(2026, 10, 4)),
      it('f', DateTime(2026, 9, 1), retired: true),
    ], now);
    expect(due.map((i) => i.file), ['d', 'b', 'c']);
  });

  test('questions come from the PROBE and from Check yourself items that are questions', () {
    final q = extractQuestions(_module);
    expect(q.length, 4);
    expect(q[0], startsWith('A dentist is the busiest'));
    expect(q[0], contains('Which side is she on?'));
    expect(q[1], 'What would have to change for that to reverse?');
    expect(q, contains('Why does a standard need an enforcer?'));
    expect(q, contains('Who decides what counts as a safe line?'));
    expect(q.any((x) => x.startsWith('Not a question')), false);
    expect(extractQuestions('# nothing here'), isEmpty);
  });

  test('three picked, and not the same three twice running', () {
    final all = ['q1', 'q2', 'q3', 'q4', 'q5'];
    final rng = Random(7);
    var last = <String>[];
    for (var i = 0; i < 40; i++) {
      final pick = pickQuestions(all, last: last, rng: rng);
      expect(pick.length, 3);
      expect(pick.toSet().length, 3);
      expect(pick.toSet().length == last.toSet().length && pick.toSet().containsAll(last), false);
      last = pick;
    }
    expect(pickQuestions(['only', 'two'], rng: rng), ['only', 'two']);
  });

  test('the card line', () {
    expect(reviewSummary(3), 'Review: 3 questions, 2 minutes');
    expect(reviewSummary(1), 'Review: 1 question, 1 minute');
  });

  test('the schedule survives a restart', () async {
    final services = await buildTestServices(_Api());
    final a = SpacedReview.forTesting();
    await a.enrol(course: 'c', file: 'f.md', title: 'T', now: fin, db: services.db);
    await a.record('c/f.md', perfect: false, now: DateTime(2026, 10, 2), db: services.db);
    final b = SpacedReview.forTesting();
    await b.ensureLoaded(services.db);
    expect(b.items.single.due, DateTime(2026, 10, 5));
    await b.withdraw('c', 'f.md', db: services.db);
    final c = SpacedReview.forTesting();
    await c.ensureLoaded(services.db);
    expect(c.items, isEmpty);
  });

  testWidgets('the review screen asks the questions, a miss moves the module to +3 days', (t) async {
    t.view.physicalSize = const Size(600, 1200);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final services = (await t.runAsync(() => buildTestServices(_Api(), online: false)))!;
    final data = {'content': _module};
    await t.runAsync(() => services.db.putSnapshot('lesson:c/f.md', data));
    services.store.detail('lesson', 'c/f.md', '/api/learning/lesson?course=c&file=f.md').value = data;
    final sr = SpacedReview.instance;
    await t.runAsync(() => sr.enrol(course: 'c', file: 'f.md', title: 'Standards', now: DateTime(2026, 10, 1), db: services.db));

    await t.pumpWidget(AppScope(services: services, child: MaterialApp(home: SpacedReviewScreen(now: DateTime(2026, 10, 2, 9)))));
    await t.pump();
    await t.runAsync(() => Future.delayed(const Duration(milliseconds: 150)));
    await t.pump();
    expect(find.text('Question 1 of 3'), findsOneWidget);
    await t.tap(find.byKey(const Key('review-got')));
    await t.pump();
    await t.tap(find.byKey(const Key('review-missed')));
    await t.pump();
    await t.tap(find.byKey(const Key('review-got')));
    await t.pump();
    await t.runAsync(() => Future.delayed(const Duration(milliseconds: 150)));
    await t.pump();
    expect(find.text('Review done.'), findsOneWidget);
    expect(find.textContaining('back in 3 days'), findsOneWidget);
    final item = sr.items.firstWhere((i) => i.key == 'c/f.md');
    expect(item.due, DateTime(2026, 10, 5));
    expect(item.last.length, 3);
    await t.runAsync(() => sr.withdraw('c', 'f.md', db: services.db));
  });
}
