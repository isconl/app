/// BI26101808: everything the Ledger space reads, behind one place, so the answer to PL26101502 (does budget, goals,
/// income and wishlist become a ledger "plan" family for every tenant) changes this file and nothing else.
///
/// Pure parsing and arithmetic (no I/O) so the numbers on Overview are tested from fixtures. The one network call is
/// [LedgerData.transactions].
library;

import '../api/client.dart';
import '../util/current_block.dart' show nairobiClock;
import '../util/fmt.dart' as fmt;

/// One transaction row, as pulse serves it.
class Tx {
  const Tx({required this.id, required this.date, required this.type, required this.amount, required this.currency,
      required this.category, required this.description, required this.accountId, required this.vendor, required this.note});
  final String id, date, type, currency, category, description, accountId, vendor, note;
  final double amount;

  bool get isExpense => type == 'expense';
  bool get isIncome => type == 'income';
  String get month => date.length >= 7 ? date.substring(0, 7) : '';

  static Tx from(Map<String, dynamic> m) => Tx(
        id: fmt.s(m['ID']),
        date: fmt.s(m['DATE']),
        type: fmt.s(m['TYPE']),
        amount: fmt.d(m['AMOUNT']),
        currency: fmt.s(m['CURRENCY']),
        category: fmt.s(m['CATEGORY']),
        description: fmt.s(m['DESCRIPTION']),
        accountId: fmt.s(m['ACCOUNT_ID']),
        vendor: fmt.s(m['VENDOR']),
        note: fmt.s(m['NOTE']),
      );
}

/// The filters the Transactions tab sends. Empty means no filter.
class LedgerFilter {
  const LedgerFilter({this.account = '', this.category = '', this.month = '', this.type = '', this.q = ''});
  final String account, category, month, type, q;

  bool get isEmpty => account.isEmpty && category.isEmpty && month.isEmpty && type.isEmpty && q.isEmpty;

  LedgerFilter copyWith({String? account, String? category, String? month, String? type, String? q}) => LedgerFilter(
        account: account ?? this.account,
        category: category ?? this.category,
        month: month ?? this.month,
        type: type ?? this.type,
        q: q ?? this.q,
      );

  String query({int limit = 60, int offset = 0}) {
    final p = <String, String>{
      if (account.isNotEmpty) 'account': account,
      if (category.isNotEmpty) 'category': category,
      if (month.isNotEmpty) 'month': month,
      if (type.isNotEmpty) 'type': type,
      if (q.isNotEmpty) 'q': q,
      'limit': '$limit',
      if (offset > 0) 'offset': '$offset',
    };
    return p.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&');
  }

  @override
  bool operator ==(Object other) => other is LedgerFilter && other.account == account && other.category == category && other.month == month && other.type == type && other.q == q;
  @override
  int get hashCode => Object.hash(account, category, month, type, q);
}

/// A page of transactions plus what the filters can offer and how fresh the book is.
class TxPage {
  const TxPage({this.items = const [], this.total = 0, this.all = 0, this.newest, this.oldest, this.months = const [], this.categories = const []});
  final List<Tx> items;
  final int total;
  final int all;
  final String? newest;
  final String? oldest;
  final List<String> months;
  final List<String> categories;

  static TxPage from(dynamic json) {
    final m = fmt.m(json);
    return TxPage(
      items: [for (final r in fmt.lm(m['items'])) Tx.from(r)],
      total: fmt.i(m['total']),
      all: fmt.i(m['all']),
      newest: fmt.s(m['newest']).isEmpty ? null : fmt.s(m['newest']),
      oldest: fmt.s(m['oldest']).isEmpty ? null : fmt.s(m['oldest']),
      months: [for (final x in fmt.l(m['months'])) fmt.s(x)],
      categories: [for (final x in fmt.l(m['categories'])) fmt.s(x)],
    );
  }
}

class LedgerData {
  LedgerData(this.api);
  final ApiClient api;

  Future<TxPage> transactions(LedgerFilter f, {int limit = 60, int offset = 0}) async =>
      TxPage.from(await api.getJson('/api/finance/transactions?${f.query(limit: limit, offset: offset)}'));
}

/// Whole days between the newest transaction and [today] (Nairobi dates, `YYYY-MM-DD`); null with no date.
int? daysSince(String? date, DateTime today) {
  final d = DateTime.tryParse(date ?? '');
  if (d == null) return null;
  final t = DateTime.utc(today.year, today.month, today.day);
  return t.difference(DateTime.utc(d.year, d.month, d.day)).inDays;
}

// ---- Envelopes -------------------------------------------------------------------------------------------------

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

/// One line of an envelope: a child of a bucket in the allocation model (`housing`, `food`, ...).
class EnvelopeLine {
  const EnvelopeLine(this.name, this.allocated, this.spent);
  final String name;
  final double allocated;
  final double spent;
  double get left => allocated - spent;
}

/// A bucket of the recursive 50-30-20 (`needs`, `wants`, `security`) with its lines.
class Envelope {
  const Envelope({required this.name, required this.share, required this.allocated, required this.spent, required this.lines});
  final String name;
  final double share;
  final double allocated;
  final double spent;
  final List<EnvelopeLine> lines;
  double get left => allocated - spent;
  bool get spendable => name == 'needs' || name == 'wants';
}

class Envelopes {
  const Envelopes({required this.month, required this.base, required this.planned, required this.envelopes, required this.unassigned});
  final String month;
  final double base;

  /// True when the allocation is on the expected income, not on income received this month.
  final bool planned;
  final List<Envelope> envelopes;

  /// This month's expense that no envelope line claimed (a blank or unknown category).
  final double unassigned;
}

/// The month's envelopes: the summary's allocation model against this month's expense rows. A row belongs to a line when
/// its category names that line (case, spaces and hyphens ignored); everything else is [Envelopes.unassigned]. Null when
/// the tenant has no allocation model, which is a real state (none is configured on engines today).
Envelopes? envelopesFrom(dynamic allocation, List<Tx> monthTx, String month) {
  final a = fmt.m(allocation);
  final buckets = fmt.lm(a['buckets']);
  if (buckets.isEmpty) return null;
  final spentBy = <String, double>{};
  var total = 0.0;
  for (final t in monthTx) {
    if (!t.isExpense || t.month != month) continue;
    total += t.amount;
    spentBy[_norm(t.category)] = (spentBy[_norm(t.category)] ?? 0) + t.amount;
  }
  var claimed = 0.0;
  final out = <Envelope>[];
  for (final b in buckets) {
    final lines = <EnvelopeLine>[];
    for (final c in fmt.lm(b['children'])) {
      final name = fmt.s(c['name']);
      final spent = spentBy[_norm(name)] ?? 0;
      claimed += spent;
      lines.add(EnvelopeLine(name, fmt.d(c['amount']), spent));
    }
    out.add(Envelope(
      name: fmt.s(b['name']),
      share: fmt.d(b['share']),
      allocated: fmt.d(b['amount']),
      spent: lines.fold(0.0, (s, l) => s + l.spent),
      lines: lines,
    ));
  }
  return Envelopes(
    month: month,
    base: fmt.d(a['base']),
    planned: a['planned'] == true,
    envelopes: out,
    unassigned: total - claimed,
  );
}

// ---- Safe to spend this week ------------------------------------------------------------------------------------

/// A bill or scheduled payment: an expense row dated after today.
class Bill {
  const Bill(this.name, this.amount, this.date);
  final String name;
  final double amount;
  final String date; // YYYY-MM-DD
}

class SafeToSpend {
  const SafeToSpend({required this.value, required this.spendableLeft, required this.unassigned, required this.bills, required this.goodUntil});

  /// What is left in this month's spendable envelopes, minus every bill due by Sunday.
  final double value;

  /// The needs and wants allocations left (allocated minus spent on their lines).
  final double spendableLeft;

  /// This month's spend no envelope claimed; it comes out of the same pool.
  final double unassigned;
  final List<Bill> bills;

  /// The Sunday this week ends (Africa/Nairobi), `YYYY-MM-DD`.
  final String goodUntil;
  double get billsTotal => bills.fold(0.0, (s, b) => s + b.amount);
  bool get short => value < 0;
}

String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// The Sunday that ends [now]'s week in Nairobi (a Sunday is its own week's end).
String weekEnd(DateTime now) {
  final n = nairobiClock(now);
  final day = DateTime.utc(n.year, n.month, n.day);
  return _iso(day.add(Duration(days: (7 - day.weekday) % 7)));
}

/// Safe to spend this week: what is left in the spendable (needs and wants) envelopes, minus unassigned spend, minus every
/// bill dated after today up to and including Sunday. A bill due the next Monday is not counted. Null with no envelopes.
SafeToSpend? safeToSpend({required Envelopes? envelopes, required List<Bill> bills, required DateTime now}) {
  if (envelopes == null) return null;
  final end = weekEnd(now);
  final today = _iso(nairobiClock(now));
  final due = [for (final b in bills) if (b.date.compareTo(today) > 0 && b.date.compareTo(end) <= 0) b]
    ..sort((a, b) => a.date.compareTo(b.date));
  final left = envelopes.envelopes.where((e) => e.spendable).fold(0.0, (s, e) => s + e.left);
  final unassigned = envelopes.unassigned;
  final billsTotal = due.fold(0.0, (s, b) => s + b.amount);
  return SafeToSpend(value: left - unassigned - billsTotal, spendableLeft: left, unassigned: unassigned, bills: due, goodUntil: end);
}

/// The bills among a month's rows: expense rows dated after today.
List<Bill> billsFrom(List<Tx> rows, DateTime now) {
  final today = _iso(nairobiClock(now));
  return [
    for (final t in rows)
      if (t.isExpense && t.date.compareTo(today) > 0)
        Bill(t.description.isEmpty ? (t.vendor.isEmpty ? t.category : t.vendor) : t.description, t.amount, t.date),
  ];
}

/// This month as `YYYY-MM`, Nairobi.
String nairobiMonth(DateTime now) => _iso(nairobiClock(now)).substring(0, 7);

/// `9 Aug` from `2026-08-09`.
String shortDateWords(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${m[d.month - 1]}';
}
