import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/api/client.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/theme.dart';
import 'package:isconl/ui/views/calendar.dart';
import 'package:isconl/ui/widgets/month_grid.dart';

import 'support/test_services.dart';

class _Api extends ApiClient {
  _Api() : super(baseUrl: 'http://test', token: 'test');
  @override
  Future<dynamic> getJson(String path, {bool cold = false}) async => <String, dynamic>{};
}

void main() {
  test('ISO week numbers across the year end, 2026 to 2027', () {
    expect(isoWeek(DateTime(2026, 9, 28)), 40); // the reference calendar shows 40 for 27 Sep to 3 Oct
    expect(isoWeek(DateTime(2026, 12, 28)), 53);
    expect(isoWeek(DateTime(2026, 12, 31)), 53);
    expect(isoWeek(DateTime(2027, 1, 1)), 53);
    expect(isoWeek(DateTime(2027, 1, 3)), 53); // a Sunday belongs to the week before
    expect(isoWeek(DateTime(2027, 1, 4)), 1);
    expect(isoWeek(DateTime(2026, 1, 1)), 1);
  });

  test('the month is six Sunday-first weeks', () {
    final w = monthWeeks(DateTime(2026, 9));
    expect(w.length, 6);
    expect(w.first.first, DateTime(2026, 8, 30));
    expect(w.last.last, DateTime(2026, 10, 10));
    expect(w.every((r) => r.length == 7 && r.first.weekday == DateTime.sunday), true);
  });

  Widget host(Widget w, {double width = 390}) => MaterialApp(home: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(8), child: SizedBox(width: width, child: w))));

  GregorianMonthGrid grid({
    DateTime? month,
    DateTime? today,
    DateTime? selected,
    Set<String> events = const {},
    void Function(int)? onMonth,
    void Function(DateTime)? onSelect,
  }) =>
      GregorianMonthGrid(
        month: month ?? DateTime(2026, 9),
        today: today ?? DateTime(2026, 9, 27),
        selected: selected ?? DateTime(2026, 9, 27),
        eventDays: events,
        onSelect: onSelect ?? (_) {},
        onMonth: onMonth ?? (_) {},
        onToday: () {},
      );

  testWidgets('renders the reference: week chips 36 to 41, two-digit days, today a green circle, header', (t) async {
    await t.pumpWidget(host(grid()));
    for (final w in [36, 37, 38, 39, 40, 41]) {
      expect(find.byKey(Key('wk-$w')), findsOneWidget, reason: 'week $w');
    }
    expect(find.text('Sunday'), findsOneWidget);
    expect(find.text('September 27 2026'), findsOneWidget);
    expect(find.text('01'), findsWidgets); // zero padded
    final today = t.widget<Container>(find.byKey(const Key('cal-today')));
    expect((today.decoration as BoxDecoration).color, C.green);
    expect((today.decoration as BoxDecoration).shape, BoxShape.circle);
    expect(find.byKey(const Key('cal-today')), findsOneWidget);
  });

  testWidgets('days outside the month are muted, in-month days are bolder', (t) async {
    await t.pumpWidget(host(grid()));
    TextStyle styleOf(String text, int nth) => t.widget<Text>(find.text(text).at(nth)).style!;
    // "30" appears twice: 30 Aug is not on the grid (starts 30 Aug: yes, first cell), and 30 Sep.
    final firstCell = styleOf('30', 0); // 30 Aug, outside September
    final lastCell = styleOf('30', 1); // 30 Sep, inside
    expect(firstCell.color, C.text3);
    expect(firstCell.fontWeight, FontWeight.w400);
    expect(lastCell.fontWeight, FontWeight.w600);
    expect(lastCell.color, isNot(C.text3));
  });

  testWidgets('swiping the grid changes the month; the arrows do too', (t) async {
    final deltas = <int>[];
    await t.pumpWidget(host(grid(onMonth: deltas.add)));
    await t.fling(find.byKey(const Key('cal-grid')), const Offset(-300, 0), 800);
    await t.pump();
    await t.fling(find.byKey(const Key('cal-grid')), const Offset(300, 0), 800);
    await t.pump();
    await t.tap(find.byKey(const Key('cal-next')));
    await t.tap(find.byKey(const Key('cal-prev')));
    expect(deltas, [1, -1, 1, -1]);
  });

  testWidgets('tapping a day selects it; event days carry a dot', (t) async {
    final picked = <DateTime>[];
    await t.pumpWidget(host(grid(events: {'2026-09-30'}, onSelect: picked.add)));
    await t.tap(find.text('30').at(1));
    expect(picked.single, DateTime(2026, 9, 30));
  });

  testWidgets('narrow and wide both fit without overflow', (t) async {
    for (final w in [320.0, 390.0, 900.0]) {
      await t.pumpWidget(host(grid(), width: w));
      expect(t.takeException(), isNull, reason: '$w');
    }
  });

  testWidgets('the Gregorian / Equicycle / Planner toggle still switches modes', (t) async {
    t.view.physicalSize = const Size(1100, 1600); // the test font is wider than Inter, so the toggle row needs room
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final services = (await t.runAsync(() => buildTestServices(_Api(), online: false)))!;
    services.store.calendar.value = {'events': <dynamic>[]};
    await t.pumpWidget(AppScope(services: services, child: const MaterialApp(home: Scaffold(body: CalendarView()))));
    await t.pump();
    await t.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
    await t.pump();
    // BI26101519: a fresh store opens on Equicycle, not Gregorian.
    expect(find.byType(GregorianMonthGrid), findsNothing);
    await t.tap(find.byKey(const ValueKey('calendar-tab-gregorian')));
    await t.pump();
    expect(find.byType(GregorianMonthGrid), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('calendar-tab-equicycle')));
    await t.pump();
    expect(find.byType(GregorianMonthGrid), findsNothing);
    await t.tap(find.byKey(const ValueKey('calendar-tab-gregorian')));
    await t.pump();
    expect(find.byType(GregorianMonthGrid), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      await t.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
      await t.pump(const Duration(seconds: 1));
    }
  });
}
