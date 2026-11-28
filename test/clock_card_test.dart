import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/services/clock.dart';
import 'package:isconl/services/clock_strings.dart';
import 'package:isconl/ui/widgets/clock_card.dart';

import 'clock_test.dart' show FakeBridge;
import 'support/test_services.dart';

/// BI26101408: the Clock card on Today: states, the correction form's required reason, an offline tap, Swahili.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final t0 = DateTime(2026, 10, 24, 9, 0);
  var now = t0;

  Future<(ClockService, AppServices, ScriptedApi)> setup(WidgetTester tester, {Map<String, Object> answers = const {}}) async {
    final api = ScriptedApi(answers);
    final services = (await tester.runAsync(() => buildTestServices(api)))!;
    final svc = ClockService(db: services.db, api: () => api, outbox: services.outbox, bridge: FakeBridge(), now: () => now);
    return (svc, services, api);
  }

  Future<void> pump(WidgetTester tester, ClockService svc, AppServices services, {String? language}) async {
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppScope(services: services, child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ClockCard(service: svc, clock: () => now, language: language))))));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
  }

  Future<void> teardown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('the button follows the state: Clock in, Take a break, Back; Clock out appears once a day is open', (tester) async {
    now = t0;
    final (svc, services, _) = await setup(tester);
    await pump(tester, svc, services);
    expect(find.text('Clock in'), findsOneWidget);
    expect(find.byKey(const Key('clock-out')), findsNothing);
    await tester.runAsync(() async => tester.tap(find.byKey(const Key('clock-main'))));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    expect(find.text('Take a break'), findsOneWidget);
    expect(find.byKey(const Key('clock-out')), findsOneWidget);
    now = t0.add(const Duration(minutes: 90));
    await tester.runAsync(() async => tester.tap(find.byKey(const Key('clock-main'))));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    expect(find.text('Back'), findsOneWidget);
    expect(find.textContaining('Breaks: 1'), findsOneWidget);
    expect(find.textContaining('1 h 30 min'), findsOneWidget);
    await teardown(tester);
  });

  testWidgets('an offline tap is queued with the device time, not sent', (tester) async {
    now = t0;
    final (svc, services, api) = await setup(tester);
    await pump(tester, svc, services);
    await tester.runAsync(() async => tester.tap(find.byKey(const Key('clock-main'))));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
    final pending = await tester.runAsync(() => services.db.pendingOutbox());
    expect(pending!.single['path'], ClockService.entriesPath);
    expect(pending.single['body'].toString(), contains('2026-10-24T09:00:00'));
    expect(api.asked.where((p) => p.contains('time')), isEmpty);
    await teardown(tester);
  });

  testWidgets('Fix a time will not save without a reason, then queues a correction naming the entry', (tester) async {
    now = t0;
    final (svc, services, _) = await setup(tester, answers: {
      ClockService.listPath: {'entries': [{'seq': 4, 'kind': 'clock_in', 'at': t0.millisecondsSinceEpoch ~/ 1000}]},
    });
    await pump(tester, svc, services);
    await tester.runAsync(() async => tester.tap(find.byKey(const Key('clock-fix'))));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('fix-save')));
    await tester.pump();
    expect(find.text('Say why before saving.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('fix-reason')), 'forgot to clock in on time');
    await tester.runAsync(() async => tester.tap(find.byKey(const Key('fix-save'))));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 400));
    final pending = await tester.runAsync(() => services.db.pendingOutbox());
    final c = pending!.firstWhere((r) => r['path'] == ClockService.correctionsPath);
    expect(c['body'].toString(), allOf(contains('"reverses":4'), contains('forgot to clock in on time')));
    await teardown(tester);
  });

  testWidgets('Swahili follows the language', (tester) async {
    now = t0;
    final (svc, services, _) = await setup(tester);
    await pump(tester, svc, services, language: 'sw');
    expect(find.text('Anza kazi'), findsOneWidget);
    expect(find.textContaining('saa 00 dak'), findsOneWidget);
    await teardown(tester);
  });

  test('strings fall back to English and the correction needs a reason', () async {
    expect(ClockStrings.forLanguage('fr')['in'], 'Clock in');
    expect(ClockStrings.forLanguage('sw')['in'], 'Anza kazi');
  });
}
