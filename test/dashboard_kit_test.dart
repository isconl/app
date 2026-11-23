import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/theme.dart';
import 'package:isconl/ui/widgets/dashboard/dashboard.dart';
import 'package:isconl/ui/widgets/dashboard/gallery.dart';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(14), child: child)),
    );

Future<void> _at(WidgetTester t, double width, Widget child) async {
  t.view.physicalSize = Size(width, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(_host(child));
  await t.pump();
}

void main() {
  for (final w in [390.0, 1280.0]) {
    group('at $w px', () {
      testWidgets('StatTile shows value, delta and unit; taps through', (t) async {
        var tapped = 0;
        await _at(t, w, StatTile(label: 'Unread', value: '42', unit: 'msgs', delta: -6, deltaGoodWhenUp: false, trend: const [3, 5, 4, 6], onTap: () => tapped++));
        expect(find.text('UNREAD'), findsOneWidget);
        expect(find.text('42'), findsOneWidget);
        expect(find.text('↓ 6'), findsOneWidget);
        expect(find.byType(Sparkline), findsOneWidget);
        await t.tap(find.byType(StatTile));
        expect(tapped, 1);
      });

      testWidgets('StatTile empty and error states', (t) async {
        await _at(t, w, const Column(children: [
          StatTile(label: 'A', value: null),
          StatTile(label: 'B', value: '7', error: 'offline'),
        ]));
        expect(find.text('No data yet'), findsOneWidget);
        expect(find.text('Could not refresh: offline'), findsOneWidget);
        expect(find.text('7'), findsOneWidget);
      });

      testWidgets('RingGauge draws with three arcs, a zero total and no arcs', (t) async {
        await _at(t, w, const Column(children: [
          RingGauge(arcs: [RingArc(5, C.green), RingArc(2, C.amber), RingArc(1, C.cyan)], total: 12, center: '8/12'),
          RingGauge(arcs: [], total: 0, center: '0'),
        ]));
        expect(find.text('8/12'), findsOneWidget);
        expect(find.text('0'), findsOneWidget);
        expect(t.takeException(), isNull);
      });

      testWidgets('BarStrip skips zero segments; all zero is empty', (t) async {
        await _at(t, w, const Column(children: [
          BarStrip(segments: [BarSegment('Done', 3, C.green), BarSegment('Gone', 0, C.red)]),
          BarStrip(segments: [BarSegment('x', 0, C.red)]),
        ]));
        expect(find.text('Done 3'), findsOneWidget);
        expect(find.textContaining('Gone'), findsNothing);
        expect(find.text('No data yet'), findsOneWidget);
      });

      testWidgets('StackedBars draws 7 and 30 days; all zero is empty', (t) async {
        const series = [BarSeries('Mail', C.cyan), BarSeries('Teams', C.violet)];
        await _at(t, w, Column(children: [
          StackedBars(series: series, days: [for (var i = 0; i < 7; i++) [i + 1.0, 1]]),
          StackedBars(series: series, days: [for (var i = 0; i < 30; i++) [i % 5 + 1.0, 0]]),
          const StackedBars(series: series, days: [[0, 0], [0, 0]]),
        ]));
        expect(find.text('Mail'), findsNWidgets(2));
        expect(find.text('No data yet'), findsOneWidget);
      });

      testWidgets('MiniList shows at most three; empty shows its message', (t) async {
        await _at(t, w, const Column(children: [
          MiniList(items: [MiniItem('a', '1'), MiniItem('b', '2'), MiniItem('c', '3'), MiniItem('d', '4')]),
          MiniList(items: [], empty: 'Nothing due'),
        ]));
        expect(find.text('c'), findsOneWidget);
        expect(find.text('d'), findsNothing);
        expect(find.text('Nothing due'), findsOneWidget);
      });

      testWidgets('the gallery renders every widget', (t) async {
        t.view.physicalSize = Size(w, 2400);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.pumpWidget(const MaterialApp(home: DashboardGallery()));
        await t.pump();
        expect(find.byType(RingGauge), findsOneWidget);
        expect(find.byType(StackedBars), findsNWidgets(2));
        expect(t.takeException(), isNull);
      });
    });
  }

  test('columns: two on a phone, four from the wide breakpoint', () {
    expect(DashboardGrid.columnsFor(390), 2);
    expect(DashboardGrid.columnsFor(1280), 4);
  });

  testWidgets('DashboardGrid packs spans into rows', (t) async {
    t.view.physicalSize = const Size(390, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(_host(const DashboardGrid(items: [
      DashItem(SizedBox(key: Key('a'), height: 40)),
      DashItem(SizedBox(key: Key('b'), height: 40)),
      DashItem(SizedBox(key: Key('c'), height: 40), span: 2),
    ])));
    final a = t.getRect(find.byKey(const Key('a')));
    final b = t.getRect(find.byKey(const Key('b')));
    final c = t.getRect(find.byKey(const Key('c')));
    expect(a.top, b.top);
    expect(c.top, greaterThan(a.top));
    expect(c.width, closeTo(a.width * 2 + 10, 0.5));
  });

  test('updatedAgo words', () {
    final now = DateTime(2026, 10, 3, 12);
    expect(updatedAgo(null), isNull);
    expect(updatedAgo(now.subtract(const Duration(minutes: 4)), now: now), 'updated 4 min ago');
    expect(updatedAgo(now.subtract(const Duration(hours: 3)), now: now), 'updated 3 h ago');
  });
}

