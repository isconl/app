import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/api/client.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/ui/widgets/common.dart';
import 'package:isconl/ui/widgets/incident_cards.dart';

import 'support/test_services.dart';

/// A scripted API that records posts and can answer them with ok:false.
class OpsApi extends ScriptedApi {
  OpsApi(super.answers);
  final List<String> posts = [];
  Object postAnswer = {'ok': true};

  @override
  Future<dynamic> postJson(String path, Map<String, dynamic> body, {bool cold = false}) async {
    posts.add(path);
    final a = postAnswer;
    if (a is ApiException) throw a;
    return a;
  }
}

Map<String, dynamic> open(String id, String service) => {
      'id': id,
      'service': service,
      'startedAt': 1000,
      'cause': 'oom',
      'lines': ['It ran out of memory.', 'It restarted twice.', 'It is down now.'],
      'resolvedAt': null,
      'durationMs': null,
      'recovery': null,
    };

Map<String, dynamic> past(String id, String service, int ms, String recovery) => {
      'id': id,
      'service': service,
      'startedAt': 500,
      'cause': 'deploy',
      'lines': ['A bad deploy broke it.', 'x', 'y'],
      'resolvedAt': 900,
      'durationMs': ms,
      'recovery': recovery,
    };

void main() {
  Future<OpsApi> pump(WidgetTester tester, Object incidents, {Object postAnswer = const {'ok': true}}) async {
    final api = OpsApi({'/api/ops/incidents': incidents})..postAnswer = postAnswer;
    final services = (await tester.runAsync(() => buildTestServices(api)))!;
    await tester.pumpWidget(AppScope(services: services, child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: IncidentCards())))));
    await tester.pump();
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 80)));
    await tester.pump();
    return api;
  }

  test('durations read as plain words', () {
    expect(incidentDuration(null), 'under 1 min');
    expect(incidentDuration(0), 'under 1 min');
    expect(incidentDuration(45000), '45s');
    expect(incidentDuration(12 * 60000), '12 min');
    expect(incidentDuration(135 * 60000), '2 h 15 min');
  });

  testWidgets('no incidents shows nothing at all', (tester) async {
    await pump(tester, {'incidents': []});
    expect(find.byType(Panel), findsNothing);
    expect(find.byType(SectionLabel), findsNothing);
  });

  testWidgets('an open incident is a card with the service, the three lines, Restart and Roll back', (tester) async {
    await pump(tester, {'incidents': [open('i1', 'hub')]});
    expect(find.text('hub is down'), findsOneWidget);
    expect(find.text('It ran out of memory.'), findsOneWidget);
    expect(find.text('It restarted twice.'), findsOneWidget);
    expect(find.text('It is down now.'), findsOneWidget);
    expect(find.byKey(const Key('incident-restart-i1')), findsOneWidget);
    expect(find.byKey(const Key('incident-rollback-i1')), findsOneWidget);
  });

  testWidgets('past incidents list service, duration, recovery and the first line, with no buttons', (tester) async {
    await pump(tester, {'incidents': [past('p1', 'scope', 12 * 60000, 'restarted by itself')]});
    expect(find.byType(SectionLabel), findsOneWidget);
    expect(find.text('scope · 12 min · restarted by itself'), findsOneWidget);
    expect(find.text('A bad deploy broke it.'), findsOneWidget);
    expect(find.text('Restart'), findsNothing);
  });

  testWidgets('Restart asks first: Cancel posts nothing, Confirm posts once to the right path and toasts', (tester) async {
    final api = await pump(tester, {'incidents': [open('i1', 'hub')]});
    await tester.tap(find.byKey(const Key('incident-restart-i1')));
    await tester.pumpAndSettle();
    expect(find.text('Restart hub?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('incident-cancel')));
    await tester.pumpAndSettle();
    expect(api.posts, isEmpty);
    await tester.tap(find.byKey(const Key('incident-restart-i1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('incident-confirm')));
    await tester.pump();
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 40)));
    await tester.pump();
    expect(api.posts, ['/api/ops/service/restart?service=hub']);
    expect(find.text('hub restarted'), findsOneWidget);
  });

  testWidgets('Roll back posts the rollback path, and an ok:false answer shows the failure with its reason', (tester) async {
    final api = await pump(tester, {'incidents': [open('i1', 'hub')]}, postAnswer: {'ok': false, 'error': 'no previous image'});
    await tester.tap(find.byKey(const Key('incident-rollback-i1')));
    await tester.pumpAndSettle();
    expect(find.text('Roll back hub?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('incident-confirm')));
    await tester.pump();
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 40)));
    await tester.pump();
    expect(api.posts, ['/api/ops/service/rollback?service=hub']);
    expect(find.textContaining('failed: no previous image'), findsOneWidget);
  });

  testWidgets('a failed load shows nothing, never stale news and never a crash', (tester) async {
    await pump(tester, ApiException(502, 'down'));
    expect(find.byType(Panel), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
