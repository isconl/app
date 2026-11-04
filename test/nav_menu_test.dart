import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/ui/nav_menu.dart';

import 'support/test_services.dart';

const navFixture = [
  {
    'key': 'command',
    'label': 'COMMAND',
    'children': [
      {'view': 'today', 'label': 'Hub'},
      {'view': 'tasks', 'label': 'Slate'},
    ],
  },
  {
    'key': 'projects',
    'label': 'PROJECTS',
    'children': [
      {'view': 'projects', 'label': 'Products', 'attrs': {'data-cat': 'product'}},
      {'view': 'codex', 'label': 'Codex'},
    ],
  },
];

void main() {
  test('parseNavGroups keeps the server order and skips malformed entries', () {
    final g = parseNavGroups([
      ...navFixture,
      {'label': 'no key', 'children': []},
      {'key': 'x', 'label': 'X', 'children': [{'view': '', 'label': 'bad'}, {'view': 'ops', 'label': 'Ops'}]},
    ]);
    expect(g.map((e) => e.label), ['COMMAND', 'PROJECTS', 'X']);
    expect(g[0].items.map((e) => e.label), ['Hub', 'Slate']);
    expect(g[2].items.single.view, 'ops');
    expect(parseNavGroups({'groups': navFixture}).length, 2);
    expect(parseNavGroups(null), isEmpty);
  });

  test('routes: nav items map to app views, unknown ones to null', () {
    expect(navRouteFor(const NavItemDef(view: 'today', label: 'Hub')), 'hub');
    expect(navRouteFor(const NavItemDef(view: 'projects', label: 'Platforms', attrs: {'data-cat': 'platform'})), 'platforms');
    expect(navRouteFor(const NavItemDef(view: 'circle', label: 'Family', attrs: {'data-ring': 'family'})), 'family');
    // BI26092651 and BI26100207: Codex and Identity used to have no view in the app; both open one now.
    expect(navRouteFor(const NavItemDef(view: 'codex', label: 'Codex')), 'codex');
    expect(navRouteFor(const NavItemDef(view: 'identity', label: 'Identity')), 'identity');
    expect(navRouteFor(const NavItemDef(view: 'hologram', label: 'Nope')), isNull);
  });

  test('the theme line splits eqShort and adds the tagline when present', () {
    final state = {'time': {'eqShort': 'Cycle 5  ·  Day 12  ·  Dig'}};
    final l = cycleThemeLine(state, "Dig deep");
    expect(l!.word, 'Dig');
    expect(l.tagline, 'Dig deep');
    expect(cycleThemeLine(state, null)!.tagline, isNull);
    expect(cycleThemeLine({}, 'x'), isNull);
  });

  testWidgets('the panel slides in from the right, shows the theme and X, and lists groups in order from the cache', (tester) async {
    final services = (await tester.runAsync(() => buildTestServices(ScriptedApi({'/api/cycle-theme': {'mix': {'tagline': 'Dig deep'}}}))))!;
    services.store.nav.value = navFixture;
    services.store.state.value = {'time': {'eqShort': 'Cycle 5  ·  Day 12  ·  Dig'}};
    await tester.pumpWidget(AppScope(
      services: services,
      child: MaterialApp(home: Builder(builder: (c) => TextButton(onPressed: () => openNavMenu(c), child: const Text('open')))),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    expect(tester.getTopLeft(find.byType(NavMenuScreen)).dx, greaterThan(width * 0.8), reason: 'starts off to the right');
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byType(NavMenuScreen)).dx, 0);
    expect(find.byKey(const Key('nav-close')), findsOneWidget);
    expect(find.textContaining('Dig'), findsWidgets);
    final ys = [for (final l in ['Hub', 'Slate', 'Products', 'Codex']) tester.getTopLeft(find.text(l)).dy];
    expect(ys, [...ys]..sort());
    await tester.tap(find.byKey(const Key('nav-close')));
    await tester.pumpAndSettle();
    expect(find.byType(NavMenuScreen), findsNothing);
  });
}
