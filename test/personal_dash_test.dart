import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/ui/views/personal_dash_model.dart';
import 'package:isconl/ui/views/personal_dashboard.dart';

void main() {
  final today = DateTime(2026, 10, 3);
  String d(int ago) {
    final t = today.subtract(Duration(days: ago));
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }

  test('streak counts back from today and today not done yet does not break it', () {
    final logs = {
      d(1): {'a': true, 'b': true},
      d(2): {'a': true},
      d(3): {'a': true},
      d(4): {'a': false},
    };
    expect(habitStreak(logs, 'a', today), 3);
    expect(habitStreak(logs, 'b', today), 1);
    logs[d(0)] = {'a': true};
    expect(habitStreak(logs, 'a', today), 4);
  });

  test('top habits are ranked by streak and carry a 14-day rising trend', () {
    final logs = {for (var i = 0; i < 5; i++) d(i): {'a': true, 'b': i < 2}};
    final top = topHabits([{'id': 'b', 'name': 'Read'}, {'id': 'a', 'name': 'Run'}], logs, today, n: 2);
    expect(top.first.name, 'Run');
    expect(top.first.streak, 5);
    expect(top.first.last14.length, 14);
    expect(top.first.last14.last, 5);
    expect(top.first.last14.first, 0);
  });

  test('blocks progress finds the running block', () {
    final p = blocksProgress(const [], DateTime(2026, 10, 3, 9, 30));
    expect(p.currentName, 'Innovator');
    expect(p.done, 3);
    expect(p.total, 12);
  });

  Widget host(Widget w) => MaterialApp(home: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(14), child: w)));

  PersonalDashboard dash(Unlock unlock, {dynamic net = 125000}) => PersonalDashboard(
        blocks: BlocksProgress(3, 12, 'Innovator'),
        habits: [HabitTrend('a', 'Run', 5, List.filled(14, 1))],
        netWorth: net,
        currency: 'KES',
        unlock: unlock,
      );

  for (final w in [390.0, 1280.0]) {
    testWidgets('renders at $w px', (t) async {
      t.view.physicalSize = Size(w, 1800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(host(dash(() async => false)));
      expect(t.takeException(), isNull);
      expect(find.text('3/12'), findsOneWidget);
      expect(find.text('Innovator'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
    });
  }

  testWidgets('holdings stay masked until the device unlocks, and a refusal keeps them masked', (t) async {
    var refuse = true;
    await t.pumpWidget(host(dash(() async => !refuse)));
    expect(find.text('Tap to reveal'), findsOneWidget);
    expect(find.textContaining('125'), findsNothing);
    await t.tap(find.text('HOLDINGS'));
    await t.pump();
    expect(find.text('Tap to reveal'), findsOneWidget);
    refuse = false;
    await t.tap(find.text('HOLDINGS'));
    await t.pump();
    expect(find.text('Tap to reveal'), findsNothing);
    expect(find.textContaining('125'), findsOneWidget);
  });

  testWidgets('holdings re-mask when the app is backgrounded and when the tile leaves the screen', (t) async {
    await t.pumpWidget(host(dash(() async => true)));
    await t.tap(find.text('HOLDINGS'));
    await t.pump();
    expect(find.textContaining('125'), findsOneWidget);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await t.pump();
    expect(find.text('Tap to reveal'), findsOneWidget);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump();

    await t.tap(find.text('HOLDINGS'));
    await t.pump();
    expect(find.textContaining('125'), findsOneWidget);
    await t.pumpWidget(host(const SizedBox()));
    await t.pumpWidget(host(dash(() async => true)));
    expect(find.text('Tap to reveal'), findsOneWidget);
  });

  testWidgets('no figure loaded shows the empty state, not a number', (t) async {
    await t.pumpWidget(host(dash(() async => true, net: null)));
    expect(find.text('No data yet'), findsWidgets);
    expect(find.text('Tap to reveal'), findsNothing);
  });
}
