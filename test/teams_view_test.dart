import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/theme.dart';
import 'package:isconl/ui/views/teams.dart';

import 'support/test_services.dart';

/// BI26092655: Board lanes, the org and team switcher, the reporting tree with forces and depth, the Architect panel, Talk.
Map<String, dynamic> w(String id, String member, String title, String status, {String signedAt = '', String note = ''}) =>
    {'id': id, 'memberId': member, 'title': title, 'status': status, 'due': '', 'late': false, 'effortDays': 1, 'signedAt': signedAt, 'blockedNote': note};

Map<String, dynamic> member(String id, String name, double depth, String level, {int directs = 0, String f1 = '', bool architect = false}) =>
    {'id': id, 'name': name, 'role': 'role', 'depth': depth, 'depthLevel': level, 'directs': directs, 'spanOver': false, 'forcePrimary': f1, 'forceSecondary': '', 'isArchitect': architect};

Map<String, dynamic> team(String id, String title, String orgId, {String parent = ''}) => {
      'id': id, 'title': title, 'orgId': orgId, 'parentTeamId': parent, 'owner': 'ARCHITECT', 'org': '',
      'members': [
        member('L', 'Lead', 3, 'green', directs: 5, f1: 'captain', architect: true),
        member('A', 'Ann', 3.5, 'green', directs: 1),
        member('K', 'Kid', 0, 'red'),
      ],
      'children': {'_root': ['L'], 'L': ['A'], 'A': ['K']},
      'forces': {'architects': [{'id': 'L', 'name': 'Lead'}]},
      'architect': {'captain': {'status': 'healthy'}, 'scout': {'status': 'quiet'}},
      'counts': {'slipped': 0},
      'work': [
        w('1', 'A', 'Queued item', 'queued'),
        w('2', 'A', 'Active item', 'active'),
        w('3', 'K', 'Blocked item', 'blocked', note: 'vendor'),
        w('4', 'K', 'Finished item', 'finished'),
        w('5', 'A', 'Fresh signed', 'signed', signedAt: DateTime.now().toUtc().toIso8601String()),
        w('6', 'A', 'Old signed', 'signed', signedAt: '2020-01-01T00:00:00Z'),
      ],
    };

/// BI26101816: the shared space header remembers its tab in the local database, whose lock warning leaves a 10 s timer
/// behind; every test ends by unmounting the tree and letting it run out.
void tw(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    await body(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 11));
  });
}

void main() {
  test('the board has five lanes in order, and a Draft lane only when there are drafts', () {
    final t = team('T', 'Studio', 'O1');
    final lanes = teamLanes(t);
    expect(lanes.map((l) => l.title), ['Ready', 'Doing', 'Blocked', 'Awaiting sign-off', 'Done this sprint']);
    expect(lanes.map((l) => l.items.map((i) => i['id']).toList()), [['1'], ['2'], ['3'], ['4'], ['5']], reason: 'only a recent signature is this sprint');
    final withDraft = {...t, 'work': [w('d', 'A', 'Half', 'draft')]};
    expect(teamLanes(withDraft).first.title, 'Draft');
  });

  test('teams are listed as a tree, parents before their sub-teams', () {
    final order = teamTreeOrder([team('G', 'Grand', 'O1', parent: 'K'), team('K', 'Kid', 'O1', parent: 'R'), team('R', 'Root', 'O1')]);
    expect(order.map((e) => (e.team['id'], e.depth)), [('R', 0), ('K', 1), ('G', 2)]);
  });

  test('the member tree follows the reporting edges and skips the reports of a folded member', () {
    final t = team('T', 'Studio', 'O1');
    expect(memberTree(t, {}).map((e) => (e.member['id'], e.depth, e.hasKids)), [('L', 0, true), ('A', 1, true), ('K', 2, false)]);
    expect(memberTree(t, {'A'}).map((e) => e.member['id']), ['L', 'A']);
  });

  Future<void> pump(WidgetTester tester, Map<String, dynamic> data) async {
    final services = (await tester.runAsync(() => buildTestServices(ScriptedApi({'/api/teams': data}))))!;
    await tester.pumpWidget(AppScope(
      services: services,
      child: MaterialApp(theme: buildTheme(), home: const Scaffold(body: TeamsView())),
    ));
    await tester.pumpAndSettle();
  }

  final data = {
    'spanLimit': 5,
    'orgs': [
      {'id': 'O1', 'name': 'Acexoft', 'kind': 'own'},
      {'id': 'O2', 'name': 'Viva', 'kind': 'engagement', 'jiraConfigKey': 'WSRU'},
    ],
    'teams': [team('T', 'Studio', 'O1'), team('V', 'Testing', 'O2')],
  };

  tw('a real own team renders its lanes and depth chips, with both pickers', (tester) async {
    await pump(tester, data);
    expect(find.byKey(const Key('teams-org')), findsOneWidget);
    expect(find.byKey(const Key('teams-team')), findsOneWidget);
    // Health (the first tab) holds the depth chips; Work holds the lanes.
    expect(find.text('Ann 3.5d'), findsOneWidget);
    expect(find.text('Kid 0d'), findsOneWidget);
    await tester.tap(find.byKey(const Key('teams-tab-work')));
    await tester.pumpAndSettle();
    for (final lane in ['Ready', 'Doing', 'Blocked', 'Awaiting sign-off', 'Done this sprint']) {
      expect(find.text(lane), findsWidgets, reason: lane);
    }
    expect(find.text('Queued item'), findsOneWidget);
    expect(find.text('Old signed'), findsNothing);
  });

  tw('People shows the Architect panel, forces and a leader at five with the span warning; folding hides the reports', (tester) async {
    await pump(tester, data);
    await tester.tap(find.byKey(const Key('teams-tab-people')));
    await tester.pumpAndSettle();
    expect(find.text('Architect'), findsWidgets);
    expect(find.textContaining('Holding the position: Lead'), findsOneWidget);
    expect(find.text('Captain: Healthy'), findsOneWidget);
    expect(find.text('Scout: Quiet'), findsOneWidget);
    expect(find.byKey(const Key('span-full-L')), findsOneWidget);
    expect(find.text('Kid'), findsOneWidget);
    await tester.tap(find.byKey(const Key('fold-A')));
    await tester.pumpAndSettle();
    expect(find.text('Kid'), findsNothing);
  });

  tw('Talk is a placeholder; choosing the engagement org opens its team and says its board is Jira', (tester) async {
    await pump(tester, data);
    await tester.tap(find.byKey(const Key('teams-tab-people')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Talk comes next'), 300, scrollable: find.byType(Scrollable).last);
    expect(find.text('Talk comes next'), findsOneWidget);
    await tester.tap(find.byKey(const Key('teams-tab-health')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('teams-org')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Viva (engagement)').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Viva is an engagement: its board is Jira'), findsOneWidget);
  });
}
