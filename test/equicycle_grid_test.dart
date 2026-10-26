import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/theme.dart';
import 'package:isconl/util/equicycle_grid.dart';
import 'package:isconl/ui/views/equicycle_grid_view.dart';

import 'support/test_services.dart';

/// BI26100135: the Equicycle grid on the phone, drawn from a grid the calendar service produced for year 26.
void main() {
  final json = jsonDecode(File('test/fixtures/eq_grid_2026.json').readAsStringSync());

  test('the grid parses: 13 cycles of 28, D01 a Sunday, no Stillweek in 26, rains as dated ranges', () {
    final g = EqGrid.fromJson(json)!;
    expect(g.year, 2026);
    expect(g.cycles.length, 13);
    expect(g.cycles.every((c) => c.days.length == 28 && c.days.first.weekday == 'Sun'), isTrue);
    expect(g.stillweek, isNull);
    expect(g.pages, 13);
    final oct1 = g.cycles[3].days[18];
    expect((oct1.day, oct1.date, oct1.weekday), (19, '2026-10-01', 'Thu'));
    expect(g.cycles[3].days[10].markers.single.name, 'September equinox');
    expect(g.inRains('2026-10-01'), isTrue);
    expect(g.inRains('2026-09-30'), isFalse);
    expect(g.seasonNames['closing'], 'Closing cycle');
  });

  test('a long year has 14 pages; a malformed grid is refused', () {
    final long = Map<String, dynamic>.from(json as Map)..['stillweek'] = {'start': '2027-06-20', 'end': '2027-06-26', 'days': [
      for (var i = 0; i < 7; i++) {'day': i + 1, 'date': '2027-06-${20 + i}', 'weekday': 'Sun', 'markers': [], 'moon': null}
    ]};
    expect(EqGrid.fromJson(long)!.pages, 14);
    expect(EqGrid.fromJson({'cycles': []}), isNull);
    expect(EqGrid.fromJson('nope'), isNull);
  });

  test('paging crosses year edges in both directions, an unloaded neighbour counts as 13 pages', () {
    int pagesOf(int y) => y == 2027 ? 14 : 13;
    expect(eqPageStep(2026, 13, 1, pagesOf), (year: 2027, page: 1));
    expect(eqPageStep(2028, 1, -1, pagesOf), (year: 2027, page: 14));
    expect(eqPageStep(2026, 5, -1, pagesOf), (year: 2026, page: 4));
    expect(eqPageStep(2030, 1, -1, (_) => 0), (year: 2029, page: 13));
  });

  Future<void> pump(WidgetTester tester, {int page = 4}) async {
    final api = ScriptedApi({'/api/calendar/eq/grid': json});
    final services = (await tester.runAsync(() => buildTestServices(api)))!;
    final store = EquicycleGrids.forTest();
    // The service answer is real async (the snapshot store), so the store is filled outside the fake clock first.
    await tester.runAsync(() => store.ensure(api, services.db, 2026));
    await tester.pumpWidget(AppScope(
      services: services,
      child: MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: EquicycleGridView(byDay: const {'2026-10-01': [{}, {}]}, selected: null, onSelect: (_) {}, grids: store, startYear: 2026, startPage: page),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('the cycle page shows D19 as 1 Oct, the equinox on D11, the band and both overlays', (tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(tester);
    expect(tester.widget<Text>(find.byKey(const Key('eq-where'))).data, '2026 · C04 of 26');
    expect(find.byKey(const Key('eq-band-c4')), findsOneWidget);
    expect(find.text('C04 · Reap'), findsOneWidget);
    expect(find.byKey(const Key('eq-cell-2026-10-01')), findsOneWidget);
    expect(find.text('19'), findsOneWidget);
    expect(find.text('1 Oct'), findsOneWidget);
    expect(find.text('◐'), findsWidgets, reason: 'the equinox marker on 23 Sep (D11), plus the legend');
    expect(find.byKey(const Key('eq-cell-2026-09-23')), findsOneWidget);
    expect(find.text('○'), findsWidgets, reason: 'the 26 Sep full moon, with the overlay on');
    await tester.tap(find.byKey(const Key('eq-moon')));
    await tester.pump();
    expect(find.text('○'), findsNothing, reason: 'no full-moon glyph, in the grid or the legend, with the overlay off');
    expect(find.text('●'), findsNothing);
  });

  testWidgets('paging moves to the next cycle and across the year edge', (tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(tester, page: 13);
    expect(tester.widget<Text>(find.byKey(const Key('eq-where'))).data, '2026 · C13 of 26');
    await tester.tap(find.byKey(const Key('eq-prev')));
    await tester.pump();
    expect(tester.widget<Text>(find.byKey(const Key('eq-where'))).data, '2026 · C12 of 26');
  });

  testWidgets('the year view draws all 13 cycles', (tester) async {
    tester.view.physicalSize = const Size(900, 9000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(tester);
    await tester.tap(find.byKey(const Key('eq-view-year')));
    await tester.pump();
    for (var c = 1; c <= 13; c++) {
      expect(find.byKey(Key('eq-band-c$c')), findsOneWidget, reason: 'C$c');
    }
  });
}
