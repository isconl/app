import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/ui/nav_menu.dart';
import 'package:isconl/ui/shell.dart';
import 'package:isconl/ui/views/codex.dart';
import 'package:isconl/ui/views/identity.dart';
import 'package:isconl/ui/views/ideas.dart';
import 'package:isconl/ui/views/journal.dart';
import 'package:isconl/ui/views/spaces.dart';

import 'console/test_services.dart';

/// BI26092651 and BI26100207: Codex (Journals · Ideas · Scans) and Identity.
void main() {
  setUpAll(initSqfliteForTests);

  Future<AppServices> services(WidgetTester tester, {bool online = true}) async =>
      (await tester.runAsync(() => buildTestServices(online: online)))!;

  /// Lets snapshot queries (real sqlite, real time) finish, then draws what they returned.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump(const Duration(seconds: 1));
  }

  Widget host(AppServices s, Widget child) =>
      AppScope(services: s, child: MaterialApp(home: Scaffold(body: child)));

  group('navigation', () {
    test('the hub nav items Codex and Identity now open a view, and the old routes still work', () {
      expect(viewForNavRoute('codex')!.$1, isA<CodexView>());
      expect(viewForNavRoute('codex')!.$2, 'Codex');
      expect(viewForNavRoute('identity')!.$1, isA<IdentityView>());
      expect(viewForNavRoute('identity')!.$2, 'Identity');
      expect(viewForNavRoute('journal')!.$1, isA<JournalView>(), reason: 'routes unchanged');
      expect(viewForNavRoute('ideas')!.$1, isA<IdeasView>(), reason: 'routes unchanged');
      expect(navRouteFor(const NavItemDef(view: 'codex', label: 'Codex')), 'codex');
      expect(navRouteFor(const NavItemDef(view: 'identity', label: 'Identity')), 'identity');
    });

    test('Journal and Ideas are no longer separate top-level menu items', () {
      final labels = kMobileOnlyItems.map((e) => e.$1).toList();
      expect(labels, isNot(contains('Journal')));
      expect(labels, isNot(contains('Ideas')));
      expect(labels, contains('Channels'), reason: 'the rest of the mobile-only list is untouched');
    });
  });

  group('Codex', () {
    testWidgets('three tabs under the web subtitle; Journals first, Ideas and Scans one tap away', (tester) async {
      final s = await services(tester);
      await tester.pumpWidget(host(s, const CodexView()));
      await settle(tester);
      expect(find.text('what you thought, and what you did about it'), findsOneWidget);
      for (final t in ['Journals', 'Ideas', 'Scans']) {
        expect(find.descendant(of: find.byKey(const ValueKey('codex-tabs')), matching: find.text(t)), findsOneWidget);
      }
      expect(find.byType(JournalView), findsOneWidget);
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('codex-tabs')), matching: find.text('Ideas')));
      await settle(tester);
      expect(find.byType(IdeasView), findsOneWidget);
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('codex-tabs')), matching: find.text('Scans')));
      await settle(tester);
      expect(find.text('No scans yet'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 11));
    });
  });

  group('Identity', () {
    testWidgets('lists Visionary, Innovator, Creator in the web order, then All spaces', (tester) async {
      final s = await services(tester);
      await tester.pumpWidget(host(s, const IdentityView()));
      await tester.pump();
      final order = ['Visionary', 'Innovator', 'Creator'];
      final ys = [for (final n in order) tester.getTopLeft(find.text(n)).dy];
      expect(ys, orderedEquals([...ys]..sort()), reason: 'in the web console\'s order');
      expect(find.text('People, decisions, the record'), findsOneWidget);
      expect(find.text('All spaces'), findsOneWidget);
    });

    testWidgets('each archetype opens the space it always did, All spaces opens them all', (tester) async {
      final s = await services(tester);
      await tester.pumpWidget(host(s, const IdentityView()));
      await tester.pump();
      for (final (key, axis) in [('identity-VIS', 'VIS'), ('identity-INN', 'INN'), ('identity-CRE', 'CRE')]) {
        await tester.tap(find.byKey(ValueKey(key)));
        await settle(tester);
        final view = tester.widget<SpacesView>(find.byType(SpacesView));
        expect(view.axis, axis);
        Navigator.of(tester.element(find.byType(SpacesView))).pop();
        await settle(tester);
      }
      await tester.tap(find.byKey(const ValueKey('identity-all')));
      await settle(tester);
      expect(tester.widget<SpacesView>(find.byType(SpacesView)).axis, isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 11));
    });
  });

  group('Make it a task', () {
    Map<String, dynamic> idea({String id = 'IDEA-7'}) => {'ID': id, 'TITLE': 'Offline-first receipts', 'STAGE': 'spark'};

    testWidgets('creates the task through the tasks API and moves the idea to acted when the server offers that stage', (tester) async {
      final s = await services(tester);
      final api = s.api as TestApiClient;
      final r = (await tester.runAsync(() => promoteIdeaToTask(s, idea(), ['spark', 'acted'])))!;
      expect(r.outcome, PromoteOutcome.done);
      expect(r.stageMoved, isTrue);
      final task = api.posts.firstWhere((p) => p.path == '/api/tasks');
      expect(task.body['title'], 'Offline-first receipts');
      expect(task.body['tag'], 'idea');
      expect(task.body['status'], 'backlog');
      final upd = api.posts.firstWhere((p) => p.path == '/api/ideas/update');
      expect(upd.body, {'id': 'IDEA-7', 'stage': 'acted'});
    });

    testWidgets('when the server has no acted stage the task is still made and the idea is left alone', (tester) async {
      final s = await services(tester);
      final api = s.api as TestApiClient;
      final r = (await tester.runAsync(() => promoteIdeaToTask(s, idea(), ['spark', 'explore'])))!;
      expect(r.outcome, PromoteOutcome.done);
      expect(r.stageMoved, isFalse);
      expect(api.posts.where((p) => p.path == '/api/ideas/update'), isEmpty);
      expect(api.posts.where((p) => p.path == '/api/tasks'), hasLength(1));
    });

    testWidgets('offline, the task is queued like every other write', (tester) async {
      final s = await services(tester, online: false);
      final api = s.api as TestApiClient;
      final r = (await tester.runAsync(() => promoteIdeaToTask(s, idea(), ['acted'])))!;
      expect(r.outcome, PromoteOutcome.queued);
      expect(api.posts, isEmpty, reason: 'nothing is sent while offline');
    });

    testWidgets('an idea that has not synced yet cannot be promoted', (tester) async {
      final s = await services(tester);
      final api = s.api as TestApiClient;
      final r = (await tester.runAsync(() => promoteIdeaToTask(s, idea(id: 'QUEUED'), ['acted'])))!;
      expect(r.outcome, PromoteOutcome.failed);
      expect(r.error, contains('not synced'));
      expect(api.posts, isEmpty);
    });
  });
}
