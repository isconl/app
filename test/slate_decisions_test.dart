import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/api/client.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/ui/views/slate_decisions.dart';

import 'support/test_services.dart';

Map<String, dynamic> row(String id, String project, String title) => {'id': id, 'project': project, 'title': title, 'unblocks': 0};

final answer = <String, dynamic>{
  'total': 4,
  'groups': [
    {'kind': 'decision', 'count': 2, 'rows': [row('P1', 'iSconl', 'Which buyer first?'), row('P2', 'viva', '[redacted]')]},
    {'kind': 'hands', 'count': 1, 'rows': [row('H1', 'guard', 'Run the key script')]},
    {'kind': 'ack', 'count': 1, 'rows': [row('A1', 'deck', 'Acknowledge the rename')]},
  ],
};

void main() {
  Future<AppServices> pump(WidgetTester tester, Object apiAnswer, {Map<String, dynamic>? seed}) async {
    final api = ScriptedApi({'/api/slate/decisions': apiAnswer});
    final services = (await tester.runAsync(() => buildTestServices(api)))!;
    if (seed != null) services.store.slateDecisions.value = seed;
    await tester.pumpWidget(AppScope(services: services, child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: DecisionsView())))));
    await tester.pump();
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 80)));
    await tester.pump();
    return services;
  }

  test('group labels are plain words, and an unknown kind shows as it is', () {
    expect(kindLabel('decision'), 'Decisions');
    expect(kindLabel('hands'), 'Hands');
    expect(kindLabel('ack'), 'To acknowledge');
    expect(kindLabel('brainstorm'), 'Brainstorms');
    expect(kindLabel('other'), 'other');
  });

  testWidgets('groups show a count each, rows show id, project and title, and a redacted title stays as returned', (tester) async {
    await pump(tester, answer, seed: answer);
    expect(find.text('Decisions · 2'), findsOneWidget);
    expect(find.text('Hands · 1'), findsOneWidget);
    expect(find.text('To acknowledge · 1'), findsOneWidget);
    expect(find.text('P1 · iSconl'), findsOneWidget);
    expect(find.text('Which buyer first?'), findsOneWidget);
    expect(find.text('[redacted]'), findsOneWidget);
    expect(find.textContaining('Answers happen in sessions'), findsOneWidget);
  });

  testWidgets('with nothing waiting it says so, not a blank screen', (tester) async {
    await pump(tester, {'total': 0, 'groups': []}, seed: {'total': 0, 'groups': []});
    expect(find.text('Nothing is waiting on you'), findsOneWidget);
  });

  testWidgets('offline with a cached copy still shows the last data', (tester) async {
    await pump(tester, ApiException(0, 'offline'), seed: answer);
    expect(find.text('Decisions · 2'), findsOneWidget);
    expect(find.text('Run the key script'), findsOneWidget);
  });
}
