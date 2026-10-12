import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/ui/views/jira.dart';
import 'package:isconl/ui/widgets/jira_compose.dart';

import 'support/test_services.dart';

class JiraApi extends ScriptedApi {
  JiraApi(super.answers, {this.pushAnswer});
  final List<Map<String, dynamic>> posts = [];
  final Map<String, dynamic>? pushAnswer;

  @override
  Future<dynamic> postJson(String path, Map<String, dynamic> body, {bool cold = false}) async {
    posts.add({'path': path, ...body});
    if (path == '/api/jira/preview') return answers['/api/jira/preview'];
    if (path == '/api/jira/push') return pushAnswer ?? {'success': true, 'key': 'WSRU-77'};
    return {'success': true, 'key': 'WSRU-78'};
  }
}

final preview = {
  'success': true,
  'payload': {
    'summary': 'Ship the quarterly review pack',
    'description': 'Compile the numbers, write the three-page summary and send it to the supervisor for sign-off.',
    'duedate': '2026-10-20',
    'assignee': 'acc-1',
    'labels': ['work'],
    'priority': 'high',
  },
  'users': [
    {'accountId': 'acc-1', 'displayName': 'First Owner'},
  ],
  'tags': ['work', 'personal'],
  'project': 'WSRU',
};

void main() {
  test('the checklist is the console\'s: outcome summary, a real description, a date, a tag and an owner', () {
    final ok = jiraReadiness({'summary': 'Ship the quarterly review pack', 'description': 'x' * 40, 'duedate': '2026-10-20', 'tag': 'work', 'assignee': 'a'});
    expect(ok.every((c) => c.ok), isTrue);
    final bad = jiraReadiness({'summary': 'Fix it', 'description': 'short', 'duedate': '20 Oct', 'tag': '', 'assignee': ''});
    expect(bad.where((c) => !c.ok).map((c) => c.id).toList(), ['summary', 'description', 'duedate', 'tag', 'assignee']);
    // Twelve characters but under three words still reads as a placeholder.
    expect(jiraReadiness({'summary': 'Quarterlyreview'})[0].ok, isFalse);
  });

  test('a pending item reads as its summary, a transition, or its action', () {
    expect(pendingLabel({'payload': {'summary': 'New issue'}, 'action': 'create'}), 'New issue');
    expect(pendingLabel({'payload': {'key': 'WSRU-1', 'from': 'To Do', 'to': 'Done'}}), 'WSRU-1: To Do to Done');
    expect(pendingLabel({'payload': {'key': 'WSRU-1', 'transitionName': 'Start'}}), 'WSRU-1: Start');
    expect(pendingLabel({'payload': {}, 'action': 'assign'}), 'assign');
    expect(pendingOnly({'pending': [{'id': 'a', 'status': 'pending'}, {'id': 'b', 'status': 'approved'}]}).map((p) => p['id']).toList(), ['a']);
  });

  test('only open tasks without an issue are offered for creating one', () {
    final c = JiraView.candidateTasks([
      {'ID': 'T1', 'JIRA_KEY': '-', 'STATUS': 'today'},
      {'ID': 'T2', 'JIRA_KEY': 'WSRU-3', 'STATUS': 'today'},
      {'ID': 'T3', 'JIRA_KEY': '-', 'STATUS': 'done'},
      {'ID': 'T4', 'JIRA_KEY': '', 'STATUS': 'inbox'},
    ]);
    expect(c.map((t) => t['ID']).toList(), ['T1', 'T4']);
  });

  Future<JiraApi> pump(WidgetTester tester, Widget body, Map<String, Object> answers, {Map<String, dynamic>? pushAnswer}) async {
    final api = JiraApi(answers, pushAnswer: pushAnswer);
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final services = (await tester.runAsync(() => buildTestServices(api)))!;
    await tester.pumpWidget(AppScope(services: services, child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: body)))));
    for (var i = 0; i < 4; i++) {
      await tester.pump();
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 60)));
    }
    await tester.pump();
    return api;
  }

  testWidgets('the review sheet shows the preview and a ready issue pushes exactly what is on screen', (tester) async {
    final api = await pump(tester, const JiraReviewSheet(taskId: 'T1'), {'/api/jira/preview': preview});
    expect(find.text('New Jira issue · WSRU'), findsOneWidget);
    expect(find.text('Create in Jira'), findsOneWidget);
    await tester.tap(find.byKey(const Key('jira-create')));
    await tester.pump();
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 80)));
    await tester.pump();
    final push = api.posts.firstWhere((p) => p['path'] == '/api/jira/push');
    expect(push['taskId'], 'T1');
    expect(push['force'], false);
    expect(push['summary'], 'Ship the quarterly review pack');
    expect(push['labels'], ['work']);
    expect(push['priority'], 'high');
    expect(push['assignee'], 'acc-1');
  });

  testWidgets('a failed push shows hub\'s error and keeps the draft', (tester) async {
    await pump(tester, const JiraReviewSheet(taskId: 'T1'), {'/api/jira/preview': preview}, pushAnswer: {'success': false, 'error': 'Jira refused: assignee not assignable'});
    await tester.tap(find.byKey(const Key('jira-create')));
    await tester.pump();
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 80)));
    await tester.pump();
    expect(find.text('Jira refused: assignee not assignable'), findsOneWidget);
    expect(find.text('Ship the quarterly review pack'), findsOneWidget);
    expect(find.byKey(const Key('jira-create')), findsOneWidget);
  });

  testWidgets('an incomplete issue says what is missing and the button counts it', (tester) async {
    final thin = {
      ...preview,
      'payload': {'summary': 'Fix it', 'description': '', 'duedate': '', 'assignee': '', 'labels': <String>[], 'priority': 'medium'},
    };
    await pump(tester, const JiraReviewSheet(taskId: 'T1'), {'/api/jira/preview': thin});
    expect(find.text('5 things missing - push anyway'), findsOneWidget);
    expect(find.textContaining('Has an owner. Unassigned issues belong to nobody.'), findsOneWidget);
  });

  testWidgets('a preview refusal shows hub\'s reason instead of a form', (tester) async {
    await pump(tester, const JiraReviewSheet(taskId: 'T1'), {'/api/jira/preview': {'success': false, 'error': 'Task already has an issue'}});
    expect(find.text('Task already has an issue'), findsOneWidget);
  });

  testWidgets('pending items list with Approve and Deny, and approving fires after the confirm', (tester) async {
    final api = await pump(tester, const JiraPendingSection(), {
      '/api/jira/pending': {
        'pending': [
          {'id': 'p1', 'status': 'pending', 'action': 'create', 'requester': 'agent', 'createdAt': '2026-10-12T08:30:00Z', 'payload': {'summary': 'Draft release notes'}},
          {'id': 'p2', 'status': 'approved', 'action': 'create', 'payload': {'summary': 'Old'}},
        ],
      },
    });
    expect(find.text('PENDING APPROVALS · 1'), findsOneWidget);
    expect(find.text('Draft release notes'), findsOneWidget);
    expect(find.text('Old'), findsNothing);
    await tester.tap(find.byKey(const Key('approve-p1')));
    await tester.pumpAndSettle();
    expect(api.posts, isEmpty, reason: 'nothing is sent before the confirm');
    await tester.tap(find.text('Approve').last);
    await tester.pump();
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 80)));
    await tester.pump();
    final sent = api.posts.firstWhere((p) => p['path'] == '/api/jira/pending/approve');
    expect(sent['id'], 'p1');
  });
}
