/// BI26102401: everything the Accounts space reads and writes, behind one typed interface.
///
/// The register lives in vault's personal tier and is served by hub under /api/accounts (the hub and vault halves are
/// their own commits). Until they are live the space runs on [FakeAccountsApi]; [HttpAccountsApi] speaks this contract:
///
///   GET  /api/accounts/addresses                 -> {items:[address]}
///   POST /api/accounts/addresses {address}       -> {item}
///   GET  /api/accounts/signups                   -> {items:[signup]}
///   POST /api/accounts/signups   {signup}        -> {item}
///   GET  /api/accounts/seats                     -> {items:[seat]}   (usage from slate GET /api/usage)
///   POST /api/accounts/import    {rows}          -> {added}
///
/// Never stored or shown: passwords, recovery codes, 2FA seeds, API keys, cookies. Only the Bitwarden item NAME is kept.
library;

import '../api/client.dart';
import '../util/fmt.dart' as fmt;

class AccountsException implements Exception {
  const AccountsException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// mine | not mine; purpose; status. Strings, so the server can add values without an app release.
class AccountAddress {
  const AccountAddress({
    required this.address,
    this.provider = '',
    this.purpose = 'personal',
    this.status = 'active',
    this.mine = true,
    this.recoveryAddress = '',
    this.recoveryPhoneLast2 = '',
    this.twoFa = '',
    this.bitwardenItem = '',
    this.created,
    this.closed,
    this.note = '',
    this.lastSeen,
    this.lastSeenSource = '',
  });
  final String address, provider, purpose, status, recoveryAddress, recoveryPhoneLast2, twoFa, bitwardenItem, note, lastSeenSource;
  final bool mine;
  final DateTime? created, closed, lastSeen;

  bool get closedOut => status == 'closed';

  static DateTime? _d(Object? v) => v == null || '$v'.isEmpty ? null : DateTime.tryParse('$v');

  static AccountAddress from(Map<String, dynamic> m) => AccountAddress(
        address: fmt.s(m['address']),
        provider: fmt.s(m['provider']),
        purpose: fmt.s(m['purpose']).isEmpty ? 'personal' : fmt.s(m['purpose']),
        status: fmt.s(m['status']).isEmpty ? 'active' : fmt.s(m['status']),
        mine: m['mine'] == null ? true : fmt.b(m['mine']),
        recoveryAddress: fmt.s(m['recovery_address']),
        recoveryPhoneLast2: fmt.s(m['recovery_phone_last2']),
        twoFa: fmt.s(m['two_fa']),
        bitwardenItem: fmt.s(m['bitwarden_item']),
        created: _d(m['created']),
        closed: _d(m['closed']),
        note: fmt.s(m['note']),
        lastSeen: _d(m['last_seen']),
        lastSeenSource: fmt.s(m['last_seen_source']),
      );

  Map<String, dynamic> toJson() => {
        'address': address,
        'provider': provider,
        'purpose': purpose,
        'status': status,
        'mine': mine,
        'recovery_address': recoveryAddress,
        'recovery_phone_last2': recoveryPhoneLast2,
        'two_fa': twoFa,
        'bitwarden_item': bitwardenItem,
        'created': created?.toIso8601String(),
        'closed': closed?.toIso8601String(),
        'note': note,
      };
}

class SignUp {
  const SignUp({
    required this.service,
    required this.address,
    this.url = '',
    this.plan = '',
    this.monthlyCost = 0,
    this.currency = 'USD',
    this.renewal,
    this.twoFaOn = false,
    this.bitwardenItem = '',
    this.status = 'active',
    this.lastSeen,
    this.lastSeenSource = '',
  });
  final String service, address, url, plan, currency, bitwardenItem, status, lastSeenSource;
  final double monthlyCost;
  final DateTime? renewal, lastSeen;
  final bool twoFaOn;

  bool get costsMoney => monthlyCost > 0;
  bool renewsWithin(int days, DateTime now) => renewal != null && !renewal!.isBefore(DateTime(now.year, now.month, now.day)) && renewal!.difference(now).inDays < days;

  static SignUp from(Map<String, dynamic> m) => SignUp(
        service: fmt.s(m['service']),
        address: fmt.s(m['address']),
        url: fmt.s(m['url']),
        plan: fmt.s(m['plan']),
        monthlyCost: fmt.d(m['monthly_cost']),
        currency: fmt.s(m['currency']).isEmpty ? 'USD' : fmt.s(m['currency']),
        renewal: AccountAddress._d(m['renewal']),
        twoFaOn: fmt.b(m['two_fa_on']),
        bitwardenItem: fmt.s(m['bitwarden_item']),
        status: fmt.s(m['status']).isEmpty ? 'active' : fmt.s(m['status']),
        lastSeen: AccountAddress._d(m['last_seen']),
        lastSeenSource: fmt.s(m['last_seen_source']),
      );

  Map<String, dynamic> toJson() => {
        'service': service,
        'address': address,
        'url': url,
        'plan': plan,
        'monthly_cost': monthlyCost,
        'currency': currency,
        'renewal': renewal?.toIso8601String(),
        'two_fa_on': twoFaOn,
        'bitwarden_item': bitwardenItem,
        'status': status,
      };
}

/// A Claude or agy (Gemini) account with its live usage from slate.
class AiSeat {
  const AiSeat({
    required this.account,
    required this.provider,
    this.address = '',
    this.paidBy = '',
    this.plan = '',
    this.fiveHourPct,
    this.fiveHourResets,
    this.sevenDayPct,
    this.sevenDayResets,
    this.machine = '',
    this.sessionsToday = 0,
  });
  final String account, provider, address, paidBy, plan, machine;
  final double? fiveHourPct, sevenDayPct;
  final DateTime? fiveHourResets, sevenDayResets;
  final int sessionsToday;

  static AiSeat from(Map<String, dynamic> m) => AiSeat(
        account: fmt.s(m['account']),
        provider: fmt.s(m['provider']),
        address: fmt.s(m['address']),
        paidBy: fmt.s(m['paid_by']),
        plan: fmt.s(m['plan']),
        fiveHourPct: m['five_hour_pct'] == null ? null : fmt.d(m['five_hour_pct']),
        fiveHourResets: AccountAddress._d(m['five_hour_resets']),
        sevenDayPct: m['seven_day_pct'] == null ? null : fmt.d(m['seven_day_pct']),
        sevenDayResets: AccountAddress._d(m['seven_day_resets']),
        machine: fmt.s(m['machine']),
        sessionsToday: fmt.i(m['sessions_today']),
      );
}

/// Warns on an address that is the only recovery route for [threshold] or more others.
Map<String, List<String>> recoveryChain(List<AccountAddress> all) {
  final out = <String, List<String>>{};
  for (final a in all) {
    if (a.recoveryAddress.isEmpty) continue;
    (out[a.recoveryAddress.toLowerCase()] ??= []).add(a.address);
  }
  return out;
}

const recoveryWarnThreshold = 3;

/// Addresses that recover [recoveryWarnThreshold] or more others.
List<String> recoverySinglePoints(List<AccountAddress> all) =>
    [for (final e in recoveryChain(all).entries) if (e.value.length >= recoveryWarnThreshold) e.key];

/// Secret-shape scan for free text (notes). A hit refuses the save; the text is never echoed back.
class SecretGuard {
  static final _shapes = <RegExp>[
    RegExp(r'gh[pousr]_[A-Za-z0-9]{20,}'),
    RegExp(r'github_pat_[A-Za-z0-9_]{20,}'),
    RegExp(r'sk-[A-Za-z0-9_\-]{20,}'),
    RegExp(r'AKIA[0-9A-Z]{16}'),
    RegExp(r'xox[abprs]-[A-Za-z0-9\-]{10,}'),
    RegExp(r'AIza[0-9A-Za-z_\-]{30,}'),
    RegExp(r'-----BEGIN [A-Z ]*PRIVATE KEY-----'),
    RegExp(r'eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}'),
    RegExp(r'\b[A-Z2-7]{32,}\b'), // a base32 2FA seed
    RegExp(r'(?:password|passwd|secret|token|api[_ -]?key)\s*[:=]\s*\S{6,}', caseSensitive: false),
  ];

  static bool looksSecret(String text) => _shapes.any((r) => r.hasMatch(text));
}

/// A CSV or pasted-list import: address, service, plan, cost, renewal, note. Refuses secret-looking columns outright.
class ImportPreview {
  const ImportPreview({this.rows = const [], this.refusal});
  final List<SignUp> rows;

  /// Why the whole file was refused, never including any cell value.
  final String? refusal;
  bool get ok => refusal == null;
}

class AccountsImport {
  static final _secretHeader = RegExp(r'pass(word|wd)?|secret|token|totp|otp|recovery|seed|api.?key|private|\bkey\b|cookie|pin\b', caseSensitive: false);
  static const _wanted = {'address', 'service', 'plan', 'cost', 'renewal', 'note'};

  static List<String> _cells(String line) {
    final out = <String>[];
    final b = StringBuffer();
    var q = false;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') {
        if (q && i + 1 < line.length && line[i + 1] == '"') {
          b.write('"');
          i++;
        } else {
          q = !q;
        }
      } else if ((c == ',' || c == '\t') && !q) {
        out.add(b.toString().trim());
        b.clear();
      } else {
        b.write(c);
      }
    }
    out.add(b.toString().trim());
    return out;
  }

  static ImportPreview parse(String text) {
    final lines = text.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) return const ImportPreview(refusal: 'The file is empty.');
    final head = _cells(lines.first).map((h) => h.toLowerCase()).toList();
    final joined = head.join(',');
    // Bitwarden, Chrome and Firefox password exports: refused whatever else they hold.
    if (head.contains('login_password') || head.contains('login_totp') || (head.contains('url') && head.contains('password')) || joined.contains('httprealm')) {
      return const ImportPreview(refusal: 'This looks like a password-manager export. It is refused: the register never takes passwords.');
    }
    if (head.any(_secretHeader.hasMatch)) {
      return const ImportPreview(refusal: 'A column looks like a password, token, code or key. The import is refused. Remove it and try again.');
    }
    if (!head.contains('address')) return const ImportPreview(refusal: 'The first row must name the columns, starting with "address".');
    final idx = {for (var i = 0; i < head.length; i++) if (_wanted.contains(head[i])) head[i]: i};
    final rows = <SignUp>[];
    for (final line in lines.skip(1)) {
      final c = _cells(line);
      String at(String k) => idx[k] != null && idx[k]! < c.length ? c[idx[k]!] : '';
      if (SecretGuard.looksSecret(line)) return const ImportPreview(refusal: 'A cell looks like a secret. The import is refused.');
      if (at('address').isEmpty) continue;
      rows.add(SignUp(
        service: at('service'),
        address: at('address'),
        plan: at('plan'),
        monthlyCost: double.tryParse(at('cost')) ?? 0,
        renewal: DateTime.tryParse(at('renewal')),
        status: 'unknown',
      ));
    }
    return ImportPreview(rows: rows);
  }
}

abstract class AccountsApi {
  Future<List<AccountAddress>> addresses();
  Future<void> addAddress(AccountAddress a);
  Future<List<SignUp>> signUps();
  Future<void> addSignUp(SignUp s);
  Future<List<AiSeat>> seats();
  Future<int> importSignUps(List<SignUp> rows);
}

class HttpAccountsApi implements AccountsApi {
  HttpAccountsApi(this.api);
  final ApiClient api;

  Future<Map<String, dynamic>> _go(Future<dynamic> Function() f) async {
    try {
      return fmt.m(await f());
    } on ApiException catch (e) {
      throw AccountsException(e.message);
    } on OfflineException {
      throw const AccountsException('Offline.');
    }
  }

  @override
  Future<List<AccountAddress>> addresses() async =>
      [for (final m in fmt.lm((await _go(() => api.getJson('/api/accounts/addresses')))['items'])) AccountAddress.from(m)];

  @override
  Future<void> addAddress(AccountAddress a) async {
    if (SecretGuard.looksSecret(a.note)) throw const AccountsException('The note looks like a secret and was not saved.');
    await _go(() => api.postJson('/api/accounts/addresses', {'address': a.toJson()}));
  }

  @override
  Future<List<SignUp>> signUps() async => [for (final m in fmt.lm((await _go(() => api.getJson('/api/accounts/signups')))['items'])) SignUp.from(m)];

  @override
  Future<void> addSignUp(SignUp s) async {
    await _go(() => api.postJson('/api/accounts/signups', {'signup': s.toJson()}));
  }

  @override
  Future<List<AiSeat>> seats() async => [for (final m in fmt.lm((await _go(() => api.getJson('/api/accounts/seats')))['items'])) AiSeat.from(m)];

  @override
  Future<int> importSignUps(List<SignUp> rows) async =>
      fmt.i((await _go(() => api.postJson('/api/accounts/import', {'rows': [for (final r in rows) r.toJson()]})))['added']);
}

/// In-memory stand-in, seeded with the addresses already on record.
class FakeAccountsApi implements AccountsApi {
  FakeAccountsApi({List<AccountAddress>? addresses, List<SignUp>? signUps, List<AiSeat>? seats})
      : _addresses = addresses ?? seedAddresses(),
        _signUps = signUps ?? [],
        _seats = seats ?? [];
  final List<AccountAddress> _addresses;
  final List<SignUp> _signUps;
  final List<AiSeat> _seats;

  static List<AccountAddress> seedAddresses() => const [
        AccountAddress(address: 'sconl.vv@gmail.com', provider: 'Google', purpose: 'work'),
        AccountAddress(address: 'sconl@acexoft.com', provider: 'Microsoft', purpose: 'business'),
        AccountAddress(address: 'admin@acexoft.com', provider: 'Microsoft', purpose: 'business'),
        AccountAddress(address: 'sconl@proton.me', provider: 'Proton', purpose: 'personal'),
        AccountAddress(address: 'evansnyambegavv@gmail.com', provider: 'Google', purpose: 'work', mine: false, note: "The team lead's. The Drive and Atlassian connectors sign in as it."),
      ];

  @override
  Future<List<AccountAddress>> addresses() async => List.of(_addresses);
  @override
  Future<void> addAddress(AccountAddress a) async {
    if (SecretGuard.looksSecret(a.note)) throw const AccountsException('The note looks like a secret and was not saved.');
    _addresses.add(a);
  }

  @override
  Future<List<SignUp>> signUps() async => List.of(_signUps);
  @override
  Future<void> addSignUp(SignUp s) async => _signUps.add(s);
  @override
  Future<List<AiSeat>> seats() async => List.of(_seats);
  @override
  Future<int> importSignUps(List<SignUp> rows) async {
    _signUps.addAll(rows);
    return rows.length;
  }
}

/// "seen in slate 2h ago" versus "you said 3 Sep": the source is always shown.
String lastSeenLabel(DateTime? at, String source, DateTime now) {
  if (at == null) return 'never seen';
  final d = now.difference(at);
  final ago = d.inDays >= 1 ? '${d.inDays}d ago' : d.inHours >= 1 ? '${d.inHours}h ago' : '${d.inMinutes.clamp(0, 59)}m ago';
  return switch (source) {
    'typed' => 'you said ${at.day} ${fmt.monthsFull[at.month - 1].substring(0, 3)}',
    '' => ago,
    _ => 'seen in $source $ago',
  };
}

/// An address or sign-up unseen for 12 months gets a "close or keep?" prompt once.
bool staleForReview(DateTime? lastSeen, DateTime now) => lastSeen != null && now.difference(lastSeen).inDays > 365;

/// Monthly total per currency over sign-ups that are not cancelled.
Map<String, double> monthlyTotals(List<SignUp> all) {
  final out = <String, double>{};
  for (final s in all) {
    if (s.status == 'cancelled' || s.monthlyCost <= 0) continue;
    out[s.currency] = (out[s.currency] ?? 0) + s.monthlyCost;
  }
  return out;
}
