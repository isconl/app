import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/services/teams_api.dart';
import 'package:isconl/theme.dart';
import 'package:isconl/ui/views/teams.dart';

import 'support/test_services.dart';

class FakeTeams implements TeamsClient {
  final calls = <String>[];
  final bodies = <Map<String, dynamic>>[];
  String? refuse;

  void _check() {
    if (refuse != null) throw Exception(refuse);
  }

  @override
  Future<void> saveMember(Map<String, dynamic> member) async {
    _check();
    calls.add('member:${member['id']}');
    bodies.add(member);
  }

  @override
  Future<void> removeMember(String id) async {
    _check();
    calls.add('remove:$id');
  }

  @override
  Future<void> saveWork(Map<String, dynamic> work) async {
    _check();
    calls.add('work:${work['id']}');
    bodies.add(work);
  }

  @override
  Future<String?> moveWork(String id, String to, {String? note}) async {
    _check();
    calls.add('move:$id:$to${note == null ? '' : ':$note'}');
    return to == 'signed' ? 'ARCHITECT' : null;
  }
}

Map<String, dynamic> work(String id, String member, String title, String status) => {
      'id': id, 'memberId': member, 'title': title, 'status': status, 'why': 'because', 'due': '2026-11-01',
      'late': false, 'effortDays': 2, 'doneMeans': 'it ships', 'signedAt': '', 'blockedNote': '',
    };

Map<String, dynamic> member(String id, String name, String role) => {
      'id': id, 'name': name, 'role': role, 'depth': 3.0, 'depthLevel': 'green', 'directs': 0, 'spanOver': false,
      'forcePrimary': '', 'forceSecondary': '', 'isArchitect': false, 'reportsTo': '', 'personId': 'P-$id',
    };

final data = {
  'spanLimit': 5,
  'orgs': [{'id': 'O1', 'name': 'Acexoft', 'kind': 'own'}],
  'teams': [
    {
      'id': 'T', 'title': 'Studio', 'orgId': 'O1', 'parentTeamId': '', 'owner': 'ARCHITECT', 'org': '',
      'members': [member('A', 'Ann', 'Designer'), member('K', 'Kid', 'Intern')],
      'children': {'_root': ['A', 'K']},
      'forces': {'architects': []},
      'architect': {},
      'counts': {'slipped': 0},
      'work': [
        work('1', 'A', 'Queued item', 'queued'),
        work('2', 'A', 'Active item', 'active'),
        work('3', 'K', 'Blocked item', 'blocked'),
        work('4', 'K', 'Finished item', 'finished'),
      ],
    },
  ],
};

void main() {
  test('the move buttons follow the work lifecycle', () {
    expect(workMoves('queued').map((m) => m.to), ['active', 'blocked']);
    expect(workMoves('active').map((m) => m.to), ['finished', 'blocked']);
    expect(workMoves('blocked').map((m) => m.label), ['Unblock']);
    expect(workMoves('finished').map((m) => m.label), ['Sign']);
    expect(workMoves('signed'), isEmpty);
    expect(workMoves('draft'), isEmpty);
  });

  test('reassigning sends every field the console sends, changing only the owner', () {
    final b = workToSave(work('9', 'A', 'T', 'queued'), 'T', memberId: 'K');
    expect(b, {
      'id': '9', 'teamId': 'T', 'title': 'T', 'why': 'because', 'memberId': 'K', 'due': '2026-11-01',
      'doneMeans': 'it ships', 'effortDays': 2,
    });
    expect(workToSave({'id': '1', 'effortDays': 0}, 'T')['effortDays'], 1);
  });

  test('member body uses the console field names', () {
    final b = memberToSave(id: 'A', teamId: 'T', name: ' Ann ', role: 'Lead', reportsTo: 'K', forcePrimary: 'captain', isArchitect: true);
    expect(b['name'], 'Ann');
    expect(b['reportsTo'], 'K');
    expect(b['forcePrimary'], 'captain');
    expect(b['isArchitect'], true);
    expect(memberToSave(teamId: 'T', name: 'New').containsKey('id'), isFalse);
  });

  Future<FakeTeams> pump(WidgetTester tester) async {
    final fake = FakeTeams();
    final services = (await tester.runAsync(() => buildTestServices(ScriptedApi({'/api/teams': data}))))!;
    await tester.binding.setSurfaceSize(const Size(420, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(AppScope(
      services: services,
      child: MaterialApp(theme: buildTheme(), home: Scaffold(body: TeamsView(client: fake))),
    ));
    await tester.pumpAndSettle();
    return fake;
  }

  testWidgets('start, finish, unblock and sign move the work and say so', (tester) async {
    final c = await pump(tester);
    await tester.tap(find.byKey(const Key('work-active-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('work-finished-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('work-queued-3')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('work-signed-4')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(c.calls, ['move:1:active', 'move:2:finished', 'move:3:queued', 'move:4:signed']);
    expect(find.textContaining('Signed by ARCHITECT'), findsOneWidget);
  });

  testWidgets('blocking asks what it is blocked on and sends the note', (tester) async {
    final c = await pump(tester);
    await tester.tap(find.byKey(const Key('work-blocked-2')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('block-note')), 'waiting on legal');
    await tester.tap(find.byKey(const Key('block-confirm')));
    await tester.pumpAndSettle();
    expect(c.calls, ['move:2:blocked:waiting on legal']);
  });

  testWidgets('cancelling the block note sends nothing', (tester) async {
    final c = await pump(tester);
    await tester.tap(find.byKey(const Key('work-blocked-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(c.calls, isEmpty);
  });

  testWidgets('Give to... moves the work to another person, keeping its other fields', (tester) async {
    final c = await pump(tester);
    await tester.tap(find.byKey(const Key('work-give-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reassign-to')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kid').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reassign-confirm')));
    await tester.pumpAndSettle();
    expect(c.calls, ['work:1']);
    expect(c.bodies.single['memberId'], 'K');
    expect(c.bodies.single['title'], 'Queued item');
    expect(c.bodies.single['doneMeans'], 'it ships');
  });

  testWidgets('a refusal from the agent is shown in its own words', (tester) async {
    final c = await pump(tester);
    c.refuse = 'That would put Kid over five reports';
    await tester.tap(find.byKey(const Key('work-active-1')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('over five reports'), findsOneWidget);
  });

  testWidgets('marking a member as left asks first, with what is lost, and only then sends', (tester) async {
    final c = await pump(tester);
    await tester.tap(find.byKey(const Key('teams-tab-people')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('member-menu-A')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leaves the team'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Their open work returns to the board unassigned'), findsOneWidget);
    expect(c.calls, isEmpty);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(c.calls, isEmpty);
    await tester.tap(find.byKey(const Key('member-menu-A')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leaves the team'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('remove-confirm')));
    await tester.pumpAndSettle();
    expect(c.calls, ['remove:A']);
  });

  testWidgets('editing a member saves the changed role and keeps the rest', (tester) async {
    final c = await pump(tester);
    await tester.tap(find.byKey(const Key('teams-tab-people')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('member-menu-K')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('member-role')), 'Junior designer');
    await tester.tap(find.byKey(const Key('member-architect')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('member-save')));
    await tester.pumpAndSettle();
    expect(c.calls, ['member:K']);
    final b = c.bodies.single;
    expect(b['role'], 'Junior designer');
    expect(b['name'], 'Kid');
    expect(b['personId'], 'P-K');
    expect(b['isArchitect'], true);
    expect(b['teamId'], 'T');
  });
}
