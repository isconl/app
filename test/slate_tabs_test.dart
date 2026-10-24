import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/services/slate_agents.dart';
import 'package:isconl/ui/views/slate_tabs.dart';
import 'package:slate_ui/slate_ui.dart';

import 'support/test_services.dart';

class _Client implements SlateClient {
  final calls = <String>[];
  @override
  Future<List<SessionInfo>> sessions() async => [SessionInfo(id: 's1', machine: 'linux', kind: 'build-app', lastSeen: DateTime(2026, 10, 24, 9, 0))];
  @override
  Future<TodayData> today() async => const TodayData(closedToday: 4, weeklyDailyAverage: 6, inFlight: 3);
  @override
  Future<MatrixData> matrix() async => const MatrixData(types: ['plan', 'build'], cells: {'viva': {'plan': 2, 'build': 0}, 'isconl': {'plan': 1, 'build': 5}});
  @override
  Future<List<RowSummary>> rows({String? type, String? project}) async {
    calls.add('rows:${type ?? ''}:${project ?? ''}');
    if (type == 'manual') return [const RowSummary(id: 'M1', project: 'sconl', type: 'manual', title: 'Plug in the phones', status: 'ready')];
    return [RowSummary(id: 'B1', project: project ?? 'x', type: type ?? 'build', title: 'A row in $project', status: 'ready')];
  }

  @override
  Future<List<RowSummary>> decisions() async => [const RowSummary(id: 'D1', project: 'isconl', type: 'plan', title: 'Pick a thing', status: 'ready', gate: 'sconl:decision')];
  @override
  Future<RowDetail> row(String id, String project) async => RowDetail(id: id, project: project, type: 'plan', title: 'Pick a thing', status: 'ready', body: 'A) one\nB) two');
  @override
  Future<void> answerDecision(String id, String project, String answer) async => calls.add('answer:$id:$answer');
  @override
  Future<List<BlockerInfo>> blockers() async => [];
  @override
  Future<void> clearBlocker(String id, String evidence) async {}
  @override
  Future<List<RowSummary>> brainstorms() async => [];
  @override
  Future<void> claimRow(String id, String project) async {}
  @override
  Future<void> closeRow(String id, String project, String note) async {}
  @override
  Future<void> editRow(String id, String project, {String? title, String? body}) async {}
  @override
  Future<String> sendCommand(CommandDraft draft) async => 'c1';
  @override
  Future<DeliveryState> deliveryState(String commandId) async => DeliveryState.sent;
  @override
  Future<void> shelveProject(String project, String reason, {String? subset, bool releaseClaims = false}) async {}
  @override
  Future<void> unshelveProject(String project, String reason, {String? subset}) async {}
}

class _Agents implements AgentsApi {
  @override
  Future<List<AgentMachine>> machines() async => AgentMachine.fromList([
        {'hostname': 'peter', 'status': 'online', 'ageSecs': 10, 'jobs': [{'id': 'j1', 'label': 'cargo test', 'progress': '40%', 'stalled': true}]},
        {'hostname': 'fedora', 'status': 'offline', 'ageSecs': 7200},
      ]);
}

/// BS26102104: slate on the phone, three tabs.
void main() {
  final now = DateTime(2026, 10, 24, 9, 30);

  test('alerts name an offline machine, a stalled job and a silent session', () {
    final a = overviewAlerts(
      AgentMachine.fromList([{'hostname': 'f', 'status': 'offline', 'ageSecs': 7200}, {'hostname': 'p', 'status': 'online', 'jobs': [{'id': 'j', 'label': 'build', 'stalled': true}]}]),
      [SessionInfo(id: 's1', machine: 'linux', kind: 'build', lastSeen: now.subtract(const Duration(minutes: 20)))],
      now,
    );
    expect(a, hasLength(3));
    expect(a.first, contains('f is offline'));
  });

  test('progress text becomes a fraction', () {
    expect(progressFraction('40%'), 0.4);
    expect(progressFraction('step 3 of 9'), isNotNull);
    expect(progressFraction('running'), isNull);
  });

  Future<AppServices> setup(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    return (await tester.runAsync(() => buildTestServices(ScriptedApi({}))))!;
  }

  Future<void> host(WidgetTester tester, AppServices s, Widget child) async {
    await tester.pumpWidget(AppScope(services: s, child: MaterialApp(home: Scaffold(body: child))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> end(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('Overview shows today, alerts, machines and a progress bar', (tester) async {
    final s = await setup(tester);
    await host(tester, s, SlateOverviewTab(client: _Client(), agents: _Agents(), commandStepUp: (_) async => true, writeStepUp: (_) async => true, clock: () => now));
    expect(find.textContaining('4 closed against a 6.0 a day average'), findsOneWidget);
    expect(find.byKey(const Key('alert-fedora is offline (heard from 2h ago)')), findsOneWidget);
    expect(find.byKey(const Key('bar-peter-j1')), findsOneWidget);
    expect(find.byKey(const Key('machine-fedora')), findsOneWidget);
    await end(tester);
  });

  testWidgets('Grid: tapping a cell opens its rows', (tester) async {
    final s = await setup(tester);
    final c = _Client();
    await host(tester, s, SlateGridTab(client: c, writeStepUp: (_) async => true));
    expect(find.byKey(const Key('grid-table')), findsOneWidget);
    await tester.tap(find.text('5').first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(c.calls, contains('rows:build:isconl'));
    expect(find.text('A row in isconl'), findsOneWidget);
    await end(tester);
  });

  testWidgets('Asks: a decision is answered through the step-up and reaches slate', (tester) async {
    final s = await setup(tester);
    final c = _Client();
    var stepUps = 0;
    await host(tester, s, SlateAsksTab(client: c, writeStepUp: (_) async { stepUps++; return true; }));
    await tester.tap(find.textContaining('Decision 1 of 1: D1'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byKey(const Key('answer-field')), 'A');
    await tester.pump();
    await tester.tap(find.byKey(const Key('record-button')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(stepUps, 1);
    expect(c.calls, contains('answer:D1:A'));
    await end(tester);
  });

  testWidgets('Asks: activities list the manual rows and approvals say none yet', (tester) async {
    final s = await setup(tester);
    await host(tester, s, SlateAsksTab(client: _Client(), writeStepUp: (_) async => true));
    await tester.tap(find.byKey(const Key('asks-activities')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Activity 1 of 1: M1'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('asks-approvals')));
    await tester.tap(find.byKey(const Key('asks-approvals')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('asks-approvals-empty')), findsOneWidget);
    await end(tester);
  });
}
