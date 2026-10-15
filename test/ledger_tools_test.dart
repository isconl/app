import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/services/ledger_tools.dart';
import 'package:isconl/ui/views/ledger_tools.dart';
import 'package:isconl/ui/widgets/ledger_widgets.dart';

class FakeLedger implements LedgerApi {
  final calls = <String>[];
  int summaryCalls = 0;
  var accounts = [
    const LedgerAccount(id: 'a1', name: 'M-Pesa', type: 'mobile-money', balance: '1200'),
    const LedgerAccount(id: 'a2', name: 'Loan', type: 'debt', balance: '5000'),
  ];
  var streams = [const IncomeStream(id: 'i1', name: 'Salary', expected: 90000, dueDay: 5, recurs: 'monthly', overdue: true)];
  var groups = [const ReviewGroup(vendor: 'Naivas', category: 'wants/liquid', confidence: 'low', count: 3, total: 4500, sample: 'NAIVAS 123')];
  var poss = [const Possession(id: 'p1', item: 'Laptop', category: 'electronics', value: '90000')];
  var vents = [const Venture(id: 'v1', name: 'WellPath', kind: 'saas', category: 'product', metrics: {'mrr': '12'})];

  @override
  Future<LedgerSummary> summary() async {
    summaryCalls++;
    return LedgerSummary(accounts: accounts, streams: streams, goals: const [LedgerGoal(title: 'Emergency fund', target: 100, current: 25)], expectedMonthly: 90000);
  }

  @override
  Future<void> setBalance(String id, String balance) async => calls.add('balance:$id:$balance');
  @override
  Future<void> renameAccount(String id, String name) async => calls.add('rename:$id:$name');
  @override
  Future<void> addAccount({required String name, required String type, required String balance}) async => calls.add('addAccount:$name:$type:$balance');
  @override
  Future<void> addGoal({required String title, required String target, String due = ''}) async => calls.add('goal:$title:$target');
  @override
  Future<void> addIncome({required String name, required String amount, required String recurs, String day = '', String source = '', String match = ''}) async =>
      calls.add('income:$name:$amount');
  @override
  Future<void> setIncomeStatus(String id, String status) async => calls.add('income-status:$id:$status');
  @override
  Future<String> snapshot() async {
    calls.add('snapshot');
    return '85000';
  }

  @override
  Future<List<ReviewGroup>> review() async => groups;
  @override
  Future<int> resolve({required String vendor, required String category, required String newCategory}) async {
    calls.add('resolve:$vendor:$category>$newCategory');
    groups = const [];
    return 3;
  }

  @override
  Future<({String filename, List<int> bytes})> report(ReportPeriod p, {bool pdf = false}) async => (filename: 'r', bytes: [1]);
  @override
  Future<List<String>> exportToOneDrive(ReportPeriod p, List<String> formats) async {
    calls.add('export:${formats.join(',')}');
    return ['a.pdf'];
  }

  @override
  Future<List<Possession>> possessions() async => poss;
  @override
  Future<void> upsertPossession(Map<String, String> fields, {String id = ''}) async => calls.add('poss:${fields['item']}:$id');
  @override
  Future<void> deletePossession(String id) async => calls.add('poss-del:$id');
  @override
  Future<List<Venture>> ventures({bool refresh = false}) async => vents;
  @override
  Future<void> upsertVenture(Map<String, String> fields, {String id = ''}) async => calls.add('vent:${fields['name']}:$id');
  @override
  Future<void> deleteVenture(String id) async => calls.add('vent-del:$id');
  @override
  Future<int> discoverVentures() async => 2;
}

Widget host(Widget w) => MaterialApp(home: Scaffold(body: w));

void main() {
  test('report periods and queries', () {
    final p = ReportPeriod.presets(DateTime(2026, 3, 10));
    expect(p['This month']!.query, 'from=2026-03-01&to=2026-03-10');
    expect(p['Last month']!.query, 'from=2026-02-01&to=2026-02-28');
    expect(p['All time']!.query, 'all=1');
    expect(p['All time']!.toJson(), {'all': true});
  });

  testWidgets('locked: nothing is fetched, no figure is drawn, then Unlock opens it', (t) async {
    final api = FakeLedger();
    var asked = 0;
    await t.pumpWidget(host(LedgerToolsScreen(api: api, unlock: () async {
      asked++;
      return asked > 1;
    })));
    expect(find.text('The ledger is private'), findsOneWidget);
    expect(find.textContaining('KES'), findsNothing);
    expect(api.summaryCalls, 0);
    await t.tap(find.byKey(const Key('ledger-unlock')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('ledger-locked-note')), findsOneWidget);
    expect(api.summaryCalls, 0);
    await t.tap(find.byKey(const Key('ledger-unlock')));
    await t.pumpAndSettle();
    expect(find.text('M-Pesa'), findsOneWidget);
    expect(api.summaryCalls, greaterThan(0));
  });

  testWidgets('accounts: balance, rename, add, goal, snapshot', (t) async {
    final api = FakeLedger();
    await t.pumpWidget(host(AccountsTab(api: api)));
    await t.pumpAndSettle();
    expect(find.textContaining('-KES 5,000'), findsOneWidget, reason: 'a debt shows as negative');
    await t.tap(find.byKey(const Key('bal-a1')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('field-balance')), '1500');
    await t.tap(find.byKey(const Key('dialog-save')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('ren-a1')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('field-name')), 'M-Pesa main');
    await t.tap(find.byKey(const Key('dialog-save')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('add-goal')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('field-title')), 'Car');
    await t.tap(find.byKey(const Key('dialog-save')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('snapshot')));
    await t.pumpAndSettle();
    expect(api.calls, ['balance:a1:1500', 'rename:a1:M-Pesa main', 'goal:Car:0', 'snapshot']);
    expect(find.textContaining('Position frozen: 85000'), findsOneWidget);
  });

  testWidgets('income: an overdue stream says so and pause is one tap', (t) async {
    final api = FakeLedger();
    await t.pumpWidget(host(IncomeTab(api: api)));
    await t.pumpAndSettle();
    expect(find.text('not yet in: chase it'), findsOneWidget);
    await t.tap(find.byKey(const Key('toggle-i1')));
    await t.pumpAndSettle();
    expect(api.calls, ['income-status:i1:paused']);
  });

  testWidgets('review: resolve moves a group and reports the count', (t) async {
    final api = FakeLedger();
    await t.pumpWidget(host(ReviewTab(api: api)));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('review-save-Naivas')));
    await t.pumpAndSettle();
    expect(api.calls, ['resolve:Naivas:wants/liquid>wants/liquid']);
    expect(find.text('3 transactions moved to wants/liquid.'), findsOneWidget);
    expect(find.byKey(const Key('review-empty')), findsOneWidget);
  });

  testWidgets('report: export asks first and only then writes', (t) async {
    final api = FakeLedger();
    await t.pumpWidget(host(ReportTab(api: api, now: () => DateTime(2026, 3, 10))));
    await t.tap(find.byKey(const Key('report-export')));
    await t.pumpAndSettle();
    expect(find.text('Save to your OneDrive?'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(api.calls, isEmpty);
    await t.tap(find.byKey(const Key('report-export')));
    await t.pumpAndSettle();
    await t.tap(find.text('Save it'));
    await t.pumpAndSettle();
    expect(api.calls, ['export:pdf,csv']);
  });

  testWidgets('assets: delete asks to confirm, for a possession and for a venture', (t) async {
    final api = FakeLedger();
    await t.pumpWidget(host(AssetsTab(api: api)));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('poss-del-p1')));
    await t.pumpAndSettle();
    expect(find.text('Discard "Laptop"?'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(api.calls, isEmpty);
    await t.tap(find.byKey(const Key('poss-del-p1')));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Discard'));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.byKey(const Key('vent-del-v1')), 200, scrollable: find.byType(Scrollable).first);
    await t.tap(find.byKey(const Key('vent-del-v1')));
    await t.pumpAndSettle();
    expect(find.text('Discard "WellPath"?'), findsOneWidget);
    await t.tap(find.widgetWithText(FilledButton, 'Discard'));
    await t.pumpAndSettle();
    expect(api.calls, ['poss-del:p1', 'vent-del:v1']);
  });

  testWidgets('assets: adding a possession needs a name; discover reports the count', (t) async {
    final api = FakeLedger();
    await t.pumpWidget(host(AssetsTab(api: api)));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('add-possession')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('dialog-save')));
    await t.pumpAndSettle();
    expect(find.text('Name the item first.'), findsOneWidget);
    expect(api.calls, isEmpty);
    await t.tap(find.byKey(const Key('discover')));
    await t.pumpAndSettle();
    expect(find.textContaining('2 new venture candidates added'), findsOneWidget);
  });
}
