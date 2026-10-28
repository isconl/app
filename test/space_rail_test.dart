import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/theme.dart';
import 'package:isconl/ui/widgets/common.dart';
import 'package:isconl/ui/widgets/space_header.dart';

/// BI26102802 (Sconl's sketch, 28 Oct 2026): inside a space, a vertical rail of icons on the right edge in place of
/// the row of tabs, above the floating buttons; Settings switches between the two, live.

/// Every destination label the app's spaces use today. A space that gains a label must add it to
/// [spaceTabIcons] (and here), or the rail would show a bare dot.
const allLabels = [
  'Now', 'Today', 'Services', 'Next', 'Later', // Hub, Compass
  'Overview', 'Grid', 'Asks', 'Transactions', 'Plan', 'Documents', 'Enquiries', // Slate, Ledger, Practice
  'Map', 'Campus', 'Tracks', 'Ideas', 'Journals', 'Scans', // Study, Codex
  'Unread', 'Waiting', 'All', 'Jira', 'Social', 'GitHub', 'Boards', 'Drafts', 'Sent', // Inbox, Tools, Deck
  'Entities', 'Work', 'People', 'Health', 'Active', 'Building', 'Shipped', // Corporate, Teams, Projects
  'Habits', 'Year', // Rhythm
  'Logs', 'Browse', 'Recent', 'Device', 'Addresses', 'Sign-ups', 'AI seats', // OpSec, Hold, Accounts
  'General', 'Study and notes', 'Account and sync', // Settings
];

/// A body that counts its builds, so the test can tell a destination was not built before it was opened.
class _Page extends StatelessWidget {
  const _Page(this.name, this.builds);
  final String name;
  final List<String> builds;

  @override
  Widget build(BuildContext context) {
    builds.add(name);
    return ListView(
      key: Key('page-$name'),
      children: [for (var i = 0; i < 80; i++) SizedBox(height: 40, child: Text('$name row $i'))],
    );
  }
}

void main() {
  late List<String> builds;

  Future<void> pumpSpace(WidgetTester t, {int count = 3, List<Widget> overlay = const []}) async {
    t.view.physicalSize = const Size(400, 800);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    const names = ['Map', 'Campus', 'Tracks', 'Ideas', 'Scans'];
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Stack(children: [
          SpaceView(
            space: 'demo',
            tabs: [for (var i = 0; i < count; i++) SpaceTab(names[i], _Page(names[i], builds))],
          ),
          ...overlay,
        ]),
      ),
    ));
    await t.pumpAndSettle();
  }

  setUp(() {
    builds = [];
    SpaceNavMode.mode.value = SpaceNav.rail;
  });
  tearDown(() => SpaceNavMode.mode.value = SpaceNav.tabs);

  testWidgets('every label in the app has its own icon', (t) async {
    final missing = allLabels.where((l) => !spaceTabIcons.containsKey(l)).toList();
    expect(missing, isEmpty, reason: 'add an icon to spaceTabIcons for each');
    expect(spaceTabIconFor(const SpaceTab('Map', SizedBox())), Icons.map_rounded);
    expect(spaceTabIconFor(const SpaceTab('Map', SizedBox(), icon: Icons.public_rounded)), Icons.public_rounded,
        reason: 'a space can override the table');
  });

  testWidgets('rail mode: one icon per destination, no tab row, the first active', (t) async {
    await pumpSpace(t);
    expect(find.byKey(const ValueKey('demo-rail')), findsOneWidget);
    expect(find.byKey(const ValueKey('demo-tabs')), findsNothing, reason: 'the rail replaces the tab row');
    for (final l in ['map', 'campus', 'tracks']) {
      expect(find.byKey(ValueKey('demo-rail-$l')), findsOneWidget);
    }
    final active = t.widget<Icon>(find.descendant(of: find.byKey(const ValueKey('demo-rail-map')), matching: find.byType(Icon)));
    final idle = t.widget<Icon>(find.descendant(of: find.byKey(const ValueKey('demo-rail-campus')), matching: find.byType(Icon)));
    expect(active.color, NavTint.fg);
    expect(idle.color, C.text3);
    expect(find.text('Map row 0'), findsOneWidget);
  });

  testWidgets('a destination is built only when first opened, then kept', (t) async {
    await pumpSpace(t);
    expect(builds.toSet(), {'Map'});
    await t.tap(find.byKey(const ValueKey('demo-rail-tracks')));
    await t.pumpAndSettle();
    expect(find.text('Tracks row 0'), findsOneWidget);
    expect(find.text('Map row 0'), findsNothing, reason: 'only the open destination is shown');
    expect(builds.contains('Campus'), isFalse, reason: 'never opened, never built');
    await t.tap(find.byKey(const ValueKey('demo-rail-map')));
    await t.pumpAndSettle();
    expect(find.text('Map row 0'), findsOneWidget);
  });

  testWidgets('each icon is a 48 dp target named for screen readers and on long press', (t) async {
    final handle = t.ensureSemantics();
    await pumpSpace(t);
    final box = t.getSize(find.byKey(const ValueKey('demo-rail-campus')));
    expect(box.width, greaterThanOrEqualTo(48));
    expect(box.height, greaterThanOrEqualTo(48));
    expect(find.bySemanticsLabel('Campus'), findsOneWidget);
    await t.longPress(find.byKey(const ValueKey('demo-rail-campus')));
    await t.pumpAndSettle();
    expect(find.text('Campus'), findsOneWidget, reason: 'the tooltip names it');
    handle.dispose();
  });

  testWidgets('the rail sits on the button column, above two small buttons', (t) async {
    await pumpSpace(t, overlay: [
      ViewFab(icon: Icons.add_rounded, tooltip: 'one', onPressed: () {}),
      ViewFab(icon: Icons.upload_rounded, tooltip: 'two', onPressed: () {}, slot: 1),
    ]);
    final rail = t.getRect(find.byKey(const ValueKey('demo-rail')));
    final upper = t.getRect(find.byKey(const Key('view-fab-1')));
    expect(rail.bottom, lessThanOrEqualTo(upper.top - 10), reason: 'rail, secondary, secondary, primary');
    expect((rail.center.dx - upper.center.dx).abs(), lessThan(1), reason: 'one column');
    expect(400 - upper.center.dx, closeTo(16 + 28, 0.5), reason: "on the primary button's centre line");
  });

  testWidgets('it steps aside while reading down and returns on the way up', (t) async {
    await pumpSpace(t);
    double slide() => t.widget<AnimatedSlide>(find.ancestor(of: find.byKey(const ValueKey('demo-rail')), matching: find.byType(AnimatedSlide))).offset.dx;
    expect(slide(), 0);
    await t.drag(find.byKey(const Key('page-Map')), const Offset(0, -300));
    await t.pumpAndSettle();
    expect(slide(), greaterThan(0));
    await t.drag(find.byKey(const Key('page-Map')), const Offset(0, 120));
    await t.pumpAndSettle();
    expect(slide(), 0);
  });

  testWidgets('five destinations fit, and Settings switches to tabs and back live', (t) async {
    await pumpSpace(t, count: 5);
    expect(find.byKey(const ValueKey('demo-rail-scans')), findsOneWidget);
    SpaceNavMode.mode.value = SpaceNav.tabs;
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('demo-rail')), findsNothing);
    expect(find.byKey(const ValueKey('demo-tabs')), findsOneWidget);
    SpaceNavMode.mode.value = SpaceNav.rail;
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('demo-rail')), findsOneWidget);
  });
}
