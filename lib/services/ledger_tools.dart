import '../api/client.dart';

/// BI26100509: the console's finance routes beyond reading the summary: accounts, goals, income, the review queue,
/// the report and its export, snapshots, possessions and ventures. One class knows the routes, so when the ledger
/// engine moves to xkeel (PL26100305) only this file changes.
///
/// This is T3 data. It goes only to the reader's own hub, is never put in a URL or a log line, and nothing is sent
/// to a third party: a report is opened on this device, and the export is the hub's own save to the reader's OneDrive.

class LedgerAccount {
  const LedgerAccount({required this.id, required this.name, this.type = '', this.balance = '0', this.institution = '', this.asOf = '', this.note = ''});
  final String id;
  final String name;
  final String type;
  final String balance;
  final String institution;
  final String asOf;
  final String note;

  bool get isDebt => type == 'debt';
  double get amount => double.tryParse(balance) ?? 0;
}

class LedgerGoal {
  const LedgerGoal({required this.title, this.target = 0, this.current = 0, this.due = ''});
  final String title;
  final double target;
  final double current;
  final String due;
  double get share => target <= 0 ? 0 : (current / target).clamp(0.0, 1.0);
}

class IncomeStream {
  const IncomeStream({required this.id, required this.name, this.source = '', this.recurs = '', this.expected = 0, this.received = 0, this.paused = false, this.overdue = false, this.dueDay = 0});
  final String id;
  final String name;
  final String source;
  final String recurs;
  final double expected;
  final double received;
  final bool paused;
  final bool overdue;
  final int dueDay;
}

class LedgerSummary {
  const LedgerSummary({this.currency = 'KES', this.accounts = const [], this.goals = const [], this.streams = const [], this.expectedMonthly = 0});
  final String currency;
  final List<LedgerAccount> accounts;
  final List<LedgerGoal> goals;
  final List<IncomeStream> streams;
  final double expectedMonthly;
}

class ReviewGroup {
  const ReviewGroup({required this.vendor, required this.category, this.confidence = '', this.count = 0, this.total = 0, this.sample = ''});
  final String vendor;
  final String category;
  final String confidence;
  final int count;
  final double total;
  final String sample;
}

class Possession {
  const Possession({required this.id, required this.item, this.category = '', this.value = '', this.acquired = '', this.location = '', this.condition = '', this.notes = ''});
  final String id;
  final String item;
  final String category;
  final String value;
  final String acquired;
  final String location;
  final String condition;
  final String notes;
}

class Venture {
  const Venture({required this.id, required this.name, this.kind = '', this.category = '', this.url = '', this.authSecret = '', this.renderUrl = '', this.github = '', this.folder = '', this.note = '', this.metrics = const {}, this.error = ''});
  final String id;
  final String name;
  final String kind;
  final String category;
  final String url;

  /// The NAME of a secret in the store, never its value.
  final String authSecret;
  final String renderUrl;
  final String github;
  final String folder;
  final String note;
  final Map<String, String> metrics;
  final String error;
}

/// The console's category list for the review queue.
const reviewCategories = [
  'needs/housing',
  'needs/food',
  'needs/utilities',
  'wants/growth',
  'wants/friends-family',
  'wants/liquid',
  'security/savings',
  'security/emergency',
  'security/debt',
  'fees',
  'business/acexoft-dynamics',
  'transfer/own-accounts',
];

const accountTypes = ['cash', 'mobile-money', 'bank', 'sacco', 'investment', 'receivable', 'debt'];
const ventureKinds = ['saas', 'app', 'service', 'candidate'];
const ventureCategories = ['-', 'product', 'platform'];

/// A report period: all time, or a from and to date.
class ReportPeriod {
  const ReportPeriod.all()
      : all = true,
        from = '',
        to = '';
  const ReportPeriod.range(this.from, this.to) : all = false;
  final bool all;
  final String from;
  final String to;

  Map<String, dynamic> toJson() => all ? {'all': true} : {'from': from, 'to': to};
  String get query => all ? 'all=1' : 'from=${Uri.encodeQueryComponent(from)}&to=${Uri.encodeQueryComponent(to)}';

  /// The presets the console offers, from today's date.
  static Map<String, ReportPeriod> presets(DateTime today) {
    String iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return {
      'This month': ReportPeriod.range(iso(DateTime(today.year, today.month, 1)), iso(today)),
      'Last month': ReportPeriod.range(iso(DateTime(today.year, today.month - 1, 1)), iso(DateTime(today.year, today.month, 0))),
      'Year to date': ReportPeriod.range('${today.year}-01-01', iso(today)),
      'All time': const ReportPeriod.all(),
    };
  }
}

abstract class LedgerApi {
  Future<LedgerSummary> summary();
  Future<void> setBalance(String id, String balance);
  Future<void> renameAccount(String id, String name);
  Future<void> addAccount({required String name, required String type, required String balance});
  Future<void> addGoal({required String title, required String target, String due = ''});
  Future<void> addIncome({required String name, required String amount, required String recurs, String day = '', String source = '', String match = ''});
  Future<void> setIncomeStatus(String id, String status);

  /// Freezes today's position into the trend; returns the net figure as text.
  Future<String> snapshot();
  Future<List<ReviewGroup>> review();

  /// Moves a group's transactions to [newCategory]; returns how many changed.
  Future<int> resolve({required String vendor, required String category, required String newCategory});
  /// [format] is html or csv. The hub answers 415 for pdf: open the html and print it to PDF.
  Future<({String filename, List<int> bytes})> report(ReportPeriod p, {String format = 'html'});

  /// The hub's own save to the reader's OneDrive; returns the file names.
  Future<List<Possession>> possessions();
  Future<void> upsertPossession(Map<String, String> fields, {String id = ''});
  Future<void> deletePossession(String id);
  Future<List<Venture>> ventures({bool refresh = false});
  Future<void> upsertVenture(Map<String, String> fields, {String id = ''});
  Future<void> deleteVenture(String id);

  /// Scans for new venture folders; returns how many candidates were added.
  Future<int> discoverVentures();
}

class HubLedgerApi implements LedgerApi {
  HubLedgerApi(this.api);
  final ApiClient api;

  static Map<String, dynamic> _m(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  static List<dynamic> _l(Object? v) => v is List ? v : const [];
  static String _s(Object? v) => v == null || v == '-' ? '' : '$v';
  static double _d(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  static Map<String, dynamic> _ok(Object? res) {
    final m = _m(res);
    if (m['success'] == false || (m['success'] == null && m['ok'] == false)) throw ApiException(0, _s(m['error']).isEmpty ? 'Refused' : _s(m['error']));
    return m;
  }

  @override
  Future<LedgerSummary> summary() async {
    final f = _m(await api.getJson('/api/finance/summary'));
    final inc = _m(f['incomes']);
    return LedgerSummary(
      currency: _s(f['currency']).isEmpty ? 'KES' : _s(f['currency']),
      accounts: [
        for (final a in _l(f['accounts']))
          LedgerAccount(
            id: _s(_m(a)['ID']),
            name: _s(_m(a)['NAME']),
            type: _s(_m(a)['TYPE']),
            balance: _s(_m(a)['BALANCE']).isEmpty ? '0' : _s(_m(a)['BALANCE']),
            institution: _s(_m(a)['INSTITUTION']),
            asOf: _s(_m(a)['ASOF']),
            note: _s(_m(a)['NOTE']),
          ),
      ],
      goals: [
        for (final g in _l(f['goals']))
          if (_s(_m(g)['STATUS']) != 'done') LedgerGoal(title: _s(_m(g)['TITLE']), target: _d(_m(g)['TARGET']), current: _d(_m(g)['CURRENT']), due: _s(_m(g)['DUE'])),
      ],
      streams: [
        for (final s in _l(inc['streams']))
          IncomeStream(
            id: _s(_m(s)['ID']),
            name: _s(_m(s)['NAME']),
            source: _s(_m(s)['SOURCE']),
            recurs: _s(_m(s)['RECURS']),
            expected: _d(_m(s)['expected']),
            received: _d(_m(s)['received']),
            paused: _s(_m(s)['STATUS']) == 'paused',
            overdue: _m(s)['overdue'] == true,
            dueDay: _d(_m(s)['dueDay']).toInt(),
          ),
      ],
      expectedMonthly: _d(inc['expectedMonthly']),
    );
  }

  @override
  Future<void> setBalance(String id, String balance) async => _ok(await api.postJson('/api/finance/account', {'id': id, 'balance': balance}));

  @override
  Future<void> renameAccount(String id, String name) async => _ok(await api.postJson('/api/finance/account', {'id': id, 'name': name}));

  @override
  Future<void> addAccount({required String name, required String type, required String balance}) async =>
      _ok(await api.postJson('/api/finance/account', {'name': name, 'type': type, 'balance': balance}));

  @override
  Future<void> addGoal({required String title, required String target, String due = ''}) async =>
      _ok(await api.postJson('/api/finance/goal', {'title': title, 'target': target, 'due': due}));

  @override
  Future<void> addIncome({required String name, required String amount, required String recurs, String day = '', String source = '', String match = ''}) async =>
      _ok(await api.postJson('/api/finance/income', {
        'name': name,
        'amount': amount,
        'recurs': recurs,
        'day': day.isEmpty ? '-' : day,
        'source': source,
        'match': match.isEmpty ? name.split(RegExp(r'\s+')).first.toLowerCase() : match,
      }));

  @override
  Future<void> setIncomeStatus(String id, String status) async => _ok(await api.postJson('/api/finance/income', {'id': id, 'status': status}));

  @override
  Future<String> snapshot() async {
    final d = _ok(await api.postJson('/api/finance/snapshot', {}));
    return _s(_m(d['snapshot'])['NET']);
  }

  @override
  Future<List<ReviewGroup>> review() async {
    final d = _m(await api.getJson('/api/finance/review'));
    return [
      for (final g in _l(d['groups']))
        ReviewGroup(
          vendor: _s(_m(g)['vendor']),
          category: _s(_m(g)['category']),
          confidence: _s(_m(g)['confidence']),
          count: _d(_m(g)['count']).toInt(),
          total: _d(_m(g)['total']),
          sample: _l(_m(g)['samples']).isEmpty ? '' : '${_l(_m(g)['samples']).first}',
        ),
    ];
  }

  @override
  Future<int> resolve({required String vendor, required String category, required String newCategory}) async {
    final d = _ok(await api.postJson('/api/finance/review/resolve', {'vendor': vendor, 'category': category, 'newCategory': newCategory}));
    return _d(d['changed']).toInt();
  }

  @override
  Future<({String filename, List<int> bytes})> report(ReportPeriod p, {String format = 'html'}) =>
      api.getBytes('/api/finance/report?${p.query}&format=$format');

  @override
  Future<List<Possession>> possessions() async {
    final d = _m(await api.getJson('/api/possessions'));
    return [
      for (final p in _l(d['possessions']))
        Possession(
          id: _s(_m(p)['ID']),
          item: _s(_m(p)['ITEM']),
          category: _s(_m(p)['CATEGORY']),
          value: _s(_m(p)['VALUE']),
          acquired: _s(_m(p)['ACQUIRED_DATE']),
          location: _s(_m(p)['LOCATION']),
          condition: _s(_m(p)['CONDITION']),
          notes: _s(_m(p)['NOTES']),
        ),
    ];
  }

  @override
  Future<void> upsertPossession(Map<String, String> fields, {String id = ''}) async =>
      _ok(await api.postJson('/api/possessions/upsert', {...fields, if (id.isNotEmpty) 'id': id}));

  @override
  Future<void> deletePossession(String id) async => _ok(await api.postJson('/api/possessions/delete', {'id': id}));

  @override
  Future<List<Venture>> ventures({bool refresh = false}) async {
    final d = _m(await api.getJson('/api/ventures${refresh ? '?refresh=1' : ''}'));
    return [
      for (final v in _l(d['ventures']))
        Venture(
          id: _s(_m(v)['ID']),
          name: _s(_m(v)['NAME']),
          kind: _s(_m(v)['KIND']),
          category: _s(_m(v)['CATEGORY']),
          url: _s(_m(v)['ANALYTICS_URL']),
          authSecret: _s(_m(v)['AUTH_SECRET']),
          renderUrl: _s(_m(v)['RENDER_URL']),
          github: _s(_m(v)['GITHUB']),
          folder: _s(_m(v)['FOLDER']),
          note: _s(_m(v)['NOTE']),
          metrics: {for (final e in _m(_m(v)['metrics']).entries) e.key: '${e.value}'},
          error: _s(_m(v)['error']),
        ),
    ];
  }

  @override
  Future<void> upsertVenture(Map<String, String> fields, {String id = ''}) async =>
      _ok(await api.postJson('/api/ventures/upsert', {...fields, if (id.isNotEmpty) 'id': id}));

  @override
  Future<void> deleteVenture(String id) async => _ok(await api.postJson('/api/ventures/delete', {'id': id}));

  @override
  Future<int> discoverVentures() async {
    final d = _m(await api.postJson('/api/ventures/discover', {}, cold: true));
    if (d['ok'] == false) throw ApiException(0, _s(d['error']).isEmpty ? 'Discovery sync failed' : _s(d['error']));
    return _l(d['created']).length;
  }
}
