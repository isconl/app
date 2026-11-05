import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/ui/widgets/nav_bar.dart';

void main() {
  const items = [
    PillNavItem(icon: Icons.bolt_rounded, label: 'Hub'),
    PillNavItem(icon: Icons.task_alt_rounded, label: 'Tasks'),
    PillNavItem(icon: Icons.forum_rounded, label: 'Ask', isTab: false),
  ];

  Future<List<int>> pump(WidgetTester tester, {int index = 0}) async {
    final taps = <int>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        bottomNavigationBar: PillNavBar(
          items: items,
          index: index,
          onSelect: taps.add,
        ),
      ),
    ));
    return taps;
  }

  testWidgets('only the active item shows its label', (tester) async {
    await pump(tester, index: 0);
    await tester.pumpAndSettle();
    expect(find.text('Hub'), findsOneWidget);
    expect(find.text('Tasks'), findsNothing);
    expect(find.text('Ask'), findsNothing);
    // Every item still shows its icon.
    expect(find.byIcon(Icons.task_alt_rounded), findsOneWidget);
  });

  testWidgets('the pill follows the selected index', (tester) async {
    await pump(tester, index: 1);
    await tester.pumpAndSettle();
    expect(find.text('Tasks'), findsOneWidget);
    expect(find.text('Hub'), findsNothing);
  });

  testWidgets('tapping reports the row position', (tester) async {
    final taps = await pump(tester);
    await tester.tap(find.byIcon(Icons.task_alt_rounded));
    await tester.pumpAndSettle();
    expect(taps, [1]);
  });

  // An action item flashes the pill as press feedback, then lets it go. If the
  // release ever regresses the bar would sit with two pills open at once.
  testWidgets('an action flashes its pill and releases it', (tester) async {
    await pump(tester);
    await tester.tap(find.byIcon(Icons.forum_rounded));
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('Ask'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text('Ask'), findsNothing);
    expect(find.text('Hub'), findsOneWidget);
  });

  // 360px is the narrowest phone worth supporting; 390 is his.
  testWidgets('fits a 360px screen with five items', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        bottomNavigationBar: PillNavBar(
          index: 3,
          onSelect: (_) {},
          items: const [
            PillNavItem(icon: Icons.bolt_rounded, label: 'Hub'),
            PillNavItem(icon: Icons.task_alt_rounded, label: 'Tasks'),
            PillNavItem(icon: Icons.forum_rounded, label: 'Ask', isTab: false),
            PillNavItem(icon: Icons.notifications_rounded, label: 'Alerts'),
            PillNavItem(icon: Icons.menu_rounded, label: 'Menu', isTab: false),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Alerts'), findsOneWidget);
  });
}
