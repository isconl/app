import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/ui/widgets/plan_actions.dart';

import 'support/test_services.dart';

class PlanApi extends ScriptedApi {
  PlanApi(super.answers, {this.refuse});
  final String? refuse;
  final List<Map<String, dynamic>> posts = [];

  @override
  Future<dynamic> postJson(String path, Map<String, dynamic> body, {bool cold = false}) async {
    posts.add({'path': path, ...body});
    if (refuse != null) return {'success': false, 'error': refuse};
    switch (path) {
      case '/api/plans/distill':
        return {
          'success': true,
          'proposals': [
            {'title': 'Write the outline', 'keep': true},
            {'title': 'Book the venue'},
            {'title': '   '},
          ],
          'events': [
            {'title': 'Review day', 'start': '2026-10-20'},
          ],
        };
      case '/api/plans/ladder':
        return {
          'success': true,
          'rungs': {'decade': 'Own the platform', 'year': 'Ship v1'},
          'proposals': [
            {'title': 'First rung task'},
          ],
        };
      case '/api/plans/accept':
        return {
          'success': true,
          'added': [{}, {}],
          'events': [{}],
        };
      case '/api/plans/strategy':
        return {
          'success': true,
          'strategy': {
            'theme': 'Leverage',
            'daysLeft': 9,
            'position': 'You are ahead on shipping.',
            'leverage': ['Releases are weekly.'],
            'exposed': ['Revenue is thin.'],
            'window': 'Close the first sale.',
          },
        };
    }
    return {'success': true};
  }
}

void main() {
  test('a proposal title is read from either spelling, and only ticked, titled ones go back without the keep flag', () {
    expect(proposalTitle({'title': ' A '}), 'A');
    expect(proposalTitle({'TITLE': 'B'}), 'B');
    expect(proposalTitle({}), '');
    final all = [
      {'title': 'one', 'keep': true, 'due': 'x'},
      {'title': 'two'},
      {'title': '  '},
      {'title': 'four'},
    ];
    final chosen = chosenProposals(all, {0, 2, 3});
    expect(chosen.map((p) => p['title']).toList(), ['one', 'four']);
    expect(chosen.first.containsKey('keep'), isFalse);
    expect(chosen.first['due'], 'x');
    expect(all.first.containsKey('keep'), isTrue, reason: 'the original is untouched');
  });

  test('the summary line counts tasks and calendar entries', () {
    expect(proposalSummary(1, 0), '1 task');
    expect(proposalSummary(3, 0), '3 tasks');
    expect(proposalSummary(2, 1), '2 tasks and 1 calendar entry');
    expect(proposalSummary(1, 2), '1 task and 2 calendar entries');
  });

  Future<PlanApi> pump(WidgetTester tester, Widget body, {String? refuse}) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = PlanApi({}, refuse: refuse);
    final services = (await tester.runAsync(() => buildTestServices(api)))!;
    await tester.pumpWidget(AppScope(services: services, child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: body)))));
    await tester.pump();
    return api;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 80));
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 40)));
    }
  }

  const plan = {'ID': 'P1', 'TITLE': 'Launch the course', 'STATUS': 'active'};

  testWidgets('distill shows proposals ticked, a vetoed one is not sent, and accept posts the ticked tasks and events', (tester) async {
    final api = await pump(tester, const PlanActions(plan: plan));
    await tester.tap(find.byKey(const Key('plan-distill-P1')));
    await settle(tester);
    expect(find.text('Write the outline'), findsOneWidget);
    expect(find.text('Book the venue'), findsOneWidget);
    expect(find.text('Review day'), findsOneWidget);
    // Veto the second task.
    await tester.tap(find.byKey(const Key('keep-task-1')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('plan-accept')));
    await settle(tester);
    final sent = api.posts.firstWhere((p) => p['path'] == '/api/plans/accept');
    expect(sent['id'], 'P1');
    expect((sent['tasks'] as List).map((t) => (t as Map)['title']).toList(), ['Write the outline']);
    expect((sent['events'] as List).map((t) => (t as Map)['title']).toList(), ['Review day']);
    expect(find.byKey(const Key('plan-accept')), findsNothing, reason: 'the proposals are cleared once accepted');
  });

  testWidgets('nothing is added by distilling alone, and discard throws the proposals away without a request', (tester) async {
    final api = await pump(tester, const PlanActions(plan: plan));
    await tester.tap(find.byKey(const Key('plan-distill-P1')));
    await settle(tester);
    expect(api.posts.where((p) => p['path'] == '/api/plans/accept'), isEmpty);
    await tester.tap(find.byKey(const Key('plan-discard')));
    await tester.pump();
    expect(find.text('Write the outline'), findsNothing);
    expect(api.posts.where((p) => p['path'] == '/api/plans/accept'), isEmpty);
  });

  testWidgets('with everything unticked, accept sends nothing', (tester) async {
    final api = await pump(tester, const PlanActions(plan: plan));
    await tester.tap(find.byKey(const Key('plan-distill-P1')));
    await settle(tester);
    for (final k in ['keep-task-0', 'keep-task-1', 'keep-event-0']) {
      await tester.tap(find.byKey(Key(k)));
      await tester.pump();
    }
    await tester.tap(find.byKey(const Key('plan-accept')));
    await settle(tester);
    expect(api.posts.where((p) => p['path'] == '/api/plans/accept'), isEmpty);
    // The distill toast is still showing, so this one waits its turn in the snack bar queue.
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Nothing is ticked, so nothing happens.'), findsOneWidget);
  });

  testWidgets('ladder shows the rungs and its first tasks', (tester) async {
    final api = await pump(tester, const PlanActions(plan: plan));
    await tester.tap(find.byKey(const Key('plan-ladder-P1')));
    await settle(tester);
    expect(api.posts.first['path'], '/api/plans/ladder');
    expect(find.text('decade: Own the platform'), findsOneWidget);
    expect(find.text('year: Ship v1'), findsOneWidget);
    expect(find.text('First rung task'), findsOneWidget);
  });

  testWidgets('marking done and archiving ask first, then post the status', (tester) async {
    final api = await pump(tester, const PlanActions(plan: plan));
    await tester.tap(find.byKey(const Key('plan-done-P1')));
    await tester.pumpAndSettle();
    expect(api.posts.where((p) => p['path'] == '/api/plans/update'), isEmpty, reason: 'nothing before the confirm');
    await tester.tap(find.text('Mark done').last);
    await settle(tester);
    final u = api.posts.firstWhere((p) => p['path'] == '/api/plans/update');
    expect(u['id'], 'P1');
    expect(u['status'], 'done');
  });

  testWidgets('a finished goal offers no actions', (tester) async {
    await pump(tester, const PlanActions(plan: {'ID': 'P2', 'TITLE': 'Old', 'STATUS': 'done'}));
    expect(find.byKey(const Key('plan-distill-P2')), findsNothing);
    expect(find.byKey(const Key('plan-done-P2')), findsNothing);
  });

  testWidgets('a refusal shows the server\'s reason', (tester) async {
    await pump(tester, const PlanActions(plan: plan), refuse: 'The planner is busy.');
    await tester.tap(find.byKey(const Key('plan-distill-P1')));
    await settle(tester);
    expect(find.text('The planner is busy.'), findsOneWidget);
    expect(find.byKey(const Key('plan-accept')), findsNothing);
  });

  testWidgets('the strategy read shows the position, leverage, the thin spots and the one thing', (tester) async {
    final api = await pump(tester, const StrategyRead());
    await tester.tap(find.byKey(const Key('strategy-read')));
    await settle(tester);
    expect(api.posts.first['path'], '/api/plans/strategy');
    expect(find.text('Leverage · 9 days left'), findsOneWidget);
    expect(find.text('You are ahead on shipping.'), findsOneWidget);
    expect(find.text('Releases are weekly.'), findsOneWidget);
    expect(find.text('Revenue is thin.'), findsOneWidget);
    expect(find.text('If only one thing: Close the first sale.'), findsOneWidget);
  });
}
