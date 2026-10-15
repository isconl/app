/// BI26100707: Survival and Readiness. A kit checklist with expiry reminders and a
/// trip card with a missed check-in nudge. Everything here works with no signal
/// and keeps its data on the phone (§41): nothing is sent anywhere until the
/// reader presses Share.
library;

/// A reminder fires this long before a perishable expires.
const expiryWarning = Duration(days: 14);

/// The hour of the day an expiry reminder fires.
const reminderHour = 9;

class KitItem {
  KitItem({required this.id, required this.name, this.packed = false, this.expiry});

  final String id;
  String name;
  bool packed;

  /// Only perishables carry one (medicines, water tablets, batteries, ORS).
  DateTime? expiry;

  /// When the reminder for this item fires: 14 days before expiry, at 09:00.
  DateTime? get reminderAt {
    final e = expiry;
    if (e == null) return null;
    final d = DateTime(e.year, e.month, e.day).subtract(expiryWarning);
    return DateTime(d.year, d.month, d.day, reminderHour);
  }

  /// Days left to [now] (negative once past). Null with no expiry.
  int? daysLeft(DateTime now) {
    final e = expiry;
    if (e == null) return null;
    final a = DateTime(now.year, now.month, now.day);
    final b = DateTime(e.year, e.month, e.day);
    return b.difference(a).inDays;
  }

  /// Within the warning window or already expired.
  bool needsAttention(DateTime now) {
    final d = daysLeft(now);
    return d != null && d <= expiryWarning.inDays;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'packed': packed,
        if (expiry != null) 'expiry': _date(expiry!),
      };

  static KitItem? fromJson(Object? v) {
    if (v is! Map) return null;
    final id = '${v['id'] ?? ''}';
    final name = '${v['name'] ?? ''}';
    if (id.isEmpty || name.isEmpty) return null;
    return KitItem(
      id: id,
      name: name,
      packed: v['packed'] == true,
      expiry: DateTime.tryParse('${v['expiry'] ?? ''}'),
    );
  }
}

class Kit {
  Kit({required this.id, required this.name, List<KitItem>? items}) : items = items ?? [];

  final String id;
  final String name;
  final List<KitItem> items;

  int get packedCount => items.where((i) => i.packed).length;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'items': [for (final i in items) i.toJson()]};

  static Kit? fromJson(Object? v) {
    if (v is! Map) return null;
    final id = '${v['id'] ?? ''}';
    if (id.isEmpty) return null;
    final raw = v['items'];
    return Kit(
      id: id,
      name: '${v['name'] ?? id}',
      items: [
        for (final i in (raw is List ? raw : const []))
          if (KitItem.fromJson(i) case final it?) it,
      ],
    );
  }
}

/// The three kits named in the decision. Their items come from the course
/// modules, so a new phone starts with these empty and the reader adds what the
/// course says to pack; no list is hard-coded here.
List<Kit> defaultKits() => [
      Kit(id: 'trek', name: 'Trek pack'),
      Kit(id: 'carry', name: 'Everyday carry and car kit'),
      Kit(id: 'house', name: 'House kit'),
    ];

class Trip {
  Trip({
    required this.id,
    required this.where,
    this.who = '',
    required this.start,
    required this.returnBy,
    required this.alarmAt,
    this.callWho = '',
    this.notes = '',
    this.sharePhone = '',
    this.backAt,
    this.sharedAt,
  });

  final String id;
  String where;

  /// Who is going.
  String who;
  DateTime start;
  DateTime returnBy;

  /// When to raise the alarm if nobody has pressed "I'm back".
  DateTime alarmAt;

  /// Who to call (KWS, mountain rescue, a contact), with the number the reader
  /// typed. Never filled from this app.
  String callWho;
  String notes;

  /// The WhatsApp number the trip card is shared to.
  String sharePhone;
  DateTime? backAt;
  DateTime? sharedAt;

  bool get isBack => backAt != null;

  /// The alarm time has passed and nobody has said they are back.
  bool isOverdue(DateTime now) => !isBack && now.isAfter(alarmAt);

  /// The message that goes to the chosen contact. Plain text, readable on a
  /// phone with one bar of signal.
  String message() {
    final b = StringBuffer()
      ..writeln('Trip card: $where')
      ..writeln('Who: ${who.isEmpty ? 'me' : who}')
      ..writeln('Leaving: ${formatDateTime(start)}')
      ..writeln('Back by: ${formatDateTime(returnBy)}')
      ..writeln('If you have not heard from me by ${formatDateTime(alarmAt)}, please raise the alarm.');
    if (callWho.trim().isNotEmpty) b.writeln('Who to call: ${callWho.trim()}');
    if (notes.trim().isNotEmpty) b.writeln('Notes: ${notes.trim()}');
    return b.toString().trim();
  }

  /// The message to resend when the alarm time has passed without a check-in.
  String overdueMessage(DateTime now) =>
      'I am overdue. I was due back by ${formatDateTime(returnBy)} from $where and have not checked in. '
      'Please try to reach me, and raise the alarm if you cannot.'
      '${callWho.trim().isEmpty ? '' : '\nWho to call: ${callWho.trim()}'}';

  Map<String, dynamic> toJson() => {
        'id': id,
        'where': where,
        'who': who,
        'start': start.toUtc().toIso8601String(),
        'returnBy': returnBy.toUtc().toIso8601String(),
        'alarmAt': alarmAt.toUtc().toIso8601String(),
        'callWho': callWho,
        'notes': notes,
        'sharePhone': sharePhone,
        if (backAt != null) 'backAt': backAt!.toUtc().toIso8601String(),
        if (sharedAt != null) 'sharedAt': sharedAt!.toUtc().toIso8601String(),
      };

  static Trip? fromJson(Object? v) {
    if (v is! Map) return null;
    final start = DateTime.tryParse('${v['start'] ?? ''}')?.toLocal();
    final returnBy = DateTime.tryParse('${v['returnBy'] ?? ''}')?.toLocal();
    final alarm = DateTime.tryParse('${v['alarmAt'] ?? ''}')?.toLocal();
    final id = '${v['id'] ?? ''}';
    if (id.isEmpty || start == null || returnBy == null || alarm == null) return null;
    return Trip(
      id: id,
      where: '${v['where'] ?? ''}',
      who: '${v['who'] ?? ''}',
      start: start,
      returnBy: returnBy,
      alarmAt: alarm,
      callWho: '${v['callWho'] ?? ''}',
      notes: '${v['notes'] ?? ''}',
      sharePhone: '${v['sharePhone'] ?? ''}',
      backAt: DateTime.tryParse('${v['backAt'] ?? ''}')?.toLocal(),
      sharedAt: DateTime.tryParse('${v['sharedAt'] ?? ''}')?.toLocal(),
    );
  }
}

/// A starting point for a trip: only the place and a sensible default gap. The
/// rescue contacts come from the course and are typed in by the reader, with the
/// date they last checked them; a wrong number here could cost a rescue.
class TripTemplate {
  const TripTemplate(this.name, this.where, {this.hint = ''});
  final String name;
  final String where;
  final String hint;
}

const tripTemplates = [
  TripTemplate('Mt Kenya', 'Mt Kenya', hint: 'Add the park and mountain rescue contacts from the course, with the date you checked them.'),
  TripTemplate('Coast', 'Kenya coast', hint: 'Add the local rescue and a contact on shore, with the date you checked them.'),
];

/// `https://wa.me/<digits>?text=<message>`, or null when there is no usable
/// number. WhatsApp wants the number with its country code and no symbols.
Uri? whatsappLink(String phone, String message) {
  final digits = phone.replaceAll(RegExp(r'[^\d]'), '');
  if (digits.length < 7) return null;
  return Uri.parse('https://wa.me/$digits?text=${Uri.encodeQueryComponent(message)}');
}

String _date(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String formatDateTime(DateTime d) {
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final h = d.hour.toString().padLeft(2, '0');
  final mi = d.minute.toString().padLeft(2, '0');
  return '${d.day} ${m[d.month - 1]} $h:$mi';
}

String formatDate(DateTime d) {
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${m[d.month - 1]} ${d.year}';
}
