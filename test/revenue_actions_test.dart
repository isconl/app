import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/data/accounts_data.dart';
import 'package:isconl/services/revenue_actions.dart';
import 'package:isconl/ui/widgets/revenue_actions_card.dart';
import 'package:slate_ui/slate_ui.dart';

import 'support/test_services.dart';

/// BI26102202: Today's revenue actions.
void main() {
  RowSummary row(String id, String title, {String? subset, String status = 'ready'}) =>
      RowSummary(id: id, project: 'viva', type: 'work', title: title, status: status, subset: subset);

  group('rules', () {
    test('only growth, practice, enquiries, first-tenant and marketing-titled open rows, at most five, in order', () {
      final all = [
        row('A', 'x', subset: 'fix'),
        row('B', 'one', subset: 'growth'),
        row('C', 'two', subset: 'practice'),
        row('D', 'Marketing: three'),
        row('E', 'done one', subset: 'growth', status: 'done'),
        row('F', 'four', subset: 'enquiries'),
        row('G', 'five', subset: 'first-tenant'),
        row('H', 'six', subset: 'growth'),
      ];
      expect(pickRevenueRows(all).map((r) => r.id), ['B', 'C', 'D', 'F', 'G']);
    });

    test('amber after 7 days, red after 14, none before any conversation', () {
      expect(clientGap(null), ClientGap.none);
      expect(clientGap(6), ClientGap.ok);
      expect(clientGap(7), ClientGap.amber);
      expect(clientGap(13), ClientGap.amber);
      expect(clientGap(14), ClientGap.red);
    });

    test('days count from the newest client or lead touch only', () {
      final now = DateTime(2026, 10, 24, 9);
      final people = [
        {'NAME': 'a', 'TAGS': 'client', 'lastTouch': '2026-10-20T08:00:00'},
        {'NAME': 'b', 'TAGS': 'lead, warm', 'lastTouch': '2026-10-10T08:00:00'},
        {'NAME': 'c', 'TAGS': 'friend', 'lastTouch': '2026-10-23T08:00:00'},
      ];
      expect(daysSinceClientConversation(people, now), 4);
      expect(daysSinceClientConversation([people[2]], now), isNull);
      expect(gapLine(null), 'No client conversation recorded yet');
      expect(gapLine(4), 'Last client conversation: 4 days ago');
    });
  });

  group('the card', () {
    Future<void> pump(WidgetTester tester, List<RowSummary> rows, Object? circle, {Future<SpendSummary> Function()? spend, void Function(BuildContext)? onOpenAccounts}) async {
      tester.view.physicalSize = const Size(400, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final services = (await tester.runAsync(() => buildTestServices(ScriptedApi({}))))!;
      services.store.circle.value = circle;
      await tester.pumpWidget(AppScope(
        services: services,
        child: MaterialApp(home: Scaffold(body: RevenueActionsCard(rows: () async => rows, clock: () => DateTime(2026, 10, 24, 9), spend: spend, onOpenAccounts: onOpenAccounts))),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    Future<void> teardown(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
      await tester.pump(const Duration(seconds: 2));
    }

    testWidgets('shows the rows and the day count, amber at 8 days', (tester) async {
      await pump(tester, [row('B', 'Book a diagnostic', subset: 'practice')], {
        'people': [{'NAME': 'Amina', 'ID': 'p1', 'TAGS': 'client', 'lastTouch': '2026-10-16T08:00:00'}],
      });
      expect(find.byKey(const Key('revenue-row-B')), findsOneWidget);
      expect(find.text('Last client conversation: 8 days ago'), findsOneWidget);
      final t = tester.widget<Text>(find.byKey(const Key('revenue-gap')));
      expect(t.style!.color, isNot(equals(const TextStyle().color)));
      await teardown(tester);
    });

    testWidgets('empty state and no conversation yet', (tester) async {
      await pump(tester, const [], {'people': []});
      expect(find.text('No revenue actions open'), findsOneWidget);
      expect(find.text('No client conversation recorded yet'), findsOneWidget);
      await teardown(tester);
    });

    // BI26102403: money out beside money in.
    final spent = SpendSummary(
      totals: {'KES': 4200, 'USD': 45},
      unknownCost: 3,
      renewals: [
        RenewalChip(id: 'claude-team', service: 'Claude Team', amount: 30, currency: 'USD', renewsOn: DateTime(2026, 10, 26)),
        RenewalChip(id: 'gemini', service: 'Gemini', amount: 20, currency: 'USD', renewsOn: DateTime(2026, 11, 20)),
      ],
    );

    testWidgets('shows one total per currency, the count with no cost set, and the renewals soonest first', (tester) async {
      await pump(tester, const [], {'people': []}, spend: () async => spent);
      expect(find.text('Out this month: KES 4,200 · USD 45 (3 with no cost set)'), findsOneWidget);
      expect(find.text('Claude Team, 26 Oct, USD 30'), findsOneWidget);
      expect(find.text('Gemini, 20 Nov, USD 20'), findsOneWidget);
      final first = tester.getTopLeft(find.byKey(const Key('spend-chip-claude-team'))), second = tester.getTopLeft(find.byKey(const Key('spend-chip-gemini')));
      expect(first.dy < second.dy || (first.dy == second.dy && first.dx < second.dx), isTrue, reason: 'soonest renewal comes first');
      await teardown(tester);
    });

    testWidgets('a renewal inside 3 days is amber, a later one is not', (tester) async {
      await pump(tester, const [], {'people': []}, spend: () async => spent);
      Color? colour(String text) => tester.widget<Text>(find.text(text)).style!.color;
      expect(colour('Claude Team, 26 Oct, USD 30'), isNot(equals(colour('Gemini, 20 Nov, USD 20'))));
      await teardown(tester);
    });

    testWidgets('a tap on the line or a chip opens the Sign-ups tab', (tester) async {
      var opened = 0;
      await pump(tester, const [], {'people': []}, spend: () async => spent, onOpenAccounts: (_) => opened++);
      await tester.tap(find.byKey(const Key('spend-line')));
      await tester.tap(find.byKey(const Key('spend-chip-gemini')));
      expect(opened, 2);
      await teardown(tester);
    });

    testWidgets('with no paid sign-ups the line says so; with the read failing there is no line at all', (tester) async {
      await pump(tester, const [], {'people': []}, spend: () async => const SpendSummary());
      expect(find.text('No paid sign-ups recorded'), findsOneWidget);
      await teardown(tester);
      await pump(tester, const [], {'people': []}, spend: () async => throw const AccountsException('down'));
      expect(find.byKey(const Key('spend-line')), findsNothing);
      await teardown(tester);
    });

    testWidgets('sign-ups with no cost never read as zero', (tester) async {
      await pump(tester, const [], {'people': []}, spend: () async => const SpendSummary(unknownCost: 2));
      expect(find.text('Out this month: nothing priced yet (2 with no cost set)'), findsOneWidget);
      await teardown(tester);
    });
  });
}
