import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/theme.dart';
import 'package:isconl/ui/widgets/cycle_gauge.dart';

import 'support/test_services.dart';

class GaugeApi extends ScriptedApi {
  GaugeApi(super.answers);
  final List<Map<String, dynamic>> posts = [];

  @override
  Future<dynamic> postJson(String path, Map<String, dynamic> body, {bool cold = false}) async {
    posts.add({'path': path, ...body});
    return {'success': true};
  }
}

const key = 'eq2:26-C10';

Map<String, dynamic> availableGauge({String status = 'on_track', bool empty = false, bool capped = false}) => {
      'cycleKey': key,
      'focus': {'title': 'Leverage'},
      'available': true,
      'empty': empty,
      'position': 62,
      'confidence': 0.55,
      'capped': capped,
      'weakest': 'ship',
      'dimensions': [
        {'id': 'ship', 'label': 'Shipping', 'score': 31.4, 'confidence': 0.4, 'gaps': ['No release logged this cycle.'], 'evidence': [{}]},
        {'id': 'make', 'label': 'Making', 'score': 80.0, 'confidence': 0.7, 'gaps': [], 'evidence': [{}, {}, {}]},
      ],
      'trajectory': {'status': status, 'deltaPoints': status == 'behind' ? -6 : 2},
      'trend': {'vsPriorPeriod': {'positionDelta': 4}},
    };

void main() {
  Future<GaugeApi> pump(WidgetTester tester, Map<String, dynamic> gauge) async {
    final api = GaugeApi({'/api/compass/gauge': gauge});
    final services = (await tester.runAsync(() => buildTestServices(api)))!;
    await tester.pumpWidget(AppScope(services: services, child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: CycleGaugeCard(cycleKey: key, daysElapsed: 9))))));
    await tester.pump();
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 80)));
    await tester.pump();
    return api;
  }

  test('the status badge takes the app tones and is absent for an unknown status', () {
    expect(gaugeStatus({'status': 'on_track'})!.label, 'On track');
    expect(gaugeStatus({'status': 'on_track'})!.tone, C.green);
    expect(gaugeStatus({'status': 'ahead'})!.tone, C.green);
    expect(gaugeStatus({'status': 'behind'})!.label, 'Behind');
    expect(gaugeStatus({'status': 'behind'})!.tone, C.amber);
    expect(gaugeStatus({'status': 'weird'}), isNull);
    expect(gaugeStatus(null), isNull);
    expect(pct(0.554), '55%');
    expect(pct(null), '0%');
  });

  testWidgets('an available gauge shows position, confidence, the status against the plan and the dimensions weakest first', (tester) async {
    final api = await pump(tester, availableGauge());
    expect(find.text('62'), findsOneWidget);
    expect(find.text('of 100'), findsOneWidget);
    expect(find.text('confidence 55%'), findsOneWidget);
    expect(find.text('On track · +2 against the plan'), findsOneWidget);
    expect(find.text('+4 since the last reading'), findsOneWidget);
    expect(find.textContaining('Shipping · weakest'), findsOneWidget);
    expect(find.text('Making'), findsOneWidget);
    expect(find.text('No release logged this cycle.'), findsOneWidget);
    expect(find.text('1 piece of evidence'), findsOneWidget);
    expect(find.text('3 pieces of evidence'), findsOneWidget);
    expect(find.text('Cycle gauge · Leverage'), findsOneWidget);
    // The Equicycle loader asks for its year table too, so check the gauge call is among the calls, and made once.
    expect(api.asked.where((p) => p.startsWith('/api/compass/gauge')).toList(), ['/api/compass/gauge?cycleKey=eq2%3A26-C10&daysElapsed=9&daysTotal=28']);
  });

  testWidgets('behind is amber, and a capped or empty gauge says why', (tester) async {
    await pump(tester, availableGauge(status: 'behind', empty: true, capped: true));
    final t = tester.widget<Text>(find.byKey(const Key('gauge-status')));
    expect(t.data, 'Behind · -6 against the plan');
    expect(t.style?.color, C.amber);
    expect(find.text('A near-zero dimension is holding the position down.'), findsOneWidget);
    expect(find.textContaining('No evidence logged yet'), findsOneWidget);
  });

  testWidgets('an unavailable gauge shows the reason and the empty invitation, never a number', (tester) async {
    await pump(tester, {'available': false, 'empty': true, 'reason': 'The assessment service is not set up yet.', 'focus': {'title': 'Leverage'}});
    expect(find.text('The assessment service is not set up yet.'), findsOneWidget);
    expect(find.textContaining('The first entry starts the picture'), findsOneWidget);
    expect(find.text('0'), findsNothing);
    expect(find.byKey(const Key('gauge-position')), findsNothing);
  });

  testWidgets('with no focus it offers the four models, and a tap posts the focus for this cycle', (tester) async {
    final api = await pump(tester, {'available': false, 'needsFocus': true, 'reason': 'No focus chosen for this cycle yet.'});
    for (final label in ['Leverage', 'Revenue', 'Health', 'Learning']) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.tap(find.byKey(const Key('gauge-model-isconl.cycle.revenue@1')));
    await tester.pump();
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 40)));
    await tester.pump();
    expect(api.posts, [
      {'path': '/api/compass/focus', 'cycleKey': key, 'model': 'isconl.cycle.revenue@1'},
    ]);
  });

  testWidgets('logging evidence posts the dimension, the note and the link; an empty note posts nothing', (tester) async {
    final api = await pump(tester, availableGauge());
    await tester.tap(find.byKey(const Key('gauge-log')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('gauge-save')));
    await tester.pumpAndSettle();
    expect(api.posts, isEmpty);
    await tester.tap(find.byKey(const Key('gauge-log')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('gauge-note')), 'Shipped the release');
    await tester.enterText(find.byKey(const Key('gauge-link')), 'https://example.test/pr/1');
    await tester.tap(find.byKey(const Key('gauge-save')));
    await tester.pump();
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 40)));
    await tester.pump();
    expect(api.posts.single, {'path': '/api/compass/evidence', 'cycleKey': key, 'dimension': 'ship', 'note': 'Shipped the release', 'link': 'https://example.test/pr/1'});
  });

  testWidgets('Change focus asks first, then shows the picker', (tester) async {
    await pump(tester, availableGauge());
    await tester.tap(find.byKey(const Key('gauge-change')));
    await tester.pumpAndSettle();
    expect(find.text("Change this cycle's focus?"), findsOneWidget);
    await tester.tap(find.byKey(const Key('gauge-change-confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('gauge-model-isconl.cycle.leverage@1')), findsOneWidget);
  });
}
