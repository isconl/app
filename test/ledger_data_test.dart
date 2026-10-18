// BI26101808: the Ledger's arithmetic, from fixtures. No amounts here are Sconl's.
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/data/ledger_data.dart';

Tx tx(String id, String date, String type, double amount, {String category = '', String desc = '', String account = 'a1'}) => Tx(
    id: id, date: date, type: type, amount: amount, currency: 'KES', category: category, description: desc, accountId: account, vendor: '', note: '');

// 2026-10-18 is a Sunday (Nairobi). Use a Wednesday for most checks: 2026-10-14.
final wednesday = DateTime.utc(2026, 10, 14, 9, 0); // 12:00 Nairobi
final sunday = DateTime.utc(2026, 10, 18, 9, 0);

final allocation = {
  'base': 100000,
  'planned': false,
  'buckets': [
    {'name': 'needs', 'share': 0.5, 'amount': 50000, 'children': [
      {'name': 'housing', 'amount': 25000}, {'name': 'food', 'amount': 15000}, {'name': 'utilities', 'amount': 10000}]},
    {'name': 'wants', 'share': 0.3, 'amount': 30000, 'children': [
      {'name': 'growth', 'amount': 15000}, {'name': 'friends-family', 'amount': 9000}, {'name': 'liquid', 'amount': 6000}]},
    {'name': 'security', 'share': 0.2, 'amount': 20000, 'children': [
      {'name': 'savings', 'amount': 10000}, {'name': 'emergency', 'amount': 6000}, {'name': 'debt', 'amount': 4000}]},
  ],
};

void main() {
  group('envelopes', () {
    test('a row belongs to the line its category names; case, spaces and hyphens are ignored; the rest is unassigned', () {
      final e = envelopesFrom(allocation, [
        tx('1', '2026-10-02', 'expense', 3000, category: 'Food'),
        tx('2', '2026-10-03', 'expense', 1000, category: 'friends family'),
        tx('3', '2026-10-04', 'expense', 700),
        tx('4', '2026-10-05', 'income', 90000, category: 'salary'),
        tx('5', '2026-09-30', 'expense', 999, category: 'food'),
      ], '2026-10')!;
      final needs = e.envelopes.firstWhere((x) => x.name == 'needs');
      expect(needs.lines.firstWhere((l) => l.name == 'food').spent, 3000);
      expect(needs.spent, 3000);
      expect(needs.left, 47000);
      expect(e.envelopes.firstWhere((x) => x.name == 'wants').lines.firstWhere((l) => l.name == 'friends-family').spent, 1000);
      expect(e.unassigned, 700, reason: 'the blank-category expense; income and last month are not counted');
      expect(e.base, 100000);
      expect(e.planned, false);
    });

    test('no allocation model means no envelopes', () {
      expect(envelopesFrom(null, const [], '2026-10'), isNull);
      expect(envelopesFrom({'buckets': []}, const [], '2026-10'), isNull);
    });
  });

  group('safe to spend this week', () {
    final env = envelopesFrom(allocation, [tx('1', '2026-10-02', 'expense', 10000, category: 'housing'), tx('2', '2026-10-03', 'expense', 2000)], '2026-10');

    test('the week ends on Sunday, a Sunday is its own end', () {
      expect(weekEnd(wednesday), '2026-10-18');
      expect(weekEnd(sunday), '2026-10-18');
      expect(weekEnd(DateTime.utc(2026, 10, 19, 5, 0)), '2026-10-25', reason: 'Monday starts a new week');
    });

    test('envelopes left minus unassigned minus bills due by Sunday; a bill on Sunday counts, the next Monday does not', () {
      final r = safeToSpend(
        envelopes: env,
        now: wednesday,
        bills: [
          const Bill('Rent top-up', 4000, '2026-10-17'),
          const Bill('Internet', 1500, '2026-10-18'), // exactly Sunday
          const Bill('Insurance', 9000, '2026-10-19'), // next Monday: not this week
          const Bill('Paid already', 800, '2026-10-13'), // before today: not a bill
        ],
      )!;
      // spendable left = (50000 - 10000) + 30000 = 70000; unassigned 2000; bills 4000 + 1500
      expect(r.spendableLeft, 70000);
      expect(r.unassigned, 2000);
      expect(r.bills.map((b) => b.name), ['Rent top-up', 'Internet']);
      expect(r.billsTotal, 5500);
      expect(r.value, 62500);
      expect(r.goodUntil, '2026-10-18');
      expect(r.short, false);
    });

    test('a shortfall is negative and flagged', () {
      final r = safeToSpend(envelopes: env, now: wednesday, bills: const [Bill('Big', 90000, '2026-10-16')])!;
      expect(r.value, lessThan(0));
      expect(r.short, true);
    });

    test('with no envelopes there is no figure, not a made-up one', () {
      expect(safeToSpend(envelopes: null, bills: const [], now: wednesday), isNull);
    });

    test('bills are expense rows dated after today', () {
      final bills = billsFrom([
        tx('1', '2026-10-16', 'expense', 1200, desc: 'Water'),
        tx('2', '2026-10-14', 'expense', 500, desc: 'Today'),
        tx('3', '2026-10-17', 'income', 900),
      ], wednesday);
      expect(bills.map((b) => b.name), ['Water']);
    });
  });

  group('filters and pages', () {
    test('the query carries only the filters that are set', () {
      expect(const LedgerFilter().query(), 'limit=60');
      expect(const LedgerFilter(month: '2026-08', q: 'naivas groceries').query(limit: 20, offset: 40), 'month=2026-08&q=naivas+groceries&limit=20&offset=40');
      expect(const LedgerFilter().isEmpty, true);
      expect(const LedgerFilter(account: 'a1').isEmpty, false);
    });

    test('a page parses rows, counts, months and the newest date', () {
      final p = TxPage.from({
        'items': [{'ID': '9', 'DATE': '2026-08-09', 'TYPE': 'expense', 'AMOUNT': '120', 'CURRENCY': 'KES', 'CATEGORY': 'food', 'DESCRIPTION': 'x', 'ACCOUNT_ID': 'a1', 'VENDOR': '-', 'NOTE': '-'}],
        'total': 2409, 'all': 2409, 'newest': '2026-08-09', 'oldest': '2026-01-01', 'months': ['2026-08', '2026-07'], 'categories': ['food'],
      });
      expect(p.items.single.amount, 120);
      expect(p.total, 2409);
      expect(p.newest, '2026-08-09');
      expect(p.months, ['2026-08', '2026-07']);
      expect(TxPage.from({}).items, isEmpty);
    });

    test('days since the newest transaction', () {
      expect(daysSince('2026-08-09', DateTime.utc(2026, 10, 18)), 70);
      expect(daysSince(null, DateTime.utc(2026, 10, 18)), isNull);
    });
  });
}
