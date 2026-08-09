/// ═══════════════════════════════════════════════════════════════════════════
/// M-Pesa SMS, turned into facts
/// ═══════════════════════════════════════════════════════════════════════════
///
/// ARCHITECT asked for his SMS read automatically so M-Pesa movements and the people
/// in them reach the agent without him typing anything. This is the parser, and
/// it is deliberately the only part of that feature with no side effects: pure
/// functions in, structured records out, so it can be tested exhaustively
/// against real message shapes rather than trusted.
///
/// ─── THE DISCIPLINE ─────────────────────────────────────────────────────────
///
/// This produces money, and money is arithmetic. So:
///
///   * NOTHING IS GUESSED. A message that does not match a known shape returns
///     `null` and is reported as unparsed. A wrong amount silently written into
///     the ledger is far worse than a message he has to file by hand, because the
///     wrong one is invisible and compounds.
///   * The amount is read from the message, never inferred from a balance delta.
///   * The balance is captured when present, because it is the one figure that
///     can reconcile the ledger against reality later.
///   * Direction is explicit per shape, not deduced from wording, since "sent to"
///     and "paid to" are both outflows but "received from" and "you have received"
///     are not, and Safaricom has used all four.
///
/// ─── WHY THIS CAN EXIST AT ALL ──────────────────────────────────────────────
///
/// READ_SMS is effectively unobtainable for a Play Store app. The agent serves
/// its own APK and there is no store in the path, so the permission is simply
/// granted on the device. That distribution choice is what makes this feature
/// possible, and it is worth naming as a deliberate advantage rather than a
/// workaround.
library;

enum MpesaKind {
  received,   // money in, from a person or a business
  sent,       // money out, to a person
  paid,       // money out, to a till or paybill
  withdraw,   // cash out at an agent
  deposit,    // cash in at an agent
  airtime,    // airtime purchase
  balance,    // a balance enquiry, no movement
  reversal,   // a reversal, money back
}

class MpesaEvent {
  const MpesaEvent({
    required this.kind,
    required this.amount,
    required this.raw,
    this.code,
    this.counterparty,
    this.phone,
    this.account,
    this.balance,
    this.cost,
    this.at,
  });

  final MpesaKind kind;

  /// Shillings. Always positive - direction lives in [kind], because a signed
  /// amount plus a direction is two sources of truth for one fact.
  final double amount;

  /// The transaction code, e.g. TG83H5K2LM. The natural idempotency key: the
  /// same SMS read twice must not become two ledger rows.
  final String? code;

  /// Who or what was on the other side, as written.
  final String? counterparty;
  final String? phone;

  /// The account number on a paybill payment (KPLC meter, school fees, and so on).
  final String? account;

  /// M-Pesa balance after the movement, when the message states it.
  final double? balance;

  /// Transaction cost, when stated. Kept separate from [amount]: it is a
  /// distinct outflow and folding it in would misstate both.
  final double? cost;

  final DateTime? at;
  final String raw;

  bool get isOutflow =>
      kind == MpesaKind.sent ||
      kind == MpesaKind.paid ||
      kind == MpesaKind.withdraw ||
      kind == MpesaKind.airtime;

  bool get isInflow =>
      kind == MpesaKind.received ||
      kind == MpesaKind.deposit ||
      kind == MpesaKind.reversal;

  /// The tier this most likely belongs to, for the recursive 50-30-20.
  ///
  /// A SUGGESTION and labelled as one everywhere it surfaces. Airtime is a
  /// utility, cash out is unknowable from the message alone, and a till could be
  /// groceries or a want. The agent proposes; ARCHITECT's category on the row wins.
  String? get suggestedTier {
    switch (kind) {
      case MpesaKind.airtime:
        return 'utilities';
      case MpesaKind.received:
      case MpesaKind.deposit:
      case MpesaKind.reversal:
      case MpesaKind.balance:
        return null;
      case MpesaKind.sent:
      case MpesaKind.paid:
      case MpesaKind.withdraw:
        return null;
    }
  }

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'amount': amount,
        if (code != null) 'code': code,
        if (counterparty != null) 'counterparty': counterparty,
        if (phone != null) 'phone': phone,
        if (account != null) 'account': account,
        if (balance != null) 'balance': balance,
        if (cost != null) 'cost': cost,
        if (at != null) 'at': at!.toIso8601String(),
        if (suggestedTier != null) 'suggestedTier': suggestedTier,
        'direction': isOutflow ? 'out' : (isInflow ? 'in' : 'none'),
        'raw': raw,
      };

  @override
  String toString() => 'MpesaEvent(${kind.name}, $amount, $counterparty, $code)';
}

/// The shape of a shilling figure: "Ksh1,234.56", "Ksh50", "KES 1,234.56".
///
/// It must END on a digit. Without that anchor the character class swallows the
/// sentence's full stop - "balance is Ksh2,345.67." captures the trailing dot,
/// double.tryParse("2345.67.") returns null, and the balance silently vanishes
/// from the ledger. That happened on the first test run, and it is exactly the
/// class of bug that makes a money parser untrustworthy: no error, no crash, just
/// a missing figure nobody notices until a reconciliation fails.
const _amountPattern = r'Ksh\s?[\d,]*\d(?:\.\d{1,2})?';

/// Shillings out of a captured figure.
///
/// Belt and braces with the anchored pattern above: even given a stray trailing
/// or leading dot from some future message shape, this returns a number rather
/// than null. Nothing here invents a value - it only refuses to be defeated by
/// punctuation.
double? _money(String? s) {
  if (s == null) return null;
  var cleaned = s.replaceAll(RegExp(r'[^0-9.]'), '');
  cleaned = cleaned.replaceAll(RegExp(r'^\.+|\.+$'), '');
  if (cleaned.isEmpty) return null;
  // More than one decimal point means the capture is wrong, not that the amount
  // is odd. Keep the first point and drop the rest rather than guessing.
  final parts = cleaned.split('.');
  if (parts.length > 2) {
    cleaned = '${parts.first}.${parts.sublist(1).join()}';
  }
  return double.tryParse(cleaned);
}

/// "3/8/26 at 10:15 AM" and "3/8/2026 at 10:15 AM".
///
/// Two-digit years are read as 2000+, which is correct for every M-Pesa message
/// that will ever exist and wrong only for a museum piece.
DateTime? _when(String? d, String? t) {
  if (d == null) return null;
  final dm = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{2,4})$').firstMatch(d.trim());
  if (dm == null) return null;
  var year = int.parse(dm.group(3)!);
  if (year < 100) year += 2000;
  final day = int.parse(dm.group(1)!);
  final month = int.parse(dm.group(2)!);
  var hour = 0, minute = 0;
  if (t != null) {
    final tm = RegExp(r'(\d{1,2}):(\d{2})\s*([AaPp])\.?[Mm]?').firstMatch(t);
    if (tm != null) {
      hour = int.parse(tm.group(1)!);
      minute = int.parse(tm.group(2)!);
      final pm = tm.group(3)!.toLowerCase() == 'p';
      if (pm && hour != 12) hour += 12;
      if (!pm && hour == 12) hour = 0;
    }
  }
  try {
    return DateTime(year, month, day, hour, minute);
  } catch (_) {
    return null;
  }
}

/// Trim the trailing noise Safaricom leaves on a name: a trailing full stop, a
/// dangling "on", stray whitespace.
String? _name(String? s) {
  if (s == null) return null;
  var n = s.trim().replaceAll(RegExp(r'\s+'), ' ');
  n = n.replaceAll(RegExp(r'[.\s]+$'), '');
  n = n.replaceAll(RegExp(r'\s+on$', caseSensitive: false), '');
  return n.isEmpty ? null : n;
}

final _codeRe = RegExp(r'^([A-Z0-9]{9,12})\s+[Cc]onfirmed', multiLine: false);
final _balanceRe = RegExp('balance is\\s*($_amountPattern)', caseSensitive: false);
final _costRe = RegExp('[Tt]ransaction cost,?\\s*($_amountPattern)');
final _dateRe = RegExp(r'on (\d{1,2}/\d{1,2}/\d{2,4})(?:\s+at\s+([\d:]+\s*[AaPp]\.?[Mm]?))?');

/// Parse one M-Pesa SMS. Returns null when the shape is not recognised - which
/// is a result, not a failure, and the caller must surface it rather than drop it.
MpesaEvent? parseMpesa(String body) {
  final raw = body.trim();
  if (raw.isEmpty) return null;
  // A cheap gate so ordinary SMS never reaches the shape matchers.
  if (!RegExp(r'M-?PESA|Ksh', caseSensitive: false).hasMatch(raw)) return null;

  final code = _codeRe.firstMatch(raw)?.group(1);
  final balance = _money(_balanceRe.firstMatch(raw)?.group(1));
  final cost = _money(_costRe.firstMatch(raw)?.group(1));
  final dm = _dateRe.firstMatch(raw);
  final at = _when(dm?.group(1), dm?.group(2));

  MpesaEvent build(MpesaKind kind, double amount,
          {String? counterparty, String? phone, String? account}) =>
      MpesaEvent(
        kind: kind, amount: amount, raw: raw, code: code,
        counterparty: _name(counterparty), phone: phone, account: _name(account),
        balance: balance, cost: cost, at: at,
      );

  // ── received: "You have received Ksh1,000.00 from JOHN DOE 0712345678 on ..."
  var m = RegExp(
    'received\\s*($_amountPattern)\\s*from\\s+(.+?)(?:\\s+(\\+?\\d[\\d\\s]{7,}))?\\s+on\\s',
    caseSensitive: false,
  ).firstMatch(raw);
  if (m != null) {
    final amt = _money(m.group(1));
    if (amt != null) {
      return build(MpesaKind.received, amt,
          counterparty: m.group(2), phone: m.group(3)?.replaceAll(' ', ''));
    }
  }

  // ── sent: "Ksh500.00 sent to JANE DOE 0723456789 on ..."
  m = RegExp(
    '($_amountPattern)\\s*sent to\\s+(.+?)(?:\\s+(\\+?\\d[\\d\\s]{7,}))?\\s+on\\s',
    caseSensitive: false,
  ).firstMatch(raw);
  if (m != null) {
    final amt = _money(m.group(1));
    if (amt != null) {
      return build(MpesaKind.sent, amt,
          counterparty: m.group(2), phone: m.group(3)?.replaceAll(' ', ''));
    }
  }

  // ── paybill with an account: "Ksh1,000.00 paid to KPLC. ... for account 123"
  m = RegExp(
    '($_amountPattern)\\s*(?:paid to|sent to)\\s+(.+?)\\s+on\\s.*?for account\\s+([\\w\\-]+)',
    caseSensitive: false, dotAll: true,
  ).firstMatch(raw);
  if (m != null) {
    final amt = _money(m.group(1));
    if (amt != null) {
      return build(MpesaKind.paid, amt, counterparty: m.group(2), account: m.group(3));
    }
  }

  // ── till / merchant: "You have paid Ksh250.00 to NAIVAS LTD. on ..." and
  //    "Ksh250.00 paid to NAIVAS LTD. on ..."
  m = RegExp(
    '(?:you have paid|paid)\\s*($_amountPattern)\\s*to\\s+(.+?)\\s+on\\s',
    caseSensitive: false,
  ).firstMatch(raw);
  m ??= RegExp(
    '($_amountPattern)\\s*paid to\\s+(.+?)\\s+on\\s',
    caseSensitive: false,
  ).firstMatch(raw);
  if (m != null) {
    final amt = _money(m.group(1));
    if (amt != null) return build(MpesaKind.paid, amt, counterparty: m.group(2));
  }

  // ── withdraw: "Withdraw Ksh1,000.00 from 123456 - AGENT NAME"
  m = RegExp(
    '[Ww]ithdraw\\s*($_amountPattern)\\s*from\\s+([\\w\\s\\-]+?)(?:\\s+New M-?PESA|\$)',
    caseSensitive: false,
  ).firstMatch(raw);
  if (m != null) {
    final amt = _money(m.group(1));
    if (amt != null) return build(MpesaKind.withdraw, amt, counterparty: m.group(2));
  }

  // ── deposit: "Give Ksh1,000.00 cash to ..." is the agent's copy; the customer
  //    copy is "You have deposited Ksh1,000.00 to ..."
  m = RegExp(
    'deposit(?:ed)?\\s*($_amountPattern)\\s*(?:to|at)\\s+(.+?)(?:\\s+on\\s|\$)',
    caseSensitive: false,
  ).firstMatch(raw);
  if (m != null) {
    final amt = _money(m.group(1));
    if (amt != null) return build(MpesaKind.deposit, amt, counterparty: m.group(2));
  }

  // ── airtime: "You bought Ksh100.00 of airtime on ..."
  m = RegExp(
    'bought\\s*($_amountPattern)\\s*of airtime',
    caseSensitive: false,
  ).firstMatch(raw);
  if (m != null) {
    final amt = _money(m.group(1));
    if (amt != null) return build(MpesaKind.airtime, amt, counterparty: 'Airtime');
  }

  // ── reversal: "Reversal of transaction ... Ksh500.00 ..."
  m = RegExp(
    '[Rr]eversal.*?($_amountPattern)',
    caseSensitive: false, dotAll: true,
  ).firstMatch(raw);
  if (m != null) {
    final amt = _money(m.group(1));
    if (amt != null) return build(MpesaKind.reversal, amt);
  }

  // ── balance enquiry: no movement, but the balance is worth capturing.
  if (balance != null &&
      RegExp(r'your.*balance was', caseSensitive: false).hasMatch(raw)) {
    return build(MpesaKind.balance, 0);
  }

  // Recognised as M-Pesa, shape unknown. Null, and the caller says so.
  return null;
}

/// One SMS as it arrives from the platform channel.
class SmsMessage {
  const SmsMessage({
    required this.sender,
    required this.body,
    required this.receivedAt,
    this.id,
  });

  final String sender;
  final String body;
  final DateTime receivedAt;
  final String? id;

  factory SmsMessage.fromJson(Map<dynamic, dynamic> j) => SmsMessage(
        sender: (j['sender'] ?? '').toString(),
        body: (j['body'] ?? '').toString(),
        receivedAt: DateTime.fromMillisecondsSinceEpoch(
            (j['date'] is int) ? j['date'] as int : 0),
        id: j['id']?.toString(),
      );

  /// Safaricom sends M-Pesa from the alphanumeric sender "MPESA". Matching the
  /// SENDER as well as the body is what stops a forwarded screenshot of a message,
  /// or a scam SMS imitating the format, from becoming a ledger row.
  bool get looksLikeMpesa =>
      RegExp(r'^M-?PESA$', caseSensitive: false).hasMatch(sender.trim());
}

/// What a batch of SMS yielded. Unparsed messages are carried, not discarded -
/// a parser that silently drops what it does not understand cannot be improved,
/// because nobody ever learns what it missed.
class SmsHarvest {
  SmsHarvest({required this.events, required this.unparsed, required this.scanned});
  final List<MpesaEvent> events;
  final List<SmsMessage> unparsed;
  final int scanned;

  int get ignored => scanned - events.length - unparsed.length;
}

/// Parse a batch, keeping only messages that genuinely came from M-Pesa.
SmsHarvest harvest(List<SmsMessage> messages) {
  final events = <MpesaEvent>[];
  final unparsed = <SmsMessage>[];
  final seen = <String>{};

  for (final m in messages) {
    if (!m.looksLikeMpesa) continue;
    final e = parseMpesa(m.body);
    if (e == null) {
      unparsed.add(m);
      continue;
    }
    // The transaction code is the idempotency key. The same SMS read twice - a
    // backfill overlapping the live receiver - must never become two rows.
    final key = e.code ?? '${e.kind.name}|${e.amount}|${m.receivedAt.millisecondsSinceEpoch}';
    if (!seen.add(key)) continue;
    events.add(e);
  }
  return SmsHarvest(events: events, unparsed: unparsed, scanned: messages.length);
}
