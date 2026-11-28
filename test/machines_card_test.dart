import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/services/slate_agents.dart';
import 'package:isconl/ui/widgets/machines_card.dart';

import 'support/test_services.dart';

class _Fake implements AgentsApi {
  @override
  Future<List<AgentMachine>> machines() async => AgentMachine.fromList([
        {'hostname': 'peter', 'status': 'online', 'network': 'unmetered', 'ageSecs': 20, 'memFreeMb': 2048, 'memTotalMb': 8192, 'diskFreeGb': 50, 'jobs': [{'id': 'j1', 'label': 'cargo test', 'progress': '40%', 'stalled': true, 'logTail': ['<b>x</b>', 'done']}]},
        {'hostname': 'fedora', 'status': 'offline', 'ageSecs': 7200},
      ]);
}

/// BI26102102: the machines card.
void main() {
  test('lines', () {
    expect(heardLine(20), 'heard from 20s ago');
    expect(heardLine(7200), 'heard from 2h ago');
    expect(heardLine(null), 'never heard from');
  });

  testWidgets('both machines show, offline stays listed, a job tail appears on tap as plain text', (tester) async {
    tester.view.physicalSize = const Size(400, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final services = (await tester.runAsync(() => buildTestServices(ScriptedApi({}))))!;
    await tester.pumpWidget(AppScope(services: services, child: MaterialApp(home: Scaffold(body: MachinesCard(api: _Fake())))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('machine-peter')), findsOneWidget);
    expect(find.byKey(const Key('machine-fedora')), findsOneWidget);
    expect(find.textContaining('memory 2.0 of 8.0 GB free'), findsOneWidget);
    expect(find.textContaining('stalled'), findsOneWidget);
    await tester.tap(find.byKey(const Key('job-peter-j1')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('<b>x</b>'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
    await tester.pump(const Duration(seconds: 2));
  });
}
