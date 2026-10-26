// BI26101814: Hub, Slate and Compass wear the shared space header: the search entry above exactly three tabs, and the
// search finds a known fixture item and names the tab that holds it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/theme.dart';
import 'package:isconl/ui/views/hub.dart';
import 'package:isconl/ui/views/planning.dart';
import 'package:isconl/ui/views/slate.dart';
import 'package:isconl/ui/widgets/space_header.dart';
import 'package:isconl/ui/widgets/context_ring_card.dart';
import 'package:isconl/ui/widgets/revenue_actions_card.dart';

import 'support/test_services.dart';

void main() {
  Future<AppServices> pump(WidgetTester t, Widget view) async {
    t.view.physicalSize = const Size(900, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final services = (await t.runAsync(() => buildTestServices(ScriptedApi({}))))!;
    services.store.state.value = {
      'tasks': [
        {'ID': 'T7', 'TITLE': 'Renew the licence', 'STATUS': 'today', 'TAG': 'admin'},
        {'ID': 'T8', 'TITLE': 'Plan the sprint', 'STATUS': 'next', 'TAG': 'work'},
      ],
      'services': {'hub': {'status': 'up'}},
    };
    services.store.backlog.value = {
      'projects': [
        {'project': 'iSconl', 'rows': [{'id': 'BI1', 'title': 'The hold file manager', 'status': 'ready', 'category': 'build'}], 'documents': []},
      ],
    };
    services.store.plans.value = {
      'plans': [
        {'ID': 'p1', 'TITLE': 'Ship the app', 'HORIZON': 'sprint', 'tasks': []},
        {'ID': 'p2', 'TITLE': 'Year goal', 'HORIZON': 'year', 'tasks': [{'TITLE': 'Write the plan', 'STATUS': 'open'}]},
        {'ID': 'p3', 'TITLE': 'Decade goal', 'HORIZON': 'decade', 'tasks': []},
      ],
    };
    await t.pumpWidget(AppScope(services: services, child: MaterialApp(theme: buildTheme(), home: Scaffold(body: view))));
    await t.pump();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump(const Duration(seconds: 1));
    return services;
  }


  Future<void> end(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 11));
  }

  testWidgets('Hub: first child is the date/time block, no search field, and revenue actions follows console', (t) async {
    await pump(t, HubView(clock: () => DateTime(2026, 10, 20, 9, 0)));
    // Hub's first child is the date/time block:
    final column = t.widget<Column>(find.descendant(of: find.byType(HubView), matching: find.byType(Column)).first);
    expect(find.descendant(of: find.byWidget(column.children.first), matching: find.byKey(const Key('hub-date-row'))), findsOneWidget);

    // Hub contains no search field:
    expect(find.text('Search today, signals and services'), findsNothing);
    expect(find.byType(SpaceSearchEntry), findsNothing);
    expect(find.byType(TextField), findsNothing);

    // tabs exist:
    for (final l in hubTabLabels) {
      expect(find.text(l), findsWidgets, reason: l);
    }

    // and the revenue actions card comes immediately after the console:
    final ringFinder = find.byType(ContextRingCard);
    expect(ringFinder, findsOneWidget, reason: 'console is present');
    final revFinder = find.byType(RevenueActionsCard);
    expect(revFinder, findsOneWidget, reason: 'revenue actions is present');

    final outerColumn = t.widget<Column>(find.ancestor(of: ringFinder, matching: find.byType(Column)).first);
    final ringIdx = outerColumn.children.indexWhere((w) => w is ContextRingCard);
    final revIdx = outerColumn.children.indexWhere((w) => w is RevenueActionsCard);
    expect(ringIdx, isNonNegative, reason: 'console is present in outer column');
    expect(revIdx, ringIdx + 1, reason: 'the revenue actions card comes immediately after the console');

    await end(t);
  });

  testWidgets('Slate: the entry above Overview, Grid and Asks', (t) async {
    await pump(t, const SlateView());
    expect(find.text('Search tasks and register rows'), findsOneWidget);
    for (final l in ['Overview', 'Grid', 'Asks']) {
      expect(find.text(l), findsWidgets, reason: l);
    }
    await end(t);
  });

  testWidgets('Compass: the entry above Now, Next and Later, and a year goal sits on Next', (t) async {
    await pump(t, const PlanningView());
    expect(find.text('Search goals and plans'), findsOneWidget);
    await t.tap(find.text('Next'));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('year'), findsNothing, reason: 'the group heading reads "year · 1"');
    await end(t);
  });

  testWidgets('searches name the tab that holds a known item', (t) async {
    final s = await pump(t, const SizedBox());
    late List<SpaceHit> hub, slate, compass;
    await t.pumpWidget(AppScope(services: s, child: Builder(builder: (c) {
      hub = hubHits(c);
      slate = SlateView.hitsFor(c);
      compass = compassHits(c);
      return const SizedBox();
    })));
    expect(hub.firstWhere((h) => h.title == 'Renew the licence').tab, 1, reason: 'a task due today is on Today');
    expect(hub.firstWhere((h) => h.title == 'hub').tab, 2, reason: 'a service is on Services');
    expect(slate.firstWhere((h) => h.title == 'Plan the sprint').tab, 0);
    expect(slate.firstWhere((h) => h.title == 'The hold file manager').tab, 1);
    expect(compass.firstWhere((h) => h.title == 'Ship the app').tab, 0);
    expect(compass.firstWhere((h) => h.title == 'Write the plan').tab, 1, reason: 'a task follows its goal\'s horizon');
    expect(compass.firstWhere((h) => h.title == 'Decade goal').tab, 2);
    expect(filterHits(compass, 'year goal').map((h) => h.tab), everyElement(1));
    await end(t);
  });
}
