import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/api/client.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/theme.dart';
import 'package:isconl/ui/views/hub.dart';
import 'package:isconl/ui/views/vitals.dart';
import 'package:isconl/ui/widgets/vitals_card.dart';

import 'support/test_services.dart';

Map<String, dynamic> check(String id, String status, {Map<String, dynamic>? fix}) => {
      'id': id,
      'title': 'Check $id',
      'status': status,
      'value': 'value $id',
      'threshold': '< 5',
      if (fix != null) 'fix': fix,
    };

Map<String, dynamic> vitals(int score, List<Map<String, dynamic>> worst, {Map<String, dynamic>? areas}) => {
      'score': score,
      'tone': score >= 80 ? 'good' : (score >= 50 ? 'soon' : 'urgent'),
      'worst': worst,
      'areas': areas ?? {'Backups': worst},
      'measuredAt': DateTime.now().toUtc().toIso8601String(),
    };

void main() {
  group('BI26092630: vitals helpers', () {
    test('the score takes the signals tone colours: good from 80, soon 50 to 79, urgent below 50', () {
      expect(vitalsToneColor(92), C.green);
      expect(vitalsToneColor(80), C.green);
      expect(vitalsToneColor(79), C.amber);
      expect(vitalsToneColor(50), C.amber);
      expect(vitalsToneColor(45), C.red);
    });

    test('the worst three are the non-ok checks, critical first', () {
      final v = vitals(60, [check('a', 'warn'), check('b', 'critical'), check('c', 'ok'), check('d', 'warn'), check('e', 'warn')]);
      expect(worstChecks(v).map((c) => c['id']).toList(), ['b', 'a', 'd']);
      expect(worstChecks(vitals(100, [check('x', 'ok')])), isEmpty);
    });

    test('a fix is a route to open, the backup action as a queued sync, or nothing', () {
      expect(vitalsFix(check('a', 'warn', fix: {'label': 'Open', 'route': '/ops'}))!.route, '/ops');
      final q = vitalsFix(check('a', 'warn', fix: {'label': 'Back up', 'action': 'POST /backup/run'}))!;
      expect(q.queuePath, '/api/vault/sync');
      expect(vitalsFix(check('a', 'warn', fix: {'label': 'x', 'action': 'POST /something/else'})), isNull);
      expect(vitalsFix(check('a', 'warn')), isNull);
    });
  });

  group('BI26092630: the card', () {
    Future<AppServices> pump(WidgetTester tester, Object vitalsAnswer, Widget Function() child) async {
      final api = ScriptedApi({'/api/vitals': vitalsAnswer});
      final services = (await tester.runAsync(() => buildTestServices(api)))!;
      if (vitalsAnswer is Map<String, dynamic>) services.store.vitals.value = vitalsAnswer;
      await tester.pumpWidget(AppScope(services: services, child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child())))));
      await tester.pump();
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 80)));
      await tester.pump();
      return services;
    }

    testWidgets('a score of 45 renders red, with the worst checks listed', (tester) async {
      await pump(tester, vitals(45, [check('a', 'critical'), check('b', 'warn')]), () => const VitalsCard());
      final score = tester.widget<Text>(find.byKey(const Key('vitals-score')));
      expect(score.data, '45');
      expect(score.style?.color, C.red);
      expect(find.text('Check a'), findsOneWidget);
      expect(find.text('Check b'), findsOneWidget);
    });

    testWidgets('with nothing wrong it says All clear', (tester) async {
      await pump(tester, vitals(100, [check('a', 'ok')]), () => const VitalsCard());
      expect(find.text('All clear'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('vitals-score'))).style?.color, C.green);
    });

    testWidgets('a 404 from /api/vitals falls back to the old data-health card, so no VITALS header shows', (tester) async {
      await pump(tester, ApiException(404, 'not found'), () => const VitalsCard());
      expect(find.byKey(const Key('vitals-score')), findsNothing);
      expect(find.textContaining('VITALS'), findsNothing);
    });

    testWidgets('tapping the card opens the Vitals page, and its route fix opens that view', (tester) async {
      await pump(tester, vitals(60, [check('a', 'warn', fix: {'label': 'Open Ops', 'route': 'ops'})]), () => const VitalsCard());
      await tester.tap(find.byKey(const Key('vitals-score')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('vitals-fix-a')), findsOneWidget);
    });

    testWidgets('a queued-action fix writes to the outbox', (tester) async {
      final services = await pump(
        tester,
        vitals(60, [check('a', 'warn', fix: {'label': 'Back up now', 'action': 'POST /backup/run'})]),
        () => const VitalsView(),
      );
      await tester.tap(find.byKey(const Key('vitals-fix-a')));
      await tester.pump();
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 80)));
      await tester.pump();
      expect(services.outbox.pending, 1);
    });
  });

  group('BI26092630: the Hub', () {
    testWidgets('Latest captures is gone and the Vitals card is on the Hub', (tester) async {
      final api = ScriptedApi({'/api/vitals': vitals(88, [])});
      final services = (await tester.runAsync(() => buildTestServices(api)))!;
      services.store.vitals.value = vitals(88, []);
      services.store.state.value = {
        'time': {'eqShort': '2026-5', 'sprintShort': 'W39', 'yearPct': 74},
        'tasks': [],
        'feed': [
          {'ID': 'm1', 'TITLE': 'A capture', 'CHANNEL': 'email', 'RECEIVED': '2026-09-27T08:00:00Z'}
        ],
        'services': {},
      };
      await tester.pumpWidget(AppScope(services: services, child: const MaterialApp(home: Scaffold(body: HubView()))));
      await tester.pump();
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 120)));
      await tester.pump();
      expect(find.text('LATEST CAPTURES'), findsNothing);
      expect(find.text('A capture'), findsNothing);
      expect(find.byKey(const Key('vitals-score')), findsOneWidget);
      // Let the Hub's own timers run out before the tree is torn down.
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
      await tester.pump(const Duration(seconds: 2));
    });
  });
}
