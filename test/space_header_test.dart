// BI26101802: the shared space header (a tailored search entry, then exactly three tabs) and the spaces on it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/ui/views/codex.dart';
import 'package:isconl/ui/views/learning.dart';
import 'package:isconl/ui/views/ops.dart';
import 'package:isconl/ui/widgets/space_header.dart';

import 'console/test_services.dart';

Widget _tab(String t) => Center(child: Text('body $t'));

SpaceView _space({List<SpaceHit>? hits}) => SpaceView(
      space: 'demo',
      searchHint: 'Search demo things',
      hits: (_) => hits ?? const [],
      tabs: [SpaceTab('One', _tab('one')), SpaceTab('Two', _tab('two')), SpaceTab('Three', _tab('three'))],
    );

void main() {
  setUpAll(initSqfliteForTests);

  Future<AppServices> services(WidgetTester t) async => (await t.runAsync(() => buildTestServices(online: true)))!;
  Future<void> settle(WidgetTester t) async {
    await t.pump();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
    await t.pump(const Duration(seconds: 1));
  }

  Widget host(AppServices s, Widget child) => AppScope(services: s, child: MaterialApp(home: Scaffold(body: child)));

  test('filterHits needs every word, in any order, ignoring case, and returns nothing for an empty query', () {
    final hits = [
      const SpaceHit(title: 'Quarterly report', subtitle: 'finance'),
      const SpaceHit(title: 'Report on people', subtitle: 'hr'),
    ];
    expect(filterHits(hits, '').length, 0);
    expect(filterHits(hits, 'REPORT').length, 2);
    expect(filterHits(hits, 'report finance').map((h) => h.title), ['Quarterly report']);
    expect(filterHits(hits, 'finance report people').length, 0);
  });

  // BI26102802: the rail holds up to five destinations, so a space has two to five (three is still the usual).
  test('a space has two to five destinations', () {
    List<SpaceTab> n(int count) => [for (var i = 0; i < count; i++) SpaceTab('T$i', _tab('t$i'))];
    expect(() => SpaceView(space: 'x', searchHint: 'h', tabs: n(1)), throwsAssertionError);
    expect(() => SpaceView(space: 'x', searchHint: 'h', tabs: n(6)), throwsAssertionError);
    for (final ok in [2, 3, 5]) {
      expect(SpaceView(space: 'x', searchHint: 'h', tabs: n(ok)).tabs.length, ok);
    }
    expect(spaceTabCount, 3);
    expect(spaceMaxTabs, 5);
  });

  testWidgets('the search entry sits above exactly three tabs', (t) async {
    final s = await services(t);
    await t.pumpWidget(host(s, _space()));
    await settle(t);
    expect(find.byKey(const Key('demo-search-entry')), findsOneWidget);
    expect(find.text('Search demo things'), findsOneWidget);
    for (final l in ['One', 'Two', 'Three']) {
      expect(find.descendant(of: find.byKey(const ValueKey('demo-tabs')), matching: find.text(l)), findsOneWidget);
    }
    expect(t.widget<TabBar>(find.byKey(const ValueKey('demo-tabs'))).tabs.length, 3);
    // the entry is above the tab bar
    expect(t.getTopLeft(find.byKey(const Key('demo-search-entry'))).dy, lessThan(t.getTopLeft(find.byKey(const ValueKey('demo-tabs'))).dy));
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('searching finds a known item, and a hit that names a tab sends the space there', (t) async {
    final s = await services(t);
    await t.pumpWidget(host(s, _space(hits: const [
      SpaceHit(title: 'Alpha project', subtitle: 'the first', tab: 2),
      SpaceHit(title: 'Beta project', subtitle: 'the second', tab: 1),
    ])));
    await settle(t);
    expect(find.text('body one'), findsOneWidget);
    await t.tap(find.byKey(const Key('demo-search-entry')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('space-search-field')), 'alpha');
    await t.pumpAndSettle();
    expect(find.text('Alpha project'), findsOneWidget);
    expect(find.text('Beta project'), findsNothing);
    await t.tap(find.text('Alpha project'));
    await t.pumpAndSettle();
    expect(find.text('body three'), findsOneWidget, reason: 'the hit sent the space to its third tab');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Study wears the shared header: its entry, then Map, Campus and Tracks', (t) async {
    final s = await services(t);
    await t.pumpWidget(host(s, const LearningView()));
    await settle(t);
    expect(find.byType(SpaceView), findsOneWidget);
    expect(find.byKey(const Key('study-search-entry')), findsOneWidget);
    for (final l in ['Map', 'Campus', 'Tracks']) {
      expect(find.descendant(of: find.byKey(const ValueKey('study-tabs')), matching: find.text(l)), findsOneWidget);
    }
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 11));
  });

  testWidgets('Codex wears it too, and its search finds an idea and opens the Ideas tab', (t) async {
    final s = await services(t);
    s.store.ideas.value = {
      'ideas': [
        {'ID': 'i1', 'TITLE': 'Walkable offline maps', 'BODY': 'cache tiles', 'STAGE': 'seed', 'STATUS': 'open'},
      ],
      'stages': ['seed'],
      'stats': {},
    };
    await t.pumpWidget(host(s, const CodexView()));
    await settle(t);
    expect(find.byType(SpaceView), findsOneWidget);
    expect(find.text('Search journals and ideas'), findsOneWidget);
    expect(find.text('what you thought, and what you did about it'), findsOneWidget);
    await t.tap(find.byKey(const Key('codex-search-entry')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('space-search-field')), 'offline maps');
    await t.pumpAndSettle();
    expect(find.text('Walkable offline maps'), findsOneWidget);
    await t.tap(find.text('Walkable offline maps'));
    await settle(t);
    expect(find.text('Walkable offline maps'), findsWidgets, reason: 'the Ideas tab shows the idea');
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 11));
  });

  testWidgets('OpSec wears it: a search over services and incidents, then Health, Services and Logs', (t) async {
    final s = await services(t);
    await t.pumpWidget(host(s, const OpsView()));
    await settle(t);
    expect(find.byType(SpaceView), findsOneWidget);
    expect(find.text('Search services and incidents'), findsOneWidget);
    for (final l in ['Health', 'Services', 'Logs']) {
      expect(find.descendant(of: find.byKey(const ValueKey('opsec-tabs')), matching: find.text(l)), findsOneWidget);
    }
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 16));
  });
}
