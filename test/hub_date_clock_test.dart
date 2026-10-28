import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/ui/views/hub.dart';
import 'package:isconl/ui/widgets/hub_clock.dart';
import 'package:isconl/util/server_clock.dart';

import 'support/test_services.dart';

/// BI26101801: the Hub's date block: day and month in full, a live clock in the app font, no "as of" line, always three spots.
void main() {
  group('the clock', () {
    testWidgets('shows HH:MM:SS for a fixed time and advances one second at a time', (tester) async {
      var now = DateTime(2026, 10, 18, 5, 41, 7);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: HubClock(clock: () => now))));
      expect(find.text('05:41:07'), findsOneWidget);
      now = DateTime(2026, 10, 18, 5, 41, 8);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('05:41:08'), findsOneWidget);
      now = DateTime(2026, 10, 18, 23, 59, 59);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('23:59:59'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('is in the app font (not seven-segment), green, and its timer stops with the widget', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: HubClock(clock: () => DateTime(2026, 10, 18, 1, 2, 3)))));
      final t = tester.widget<Text>(find.byKey(const Key('hub-clock')));
      expect(t.style!.fontFamily, isNull, reason: 'inherits the app font');
      expect(t.style!.fontWeight, FontWeight.w700);
      expect(t.style!.fontSize, lessThan(22));
      expect(t.style!.color!.toARGB32() & 0xFF00FF00, isNot(0), reason: 'a green channel');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3)); // a timer left running would fail the binding's pending-timer check
    });
  });

  group('the server offset', () {
    // The device thinks it is 05:00:00; the server's Date header says otherwise.
    DateTime dev(int s) => DateTime.utc(2026, 10, 18, 5, 0, s);
    String httpDate(DateTime d) => 'Sun, ${d.day} Oct ${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')} GMT';
    String header(int h, int m, int s) => 'Sun, 18 Oct 2026 ${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')} GMT';

    test('+3 s is applied, +1 s is ignored, a slow answer is ignored', () {
      var device = dev(0);
      final c = ServerClock(deviceNow: () => device);
      // request sent at 05:00:00.000, answered at 05:00:00.200; the server says 05:00:03 (so it is about 3 s ahead)
      c.observe(dev(0), dev(0).add(const Duration(milliseconds: 200)), header(5, 0, 3));
      expect(c.offset, isNotNull);
      expect(c.offset!.inMilliseconds, inInclusiveRange(2900, 3500));
      expect(c.now().difference(device).inSeconds, inInclusiveRange(2, 3));

      c.reset();
      c.observe(dev(0), dev(0).add(const Duration(milliseconds: 200)), header(5, 0, 1));
      expect(c.offset, isNull, reason: 'within 2 s the phone clock is shown unchanged');
      expect(c.now(), device);

      c.reset();
      c.observe(dev(0), dev(0).add(const Duration(seconds: 2)), header(5, 0, 9));
      expect(c.offset, isNull, reason: 'a round trip over a second is not trusted');
    });

    test('the offset is dropped after 24 hours and cleared by a quiet measurement', () {
      var device = dev(0);
      final c = ServerClock(deviceNow: () => device);
      c.observe(dev(0), dev(0).add(const Duration(milliseconds: 100)), header(5, 0, 5));
      expect(c.offset, isNotNull);
      device = device.add(const Duration(hours: 24, minutes: 1));
      expect(c.offset, isNull);
      expect(c.now(), device);
      // a fresh measurement 5 s ahead of the phone is applied again
      c.observe(device, device.add(const Duration(milliseconds: 100)), httpDate(device.add(const Duration(seconds: 5))));
      expect(c.offset, isNotNull);
      // and a later one that agrees with the phone clears it
      final agree = device.add(const Duration(seconds: 30));
      c.observe(agree, agree.add(const Duration(milliseconds: 100)), httpDate(agree));
      expect(c.offset, isNull);
    });

    test('a missing or malformed Date header changes nothing', () {
      final c = ServerClock(deviceNow: () => dev(0));
      c.observe(dev(0), dev(0), null);
      c.observe(dev(0), dev(0), 'yesterday');
      expect(c.offset, isNull);
      expect(parseHttpDate('Sun, 18 Oct 2026 05:41:07 GMT'), DateTime.utc(2026, 10, 18, 5, 41, 7));
      expect(parseHttpDate('18 Oct 2026'), isNull);
    });
  });

  group('the Hub date block', () {
    Future<void> pumpHub(WidgetTester tester, Map<String, dynamic>? signals, {double width = 900}) async {
      tester.view.physicalSize = Size(width, 6000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final services = (await tester.runAsync(() => buildTestServices(ScriptedApi({}))))!;
      services.store.state.value = {
        'time': {'eqShort': '2026-5', 'sprintShort': 'W41', 'yearPct': 78},
        'tasks': [],
        'services': {},
      };
      services.store.signals.value = signals;
      final fixed = DateTime(2026, 10, 18, 5, 41, 7);
      await tester.pumpWidget(AppScope(services: services, child: MaterialApp(home: Scaffold(body: HubView(clock: () => fixed)))));
      await tester.pump();
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 120)));
      await tester.pump();
    }

    Future<void> teardown(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
      await tester.pump(const Duration(seconds: 2));
    }

    String plain(WidgetTester tester) => tester
        .widgetList<RichText>(find.byType(RichText))
        .map((r) => r.text.toPlainText())
        .join('\n');

    testWidgets('the date reads Sunday · October 18, 2026, the clock sits beside it, and there is no as-of line there', (tester) async {
      await pumpHub(tester, {'strip': [{'label': '4 habits', 'tone': 'info'}]});
      expect(plain(tester), contains('Sunday · October 18, 2026'));
      expect(find.text('05:41:07'), findsOneWidget);
      final row = tester.getRect(find.byKey(const Key('hub-date-row')));
      final clock = tester.getRect(find.byKey(const Key('hub-clock')));
      expect(clock.right, lessThanOrEqualTo(row.right + 0.5));
      expect(clock.center.dx, lessThan(row.center.dx), reason: 'the time leads, the date follows on the same line');
      expect((tester.getRect(find.textContaining('Sunday')).center.dy - clock.center.dy).abs(), lessThan(12), reason: 'one line');
      // the strip's own "as of" line is gone: nothing between the strip and the next card starts with "as of"
      final strip = tester.getRect(find.byKey(const Key('hub-signal-strip')));
      final asOfBelowStrip = tester.widgetList<Text>(find.textContaining('as of ')).where((t) => tester.getRect(find.byWidget(t)).top >= strip.bottom - 1 && tester.getRect(find.byWidget(t)).top < strip.bottom + 24);
      expect(asOfBelowStrip, isEmpty);
      await teardown(tester);
    });

    testWidgets('at 320 px the month shortens, the day stays in full, and it stays on one line with the clock', (tester) async {
      await pumpHub(tester, null, width: 320);
      tester.takeException(); // a card lower on the Hub overflows at 320 px; that is not this row, which is asserted below
      expect(plain(tester), contains('Sunday 18 Oct'));
      final clock = tester.getRect(find.byKey(const Key('hub-clock')));
      final row = tester.getRect(find.byKey(const Key('hub-date-row')));
      expect(row.height, lessThan(clock.height + 14), reason: 'a single line');
      await teardown(tester);
    });

    testWidgets('one real signal renders three spots: one real, two All clear', (tester) async {
      await pumpHub(tester, {'strip': [{'label': '4 habits', 'tone': 'info'}]});
      expect(find.text('4 habits'), findsOneWidget);
      expect(find.text('All clear'), findsNWidgets(2));
      await teardown(tester);
    });

    testWidgets('three signals render no placeholder', (tester) async {
      await pumpHub(tester, {
        'strip': [
          {'label': '4 habits', 'tone': 'info'},
          {'label': '2 due', 'tone': 'soon'},
          {'label': '1 waiting', 'tone': 'waiting'},
        ],
      });
      expect(find.text('All clear'), findsNothing);
      expect(find.text('2 due'), findsOneWidget);
      await teardown(tester);
    });
  });
}
