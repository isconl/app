// BI26101808: the Ledger space. Three tabs under a search, envelopes against this month's spend, safe to spend this week,
// the full transaction list with filters, and the search. Fixture data only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/data/ledger_data.dart';
import 'package:isconl/theme.dart';
import 'package:isconl/ui/views/finance.dart';

import 'support/test_services.dart';

String _month(DateTime d) => nairobiMonth(d);

void main() {
  final now = DateTime.now();
  final thisMonth = _month(now);
  final nextMonth = weekEnd(now).substring(0, 7);
  final y = now.year;

  Map<String, dynamic> row(String id, String date, String type, num amount, {String category = '', String desc = '', String account = 'a1'}) => {
        'ID': id, 'DATE': date, 'TYPE': type, 'AMOUNT': '$amount', 'CURRENCY': 'KES', 'CATEGORY': category, 'DESCRIPTION': desc,
        'ACCOUNT_ID': account, 'VENDOR': '-', 'NOTE': '-', 'TAGS': '-',
      };

  final allocation = {
    'base': 100000, 'planned': false,
    'buckets': [
      {'name': 'needs', 'share': 0.5, 'amount': 50000, 'children': [{'name': 'housing', 'amount': 25000}, {'name': 'food', 'amount': 15000}, {'name': 'utilities', 'amount': 10000}]},
      {'name': 'wants', 'share': 0.3, 'amount': 30000, 'children': [{'name': 'growth', 'amount': 15000}, {'name': 'friends-family', 'amount': 9000}, {'name': 'liquid', 'amount': 6000}]},
      {'name': 'security', 'share': 0.2, 'amount': 20000, 'children': [{'name': 'savings', 'amount': 10000}, {'name': 'emergency', 'amount': 6000}, {'name': 'debt', 'amount': 4000}]},
    ],
  };

  final summary = {
    'currency': 'KES',
    'accounts': [
      {'ID': 'a1', 'NAME': 'M-Pesa', 'TYPE': 'wallet', 'INSTITUTION': 'Safaricom', 'CURRENCY': 'KES', 'BALANCE': '1200', 'ASOF': '${y}-08-09'},
      {'ID': 'a2', 'NAME': 'Savings', 'TYPE': '-', 'INSTITUTION': 'A Bank', 'CURRENCY': 'KES', 'BALANCE': '5000', 'ASOF': '-'},
    ],
    'netWorth': {'assets': 6200, 'liabilities': 0, 'net': 6200},
    'month': {'month': thisMonth, 'income': 0, 'expense': 4000, 'netFlow': -4000},
    'incomes': {'streams': [], 'expectedMonthly': 0},
    'goals': [],
    'allocation': allocation,
    'txCount': 3,
  };

  final monthRows = [
    row('t1', '$thisMonth-02', 'expense', 3000, category: 'food', desc: 'Groceries'),
    row('t2', '$thisMonth-03', 'expense', 1000, desc: 'Mystery'),
  ];

  Map<String, Object> api(List<Map<String, dynamic>> items, {String? newest, int? total}) => {
        '/api/finance/summary': summary,
        if (nextMonth != thisMonth)
          '/api/finance/transactions?month=$nextMonth': {
            'items': const <Map<String, dynamic>>[], 'total': 0, 'all': 0, 'newest': newest ?? '${y}-08-09', 'oldest': '${y}-01-01',
            'months': ['${y}-08', '${y}-07', thisMonth], 'categories': ['food', 'transport'],
          },
        '/api/finance/transactions': {
          'items': items, 'total': total ?? items.length, 'all': total ?? items.length, 'newest': newest ?? '${y}-08-09', 'oldest': '${y}-01-01',
          'months': ['${y}-08', '${y}-07', thisMonth], 'categories': ['food', 'transport'],
        },
      };

  Future<AppServices> pump(WidgetTester t, Map<String, Object> answers, {Object? summaryOverride}) async {
    t.view.physicalSize = const Size(900, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final scripted = ScriptedApi(answers);
    final services = (await t.runAsync(() => buildTestServices(scripted)))!;
    services.store.finance.value = summaryOverride ?? summary;
    await t.pumpWidget(AppScope(services: services, child: MaterialApp(theme: buildTheme(), home: const Scaffold(body: FinanceView()))));
    await t.pump();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));
    await t.pump(const Duration(seconds: 1));
    return services;
  }

  Future<void> end(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 11));
  }

  testWidgets('the space is a search over exactly three tabs: Overview, Transactions, Plan', (t) async {
    await pump(t, api(monthRows));
    expect(find.text('Search transactions, accounts and envelopes'), findsOneWidget);
    expect(t.widget<TabBar>(find.byKey(const ValueKey('ledger-tabs'))).tabs.length, 3);
    for (final l in ['Overview', 'Transactions', 'Plan']) {
      expect(find.descendant(of: find.byKey(const ValueKey('ledger-tabs')), matching: find.text(l)), findsOneWidget);
    }
    expect(t.getTopLeft(find.byKey(const Key('ledger-search-entry'))).dy, lessThan(t.getTopLeft(find.byKey(const ValueKey('ledger-tabs'))).dy));
    await end(t);
  });

  testWidgets('Overview: envelopes show this month\'s spend against the allocation, and what no envelope claimed', (t) async {
    await pump(t, api(monthRows));
    expect(find.byKey(const Key('envelopes')), findsOneWidget);
    // food: 3,000 of 15,000; the mystery 1,000 is unassigned
    final food = find.descendant(of: find.byKey(const Key('envelope-food')), matching: find.byType(Text));
    final text = t.widgetList<Text>(food).map((x) => x.data ?? '').join(' ');
    expect(text, contains('3,000'));
    expect(text, contains('15,000'));
    expect(find.byKey(const Key('envelope-unassigned')), findsOneWidget);
    expect(t.widget<Text>(find.byKey(const Key('envelope-unassigned'))).data, contains('1,000'));
    await end(t);
  });

  testWidgets('Overview: safe to spend is the envelopes left minus unassigned spend, with the Sunday it is good until', (t) async {
    await pump(t, api(monthRows));
    expect(find.byKey(const Key('safe-to-spend')), findsOneWidget);
    // needs 50,000 + wants 30,000 - food 3,000 - unassigned 1,000 = 76,000 (no future-dated bills)
    expect(t.widget<Text>(find.byKey(const Key('safe-to-spend-value'))).data, contains('76,000'));
    expect(find.textContaining('Good until Sunday'), findsOneWidget);
    await end(t);
  });

  testWidgets('with no allocation model, Overview says so instead of inventing a number', (t) async {
    await pump(t, api(monthRows), summaryOverride: {...summary, 'allocation': null});
    expect(find.byKey(const Key('safe-to-spend-value')), findsNothing);
    expect(find.textContaining('Needs an allocation'), findsOneWidget);
    expect(find.textContaining('No allocation model is set up'), findsOneWidget);
    await end(t);
  });

  testWidgets('Overview: a book that has gone quiet is flagged, and accounts without an as-of date say so', (t) async {
    await pump(t, api(monthRows, newest: '2026-08-09'));
    expect(find.byKey(const Key('ledger-stale')), findsOneWidget);
    expect(find.textContaining('Last transaction 9 Aug'), findsOneWidget);
    expect(find.textContaining('no as-of date'), findsOneWidget);
    expect(find.textContaining('as of 9 Aug'), findsOneWidget);
    await end(t);
  });

  testWidgets('Transactions: the full list, newest first, with the count and the filters', (t) async {
    await pump(t, api([
      row('t9', '$thisMonth-09', 'expense', 120, category: 'food', desc: 'Lunch'),
      row('t8', '$thisMonth-08', 'income', 9000, desc: 'Pay'),
    ], total: 2409));
    await t.tap(find.descendant(of: find.byKey(const ValueKey('ledger-tabs')), matching: find.text('Transactions')));
    await t.pump();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 400));
    }
    expect(find.byKey(const Key('tx-t9')), findsOneWidget);
    expect(find.byKey(const Key('tx-t8')), findsOneWidget);
    expect(t.getTopLeft(find.byKey(const Key('tx-t9'))).dy, lessThan(t.getTopLeft(find.byKey(const Key('tx-t8'))).dy));
    expect(t.widget<Text>(find.byKey(const Key('tx-count'))).data, startsWith('2 of 2409'));
    for (final k in ['tx-filter-month', 'tx-filter-account', 'tx-filter-category', 'tx-filter-type']) {
      expect(find.byKey(Key(k)), findsOneWidget, reason: k);
    }
    expect(find.byKey(const Key('tx-more')), findsOneWidget);
    await t.tap(find.byKey(const Key('tx-t9')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('tx-sheet-title')), findsOneWidget);
    expect(find.text('Lunch'), findsWidgets);
    await end(t);
  });

  testWidgets('tapping an envelope line opens Transactions on that envelope', (t) async {
    final services = await pump(t, api(monthRows));
    await t.tap(find.byKey(const Key('envelope-food')));
    await t.pump();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));
    await t.pump(const Duration(seconds: 1));
    expect(find.byKey(const Key('tx-filter-clear')), findsOneWidget, reason: 'a filter is on');
    final asked = (services.api as ScriptedApi).asked.where((p) => p.contains('/api/finance/transactions') && p.contains('category=food')).toList();
    expect(asked, isNotEmpty, reason: 'the list was asked for category=food');
    await end(t);
  });

  testWidgets('Plan: the allocation as amounts', (t) async {
    await pump(t, api(monthRows));
    await t.tap(find.descendant(of: find.byKey(const ValueKey('ledger-tabs')), matching: find.text('Plan')));
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    expect(find.byKey(const Key('allocation-plan')), findsOneWidget);
    expect(find.text('NEEDS'), findsOneWidget);
    expect(find.textContaining('50% · KES 50,000'), findsOneWidget);
    await end(t);
  });

  testWidgets('the search finds a transaction on the server, an account and an envelope; an envelope sends the space to its transactions', (t) async {
    final services = await pump(t, api([row('t7', '$thisMonth-07', 'expense', 750, category: 'food', desc: 'Naivas groceries')]));
    await t.tap(find.byKey(const Key('ledger-search-entry')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('ledger-search-field')), 'food');
    await t.pump(const Duration(milliseconds: 400));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));
    await t.pump(const Duration(seconds: 1));
    expect(find.byKey(const Key('hit-envelope-food')), findsOneWidget);
    expect(find.byKey(const Key('hit-tx-t7')), findsOneWidget);
    expect((services.api as ScriptedApi).asked.any((p) => p.contains('q=food')), isTrue, reason: 'the text went to the server');
    await t.enterText(find.byKey(const Key('ledger-search-field')), 'safaricom');
    await t.pump(const Duration(milliseconds: 400));
    await t.pump(const Duration(seconds: 1));
    expect(find.byKey(const Key('hit-account-a1')), findsOneWidget);
    await t.tap(find.byKey(const Key('hit-account-a1')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('tx-filter-clear')), findsOneWidget, reason: 'the space opened Transactions on the account');
    await end(t);
  });
}
