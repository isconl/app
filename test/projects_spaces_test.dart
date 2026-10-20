// BI26101815: Practice, Corporate, Products and Platforms wear the shared space header: the search entry above exactly
// three tabs, every card reachable in one of them, and the search names the tab that holds a known item.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/theme.dart';
import 'package:isconl/ui/views/corporate.dart';
import 'package:isconl/ui/views/practice.dart';
import 'package:isconl/ui/widgets/space_header.dart';
import 'package:isconl/ui/views/projects.dart';

import 'support/test_services.dart';

void main() {
  Future<AppServices> pump(WidgetTester t, Widget view) async {
    t.view.physicalSize = const Size(900, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final services = (await t.runAsync(() => buildTestServices(ScriptedApi({}))))!;
    services.store.projects.value = {
      'projects': [
        {'NAME': 'Alpha', 'CATEGORY': 'product', 'STATUS': 'active'},
        {'NAME': 'Beta', 'CATEGORY': 'product', 'STATUS': 'building'},
        {'NAME': 'Gamma', 'CATEGORY': 'product', 'STATUS': 'shipped'},
        {'NAME': 'Delta', 'CATEGORY': 'product', 'STATUS': 'mystery'},
        {'NAME': 'Epsilon', 'CATEGORY': 'platform', 'STATUS': 'live'},
      ],
    };
    services.store.portfolio.value = {'items': [{'title': 'My CV', 'url': 'https://x.test/cv'}]};
    services.store.corporate.value = {
      'engagements': [{'id': 'viva', 'name': 'Viva Valentia', 'role': 'Consultant', 'status': 'active', 'active': true, 'stats': {'open': 2}}],
    };
    services.store.detail('corporate', 'viva', '/api/corporate/detail?id=viva').value = {
      'name': 'Viva Valentia',
      'tasks': [{'status': 'open', 'title': 'File the report'}],
      'decisions': [{'id': 'D1', 'title': 'Pick a vendor'}],
      'risks': [],
      'people': [{'role': 'CEO', 'name': 'Swen'}],
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

  test('every status lands in exactly one tab; unknown and empty are Active', () {
    expect(projectTabOf('active'), 0);
    expect(projectTabOf(''), 0);
    expect(projectTabOf('mystery'), 0);
    expect(projectTabOf('Building'), 1);
    expect(projectTabOf('idea'), 1);
    expect(projectTabOf('shipped'), 2);
    expect(projectTabOf('archived'), 2);
  });

  testWidgets('Practice: the entry above Overview, Documents and Enquiries', (t) async {
    await pump(t, const PracticeView());
    expect(find.text('Search documents and enquiries'), findsOneWidget);
    for (final l in practiceTabLabels) {
      expect(find.text(l), findsWidgets, reason: l);
    }
    await end(t);
  });

  testWidgets('Corporate: the entry above Entities, Work and People, with the entity list on the first', (t) async {
    await pump(t, const CorporateView());
    expect(find.text('Search corporates, tasks and people'), findsOneWidget);
    for (final l in CorporateView.tabLabels) {
      expect(find.text(l), findsWidgets, reason: l);
    }
    expect(find.text('Viva Valentia'), findsWidgets);
    await end(t);
  });

  testWidgets('Products: the entry above Active, Building and Shipped, and only Active shows Alpha and Delta', (t) async {
    await pump(t, const ProjectsView(cat: 'product'));
    expect(find.text('Search products'), findsOneWidget);
    for (final l in projectTabLabels) {
      expect(find.text(l), findsWidgets, reason: l);
    }
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Delta'), findsOneWidget);
    expect(find.text('Beta'), findsNothing);
    expect(find.text('Epsilon'), findsNothing, reason: 'a platform is not a product');
    await end(t);
  });

  testWidgets('Platforms: the entry says platforms', (t) async {
    await pump(t, const ProjectsView(cat: 'platform'));
    expect(find.text('Search platforms'), findsOneWidget);
    expect(find.text('Epsilon'), findsOneWidget);
    await end(t);
  });

  testWidgets('searches name the tab that holds a known item', (t) async {
    final s = await pump(t, const SizedBox());
    late List<SpaceHit> prod, corp, prac;
    await t.pumpWidget(AppScope(services: s, child: Builder(builder: (c) {
      prod = ProjectsView.hitsFor(c, 'product');
      corp = CorporateView.hitsFor(c);
      prac = PracticeView.hitsFor(c);
      return const SizedBox();
    })));
    expect(prod.firstWhere((h) => h.title == 'Beta').tab, 1);
    expect(prod.firstWhere((h) => h.title == 'Gamma').tab, 2);
    expect(prod.firstWhere((h) => h.title == 'Delta').tab, 0);
    expect(prod.any((h) => h.title == 'Epsilon'), isFalse);
    expect(corp.firstWhere((h) => h.title == 'Viva Valentia').tab, 0);
    expect(corp.firstWhere((h) => h.title == 'File the report').tab, 1);
    expect(corp.firstWhere((h) => h.title == 'Pick a vendor').tab, 1);
    expect(corp.firstWhere((h) => h.title == 'Swen').tab, 2);
    expect(prac.firstWhere((h) => h.title == 'My CV').tab, 1);
    await end(t);
  });
}
