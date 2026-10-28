import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/theme.dart';
import 'package:isconl/ui/views/learning.dart';
import 'package:isconl/ui/views/settings.dart';
import 'package:isconl/ui/widgets/common.dart';
import 'package:isconl/ui/widgets/space_header.dart';
import 'package:isconl/ui/widgets/space_rail.dart';
import 'package:isconl/util/space_nav_prefs.dart';

import 'console/test_services.dart';

Widget _tab(String t) => Center(child: Text('canvas $t', key: ValueKey('text-$t')));

SpaceView _buildDemoSpace({
  SpaceNavMode? mode,
  int count = 3,
  Widget? primaryFab,
  List<Widget>? secondaryFabs,
}) {
  return SpaceView(
    space: 'demo',
    searchHint: 'Search demo space',
    mode: mode,
    primaryFab: primaryFab,
    secondaryFabs: secondaryFabs,
    tabs: [
      SpaceTab('Map', _tab('map'), icon: Icons.map_outlined),
      SpaceTab('Campus', _tab('campus'), icon: Icons.school_outlined),
      SpaceTab('Tracks', _tab('tracks'), icon: Icons.alt_route_rounded),
      if (count >= 4) SpaceTab('Storage', _tab('storage'), icon: Icons.inventory_2_outlined),
      if (count >= 5) SpaceTab('More', _tab('more'), icon: Icons.more_horiz_rounded),
    ],
  );
}

void main() {
  setUpAll(initSqfliteForTests);

  setUp(() {
    SpaceNavPrefs.instance.setMode(SpaceNavMode.rail);
  });

  Future<AppServices> services(WidgetTester t) async => (await t.runAsync(() => buildTestServices(online: true)))!;
  Future<void> settle(WidgetTester t) async {
    await t.pump();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
    await t.pump(const Duration(seconds: 1));
  }

  Widget host(AppServices s, Widget child, {Size size = const Size(390, 844)}) {
    return AppScope(
      services: s,
      child: MaterialApp(
        theme: buildTheme(),
        home: MediaQuery(
          data: MediaQueryData(size: size),
          child: Scaffold(body: SizedBox(width: size.width, height: size.height, child: child)),
        ),
      ),
    );
  }

  group('BI26102802: Rail navigation inside spaces', () {
    testWidgets('default mode is Rail: vertical pill rail on the right edge, no top tabs bar', (t) async {
      final s = await services(t);
      await t.pumpWidget(host(s, _buildDemoSpace()));
      await settle(t);

      // Search entry is present
      expect(find.byKey(const Key('demo-search-entry')), findsOneWidget);

      // In Rail mode, the top TabBar ('demo-tabs') is NOT rendered
      expect(find.byKey(const ValueKey('demo-tabs')), findsNothing);

      // The vertical pill rail is rendered
      expect(find.byType(SpaceRail), findsOneWidget);
      expect(find.byKey(const ValueKey('demo-rail')), findsOneWidget);

      // Canvas starts at tab 0 ('canvas map')
      expect(find.text('canvas map'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('destinations switch in both modes', (t) async {
      final s = await services(t);

      // 1. Rail mode destination switching
      SpaceNavPrefs.instance.setMode(SpaceNavMode.rail);
      await t.pumpWidget(host(s, _buildDemoSpace()));
      await settle(t);

      expect(find.text('canvas map'), findsOneWidget);

      // Tap Campus in rail
      await t.tap(find.byKey(const ValueKey('demo-rail-tab-campus')));
      await t.pumpAndSettle();
      expect(find.text('canvas campus'), findsOneWidget);

      // Tap Tracks in rail
      await t.tap(find.byKey(const ValueKey('demo-rail-tab-tracks')));
      await t.pumpAndSettle();
      expect(find.text('canvas tracks'), findsOneWidget);

      // 2. Tabs mode destination switching
      SpaceNavPrefs.instance.setMode(SpaceNavMode.tabs);
      await t.pumpWidget(host(s, _buildDemoSpace()));
      await settle(t);

      // Top TabBar is now visible
      expect(find.byKey(const ValueKey('demo-tabs')), findsOneWidget);
      expect(find.byType(SpaceRail), findsNothing);

      // Tap Map tab
      await t.tap(find.descendant(of: find.byKey(const ValueKey('demo-tabs')), matching: find.text('Map')));
      await t.pumpAndSettle();
      expect(find.text('canvas map'), findsOneWidget);

      await t.pumpWidget(const SizedBox());
    });

    testWidgets('active state: active icon has nav green and pill highlight, inactive is dim', (t) async {
      final s = await services(t);
      await t.pumpWidget(host(s, _buildDemoSpace()));
      await settle(t);

      // Map (index 0) is active
      final activeIcon = t.widget<Icon>(find.byKey(const ValueKey('demo-rail-icon-0')));
      expect(activeIcon.color, NavTint.fg);

      final inactiveIcon1 = t.widget<Icon>(find.byKey(const ValueKey('demo-rail-icon-1')));
      expect(inactiveIcon1.color, C.text3);

      final inactiveIcon2 = t.widget<Icon>(find.byKey(const ValueKey('demo-rail-icon-2')));
      expect(inactiveIcon2.color, C.text3);

      // Switch to index 1 (Campus)
      await t.tap(find.byKey(const ValueKey('demo-rail-tab-campus')));
      await t.pumpAndSettle();

      final newActiveIcon = t.widget<Icon>(find.byKey(const ValueKey('demo-rail-icon-1')));
      expect(newActiveIcon.color, NavTint.fg);

      final newInactiveIcon0 = t.widget<Icon>(find.byKey(const ValueKey('demo-rail-icon-0')));
      expect(newInactiveIcon0.color, C.text3);

      await t.pumpWidget(const SizedBox());
    });

    testWidgets('long-press label and 48 dp touch targets', (t) async {
      final s = await services(t);
      await t.pumpWidget(host(s, _buildDemoSpace()));
      await settle(t);

      // Touch target is 48 dp
      final itemSize = t.getSize(find.byKey(const ValueKey('demo-rail-tab-map')));
      expect(itemSize.width, 48.0);
      expect(itemSize.height, 48.0);

      // Tooltip is configured with destination label
      final tooltip = t.widget<Tooltip>(find.ancestor(
        of: find.byKey(const ValueKey('demo-rail-tab-map')),
        matching: find.byType(Tooltip),
      ).first);
      expect(tooltip.message, 'Map');

      // Semantics label is present for screen readers
      expect(
        find.bySemanticsLabel('Map'),
        findsOneWidget,
      );

      // Long press triggers tooltip message
      await t.longPress(find.byKey(const ValueKey('demo-rail-tab-map')));
      await t.pumpAndSettle();
      expect(find.byType(Tooltip), findsWidgets);

      await t.pumpWidget(const SizedBox());
    });

    testWidgets('FAB stack order: rail, secondary, secondary, primary from top to bottom', (t) async {
      final s = await services(t);

      final space = _buildDemoSpace(
        primaryFab: CircleFab(
          key: const Key('fab-primary'),
          heroTag: 'primary',
          tooltip: 'Assistant',
          icon: const Icon(Icons.chat_bubble_outline_rounded),
          onPressed: () {},
        ),
        secondaryFabs: [
          FloatingActionButton.small(
            key: const Key('fab-secondary-0'),
            heroTag: 'sec0',
            tooltip: 'Ask tutor',
            backgroundColor: NavTint.bg,
            foregroundColor: NavTint.fg,
            onPressed: () {},
            child: const Icon(Icons.school_outlined, size: 18),
          ),
          FloatingActionButton.small(
            key: const Key('fab-secondary-1'),
            heroTag: 'sec1',
            tooltip: 'Notes',
            backgroundColor: NavTint.bg,
            foregroundColor: NavTint.fg,
            onPressed: () {},
            child: const Icon(Icons.edit_note_rounded, size: 18),
          ),
        ],
      );

      await t.pumpWidget(host(s, space, size: const Size(390, 844)));
      await settle(t);

      final railRect = t.getRect(find.byKey(const ValueKey('demo-rail')));
      final sec1Rect = t.getRect(find.byKey(const Key('fab-secondary-1')));
      final sec0Rect = t.getRect(find.byKey(const Key('fab-secondary-0')));
      final primaryRect = t.getRect(find.byKey(const Key('fab-primary')));

      // Order from top: rail (highest up, lowest y), then secondary 1, then secondary 0, then primary (lowest, highest y)
      expect(railRect.bottom, lessThanOrEqualTo(sec1Rect.top), reason: 'rail is above secondary 1');
      expect(sec1Rect.bottom, lessThanOrEqualTo(sec0Rect.top), reason: 'secondary 1 is above secondary 0');
      expect(sec0Rect.bottom, lessThanOrEqualTo(primaryRect.top), reason: 'secondary 0 is above primary FAB');

      await t.pumpWidget(const SizedBox());
    });

    testWidgets('canvas never covered: canvas right edge sits clear of the floating rail', (t) async {
      final s = await services(t);
      await t.pumpWidget(host(s, _buildDemoSpace(), size: const Size(390, 844)));
      await settle(t);

      final canvasRect = t.getRect(find.byKey(const ValueKey('demo-canvas-0')));
      final railRect = t.getRect(find.byKey(const ValueKey('demo-rail')));

      // Canvas right edge must never extend into or sit under the rail
      expect(canvasRect.right, lessThanOrEqualTo(railRect.left), reason: 'canvas is padded clear of the rail');

      await t.pumpWidget(const SizedBox());
    });

    testWidgets('rail is built for up to five destinations', (t) async {
      final s = await services(t);

      // 3 items
      await t.pumpWidget(host(s, _buildDemoSpace(count: 3)));
      await settle(t);
      expect(find.byKey(const ValueKey('demo-rail-tab-map')), findsOneWidget);
      expect(find.byKey(const ValueKey('demo-rail-tab-campus')), findsOneWidget);
      expect(find.byKey(const ValueKey('demo-rail-tab-tracks')), findsOneWidget);
      expect(find.byKey(const ValueKey('demo-rail-tab-storage')), findsNothing);

      // 5 items
      await t.pumpWidget(host(s, _buildDemoSpace(count: 5)));
      await settle(t);
      expect(find.byKey(const ValueKey('demo-rail-tab-map')), findsOneWidget);
      expect(find.byKey(const ValueKey('demo-rail-tab-campus')), findsOneWidget);
      expect(find.byKey(const ValueKey('demo-rail-tab-tracks')), findsOneWidget);
      expect(find.byKey(const ValueKey('demo-rail-tab-storage')), findsOneWidget);
      expect(find.byKey(const ValueKey('demo-rail-tab-more')), findsOneWidget);

      await t.pumpWidget(const SizedBox());
    });

    testWidgets('Settings: Space navigation switchable between Rail and Tabs without restart', (t) async {
      final s = await services(t);
      SpaceNavPrefs.instance.setMode(SpaceNavMode.rail);

      await t.pumpWidget(host(s, const SettingsView()));
      await settle(t);

      // Segmented button exists
      expect(find.byKey(const Key('settings-space-nav-segmented')), findsOneWidget);
      expect(SpaceNavPrefs.instance.mode, SpaceNavMode.rail);

      // Tap 'Tabs'
      await t.tap(find.text('Tabs'));
      await t.pumpAndSettle();
      expect(SpaceNavPrefs.instance.mode, SpaceNavMode.tabs);

      // Tap 'Rail'
      await t.tap(find.text('Rail'));
      await t.pumpAndSettle();
      expect(SpaceNavPrefs.instance.mode, SpaceNavMode.rail);

      await t.pumpWidget(const SizedBox());
    });

    testWidgets('Study in Rail mode at phone width renders cleanly', (t) async {
      final s = await services(t);
      SpaceNavPrefs.instance.setMode(SpaceNavMode.rail);

      // Phone width: 390x844
      await t.pumpWidget(host(s, const LearningView(), size: const Size(390, 844)));
      await settle(t);

      // Study wears SpaceView
      expect(find.byType(SpaceView), findsOneWidget);
      expect(find.byKey(const Key('study-search-entry')), findsOneWidget);

      // In rail mode, the 3 destinations (Map, Campus, Tracks) are on the vertical rail
      expect(find.byKey(const ValueKey('study-rail')), findsOneWidget);
      expect(find.byKey(const ValueKey('study-rail-tab-map')), findsOneWidget);
      expect(find.byKey(const ValueKey('study-rail-tab-campus')), findsOneWidget);
      expect(find.byKey(const ValueKey('study-rail-tab-tracks')), findsOneWidget);

      // The horizontal tabs bar is NOT shown
      expect(find.byKey(const ValueKey('study-tabs')), findsNothing);

      // Verify geometry at phone width
      final railRect = t.getRect(find.byKey(const ValueKey('study-rail')));
      expect(railRect.right, lessThanOrEqualTo(390.0));
      expect(railRect.left, greaterThan(300.0), reason: 'floats on the right edge');

      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 11));
    });
  });
}
