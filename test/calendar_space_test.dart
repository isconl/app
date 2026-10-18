// BI26101810: the calendar space. Three clean tabs, import and export in one secondary FAB, the strip in the nav's
// subtle green, and key dates drawn as the web console's day-count cards.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/theme.dart';
import 'package:isconl/ui/views/calendar.dart';
import 'package:isconl/ui/views/equicycle_grid_view.dart';
import 'package:isconl/util/equicycle_grid.dart';

import 'support/test_services.dart';

void main() {
  final grid = jsonDecode(File('test/fixtures/eq_grid_2026.json').readAsStringSync());

  Future<AppServices> pumpCalendar(WidgetTester t, {Object? dates}) async {
    t.view.physicalSize = const Size(900, 2200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final api = ScriptedApi({'/api/calendar/eq/grid': grid});
    final services = (await t.runAsync(() => buildTestServices(api)))!;
    services.store.calendar.value = {'events': []};
    services.store.dates.value = dates ?? {'dates': [], 'upcoming': []};
    await t.pumpWidget(AppScope(
      services: services,
      child: MaterialApp(theme: buildTheme(), home: const Scaffold(body: Stack(children: [CalendarView()]))),
    ));
    await t.pump();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
    await t.pump(const Duration(seconds: 1));
    return services;
  }

  testWidgets('the tab bar holds exactly three tabs and no action buttons', (t) async {
    await pumpCalendar(t);
    final bar = t.widget<TabBar>(find.byKey(const ValueKey('calendar-tabs')));
    expect(bar.tabs.length, 3);
    expect(find.byTooltip('Import .ics'), findsNothing);
    expect(find.byTooltip('Export .ics'), findsNothing);
    expect(find.descendant(of: find.byKey(const ValueKey('calendar-tabs')), matching: find.byType(IconButton)), findsNothing);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 11));
  });

  testWidgets('one secondary FAB above Add opens Import and Export, in the nav green', (t) async {
    await pumpCalendar(t);
    final io = find.byKey(const Key('calendar-import-export'));
    final add = find.byKey(const Key('view-fab'));
    expect(io, findsOneWidget);
    expect(add, findsOneWidget);
    expect(t.getCenter(io).dx, closeTo(t.getCenter(add).dx, 0.5), reason: 'same column');
    expect(t.getCenter(io).dy, lessThan(t.getCenter(add).dy), reason: 'stacked above Add');
    final fab = t.widget<FloatingActionButton>(find.descendant(of: io, matching: find.byType(FloatingActionButton)));
    expect(fab.backgroundColor, NavTint.bg);
    expect(fab.foregroundColor, NavTint.fg);
    await t.tap(io);
    await t.pumpAndSettle();
    expect(find.text('Import .ics'), findsOneWidget);
    expect(find.text('Export .ics'), findsOneWidget);
    expect(find.byKey(const Key('calendar-import')), findsOneWidget);
    expect(find.byKey(const Key('calendar-export')), findsOneWidget);
    await t.tapAt(const Offset(20, 20)); // dismiss the sheet
    await t.pumpAndSettle();
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 11));
  });

  testWidgets('the C05 band (season 2) and the cycle, year, moon and rains chips are the nav green, not yellow', (t) async {
    final api = ScriptedApi({'/api/calendar/eq/grid': grid});
    final services = (await t.runAsync(() => buildTestServices(api)))!;
    final store = EquicycleGrids.forTest();
    await t.runAsync(() => store.ensure(api, services.db, 2026));
    t.view.physicalSize = const Size(900, 1800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(AppScope(
      services: services,
      child: MaterialApp(
        theme: buildTheme(),
        home: Scaffold(body: SingleChildScrollView(child: EquicycleGridView(byDay: const {}, selected: null, onSelect: (_) {}, grids: store, startYear: 2026, startPage: 5))),
      ),
    ));
    await t.pump();
    for (final k in ['eq-view-cycle', 'eq-view-year', 'eq-moon', 'eq-rains']) {
      final chip = find.byKey(Key(k));
      expect(chip, findsOneWidget, reason: k);
      final theme = Theme.of(t.element(chip)).chipTheme;
      expect(theme.selectedColor, NavTint.bg, reason: k);
      expect(theme.checkmarkColor, NavTint.fg, reason: k);
    }
    final band = find.byKey(const Key('eq-band-c5'));
    expect(band, findsOneWidget);
    final colors = [
      for (final c in t.widgetList<Container>(find.descendant(of: band, matching: find.byType(Container))))
        if (c.decoration is BoxDecoration) (c.decoration as BoxDecoration).color,
    ];
    expect(colors, contains(NavTint.bg), reason: 'the band header');
    expect(colors, isNot(contains(C.amberBg)), reason: 'no yellow tint');
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 11));
  });

  testWidgets('key dates are day-count cards like the web console', (t) async {
    await pumpCalendar(t, dates: {
      'dates': [
        {'ID': 'd1', 'KIND': 'birthday', 'TITLE': 'Mum', 'DATE': '1965-03-02', 'daysSince': 22000, 'yearsTurning': 61, 'daysToNext': 134,
         'milestones': [{'label': '22,500 days', 'days': 500, 'date': '2027-02-27'}]},
        {'ID': 'd2', 'KIND': 'first graduation', 'COLOR': '#112233', 'TITLE': 'Degree', 'DATE': '2020-12-04', 'daysSince': 2144},
        {'ID': 'd3', 'KIND': 'deadline', 'TITLE': 'Renewal', 'DATE': '2026-11-20', 'daysUntil': 33},
      ],
      'upcoming': [
        {'id': 'd3', 'title': 'Renewal', 'label': 'due', 'days': 5, 'date': '2026-11-20'},
      ],
    });
    await t.scrollUntilVisible(find.byKey(const Key('key-date-card-d1')), 300, scrollable: find.byType(Scrollable).first);
    for (final id in ['d1', 'd2', 'd3']) {
      expect(find.byKey(Key('key-date-card-$id')), findsOneWidget, reason: id);
    }
    expect(t.widget<Text>(find.byKey(const Key('key-date-number-d1'))).data, '22,000');
    expect(t.widget<Text>(find.byKey(const Key('key-date-number-d3'))).data, '33');
    expect(find.text('days since'), findsNWidgets(2));
    expect(find.text('days until'), findsOneWidget);
    expect(find.text('BACHELORS GRADUATION'), findsOneWidget, reason: 'the display label override');
    expect(find.textContaining('turns 61 in 134d'), findsOneWidget);
    expect(find.textContaining('22,500 days'), findsOneWidget, reason: 'the next milestone under the rule');
    expect(find.byKey(const Key('key-dates-soon')), findsOneWidget);
    expect(find.byKey(const Key('delete-date-d1')), findsOneWidget);
    // a card is tinted by its colour: an explicit COLOR wins over the kind
    final card2 = t.widget<Container>(find.byKey(const Key('key-date-card-d2')));
    expect((card2.decoration as BoxDecoration).color, const Color(0xFF112233).withValues(alpha: 0.08));
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 11));
  });
}
