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
    expect(fab.backgroundColor, NavTint.fabBg);
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

  testWidgets('key dates: three picked on the phone, the most relevant wide, labels plain, no placeholder year', (t) async {
    String iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final now = DateTime.now();
    final soon = DateTime(now.year, now.month, now.day + 5);
    final later = DateTime(now.year, now.month, now.day + 30);
    final far = DateTime(now.year, now.month, now.day + 200);
    await pumpCalendar(t, dates: {
      'dates': [
        {'ID': 'd1', 'KIND': 'birthday', 'TITLE': 'Mum', 'DATE': '2000-${iso(soon).substring(5)}', 'RECURS': 'yearly'},
        {'ID': 'd2', 'KIND': 'first graduation', 'COLOR': '#112233', 'TITLE': 'Degree', 'DATE': '2020-12-04', 'RECURS': '-'},
        {'ID': 'd3', 'KIND': 'deadline', 'TITLE': 'Renewal', 'DATE': iso(later), 'RECURS': '-'},
        {'ID': 'd4', 'KIND': 'anniversary', 'COLOR': '#112233', 'TITLE': 'Far one', 'DATE': '2010-${iso(far).substring(5)}', 'RECURS': 'yearly'},
      ],
      'upcoming': <dynamic>[],
    });
    await t.scrollUntilVisible(find.byKey(const Key('key-date-card-d1')), 300, scrollable: find.byType(Scrollable).first);
    for (final id in ['d1', 'd3', 'd4']) {
      expect(find.byKey(Key('key-date-card-$id')), findsOneWidget, reason: id);
    }
    expect(find.byKey(const Key('key-date-card-d2')), findsNothing, reason: 'three only: a graduation 800+ days from its next round count waits');
    expect(find.byKey(const Key('key-dates-all')), findsOneWidget);
    final wide = t.getRect(find.byKey(const Key('key-date-card-d1')));
    final square = t.getRect(find.byKey(const Key('key-date-card-d3')));
    expect(wide.width, greaterThan(square.width * 1.8), reason: 'the most relevant spans the width');
    expect(t.widget<Text>(find.byKey(const Key('key-date-number-d1'))).data, '5');
    expect(t.widget<Text>(find.byKey(const Key('key-date-unit-d1'))).data, 'DAYS TO BIRTHDAY');
    expect(find.descendant(of: find.byKey(const Key('key-date-card-d1')), matching: find.textContaining('2000')), findsNothing);
    expect(find.byKey(const Key('delete-date-d1')), findsOneWidget);
    // a card is tinted by its colour: an explicit COLOR wins over the kind
    final card2 = t.widget<Container>(find.byKey(const Key('key-date-card-d4')));
    expect((card2.decoration as BoxDecoration).color, const Color(0xFF112233).withValues(alpha: 0.08));
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 11));
  });
}
