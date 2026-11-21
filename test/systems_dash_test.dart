import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/theme.dart';
import 'package:isconl/ui/views/systems_dash_model.dart';
import 'package:isconl/ui/views/systems_dashboard.dart';

void main() {
  final ops = {
    'groups': {
      'isconl': [
        {'service': 'isconl-hub', 'running': true, 'exists': true},
        {'service': 'isconl-vault', 'running': false, 'exists': true},
        {'service': 'gone', 'running': false, 'exists': false},
      ],
    },
    'ungrouped': [
      {'service': 'tunnel', 'running': true, 'exists': true},
    ],
  };
  final backlog = {
    'projects': [
      {'project': 'a', 'rows': [{'category': 'plan'}, {'category': 'build'}, {'category': 'build'}, {'category': 'shelved'}]},
      {'project': 'b', 'rows': [{'category': 'hands'}]},
    ],
  };
  final now = DateTime(2026, 10, 3, 12);

  test('engines come from groups and ungrouped; missing services are not counted', () {
    final d = SystemsDash.from(opsStatus: ops, backlog: backlog, fetchTimes: const [], now: now);
    expect(d.engines.length, 3);
    expect(d.healthy, 2);
    expect(d.engines.firstWhere((e) => e.name == 'isconl-vault').up, false);
  });

  test('backlog counts per live type; shelved is not live', () {
    final d = SystemsDash.from(opsStatus: ops, backlog: backlog, fetchTimes: const [], now: now);
    expect(d.byType['plan'], 1);
    expect(d.byType['build'], 2);
    expect(d.byType['hands'], 1);
    expect(d.byType.containsKey('shelved'), false);
  });

  test('sync age is measured from the newest snapshot', () {
    final d = SystemsDash.from(opsStatus: const {}, backlog: const {}, now: now, fetchTimes: [
      now.subtract(const Duration(hours: 5)),
      now.subtract(const Duration(minutes: 20)),
      null,
    ]);
    expect(d.syncAge, const Duration(minutes: 20));
    expect(SystemsDash.from(opsStatus: const {}, backlog: const {}, now: now, fetchTimes: const [null]).syncAge, isNull);
  });

  test('age colours: green, amber after 2 hours, red after 24', () {
    expect(ageTone(const Duration(minutes: 119)), C.green);
    expect(ageTone(const Duration(hours: 2)), C.amber);
    expect(ageTone(const Duration(hours: 23, minutes: 59)), C.amber);
    expect(ageTone(const Duration(hours: 24)), C.red);
    expect(ageTone(null), C.text3);
    expect(ageText(const Duration(minutes: 5)), '5 min');
    expect(ageText(const Duration(hours: 30)), '1 d');
  });

  testWidgets('App tile says a newer build is available, with no button', (t) async {
    final dash = SystemsDash.from(opsStatus: ops, backlog: backlog, fetchTimes: [now], now: now);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: SystemsDashboard(
      dash: dash, outboxPending: 0, installedVersion: '0.3.44', updateState: 'v0.3.57 available.',
      updateBusy: false, latestVersion: '0.3.57', updateAvailable: true)))));
    await t.pump();
    expect(find.textContaining('v0.3.57 available: install it from Settings'), findsOneWidget);
    expect(find.byType(OutlinedButton), findsNothing);
  });

  for (final w in [390.0, 1280.0]) {
    testWidgets('renders at $w px; a down engine shows red and opens Ops; update reason shows', (t) async {
      t.view.physicalSize = Size(w, 1800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final opened = <int>[];
      var slateOpened = 0;
      final dash = SystemsDash.from(opsStatus: ops, backlog: backlog, fetchTimes: [now.subtract(const Duration(minutes: 3))], now: now);
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: SystemsDashboard(
              dash: dash,
              outboxPending: 2,
              installedVersion: '0.3.40',
              updateState: 'Latest release v0.3.23 has no APK attached.',
              updateBusy: false,
              onOpenSub: opened.add,
              onOpenSlate: () => slateOpened++,
            ),
          ),
        ),
      ));
      await t.pump();
      expect(t.takeException(), isNull);
      expect(find.text('2 of 3 healthy'), findsOneWidget);
      expect(find.text('isconl-vault'), findsOneWidget);
      expect(find.text('3 min ago'), findsOneWidget);
      expect(find.text('Latest release v0.3.23 has no APK attached.'), findsOneWidget);
      await t.tap(find.text('FLEET HEALTH'));
      await t.tap(find.text('SLATE ROWS, LIVE'));
      expect(opened, [2]);
      expect(slateOpened, 1);
      // The App tile only shows state; installing lives in Settings.
      expect(find.text('Check for updates'), findsNothing);
    });
  }
}
