import '../../util/fmt.dart' as fmt;

/// BI26092641: the pure side of the Inbox conversations. Everything here is a function of the feed rows, so it
/// is tested without a widget. The rules mirror the web (`inboxKind`, `inboxThreadRows`, `inboxDayLabel` in
/// hub/web/static/app.js) and circle's lib/inbox-rules.js, so the two clients show the same conversation.

/// When a message arrived: vault rows say `RECEIVED_AT`, older app rows `RECEIVED`.
String receivedAt(Map<String, dynamic> m) {
  final a = fmt.s(m['RECEIVED_AT']);
  return a.isNotEmpty ? a : fmt.s(m['RECEIVED']);
}

/// The text a message shows: its body, or its title when the body is empty.
String messageText(Map<String, dynamic> m) {
  final body = fmt.s(m['BODY']);
  if (body.isNotEmpty && body != '-') return body;
  final title = fmt.s(m['TITLE']);
  return title.isNotEmpty ? title : fmt.s(m['SUBJECT']);
}

enum MessageKind { message, linkOnly, system }

final _systemBody = <RegExp>[
  RegExp(r'^messages and calls are end-to-end encrypted', caseSensitive: false),
  RegExp(r'^you created (this )?group', caseSensitive: false),
  RegExp(r'^[\w +().-]+ (added|removed|left|joined|changed the (group|subject|icon))\b.*$', caseSensitive: false),
  RegExp(r'^<media omitted>$', caseSensitive: false),
  RegExp(r'^this message was deleted$', caseSensitive: false),
  RegExp(r'^you deleted this message$', caseSensitive: false),
  RegExp(r'^missed (voice|video) call', caseSensitive: false),
  RegExp(r'^your security code with .* changed', caseSensitive: false),
  RegExp(r'^disappearing messages (were|was) (turned )?(on|off)', caseSensitive: false),
  RegExp(r'^\[system\]', caseSensitive: false),
];
final _urlOnly = RegExp(r'^\s*(https?://\S+\s*)+$', caseSensitive: false);

/// Platform notices are not messages, and a bare link is folded into the message before it.
MessageKind messageKind(Map<String, dynamic> m) {
  final body = fmt.s(m['BODY']).trim();
  if (fmt.s(m['CHANNEL']).toLowerCase() == 'system' || fmt.s(m['TAG']).toLowerCase() == 'system') {
    return MessageKind.system;
  }
  if (body.isEmpty || body == '-') return MessageKind.system;
  if (_systemBody.any((re) => re.hasMatch(body))) return MessageKind.system;
  if (_urlOnly.hasMatch(body)) return MessageKind.linkOnly;
  return MessageKind.message;
}

List<String> linksIn(String body) {
  final out = <String>[];
  for (final x in RegExp(r'https?://[^\s<>"\x27)\]]+', caseSensitive: false).allMatches(body)) {
    final u = x.group(0)!.replaceAll(RegExp(r'[.,;:!?]+$'), '');
    if (!out.contains(u)) out.add(u);
  }
  return out;
}

class ThreadRow {
  ThreadRow(this.message) : extraLinks = [];
  final Map<String, dynamic> message;

  /// Links from bare-link rows that followed this message within ten minutes, same direction.
  final List<String> extraLinks;

  bool get outbound => fmt.s(message['DIRECTION']) == 'out';
  DateTime? get time => fmt.parseDate(receivedAt(message));
}

/// A thread's visible rows, oldest first: notices dropped, link-only rows folded into the message before them.
List<ThreadRow> threadRows(List<Map<String, dynamic>> messages) {
  final sorted = [...messages]..sort((a, b) => receivedAt(a).compareTo(receivedAt(b)));
  final shown = <ThreadRow>[];
  for (final m in sorted) {
    switch (messageKind(m)) {
      case MessageKind.system:
        continue;
      case MessageKind.linkOnly:
        if (shown.isNotEmpty) {
          final prev = shown.last;
          final a = prev.time, b = fmt.parseDate(receivedAt(m));
          final sameWay = prev.outbound == (fmt.s(m['DIRECTION']) == 'out');
          if (sameWay && a != null && b != null && b.difference(a).abs() <= const Duration(minutes: 10)) {
            prev.extraLinks.addAll(linksIn(fmt.s(m['BODY'])));
            continue;
          }
        }
        shown.add(ThreadRow(m));
      case MessageKind.message:
        shown.add(ThreadRow(m));
    }
  }
  return shown;
}

/// Human source label for a channel.
String sourceLabel(String channel) {
  final k = channel.toLowerCase();
  const known = {
    'whatsapp': 'WhatsApp',
    'telegram': 'Telegram',
    'signal': 'Signal',
    'email': 'Email',
    'gmail': 'Email',
    'outlook': 'Email',
  };
  if (known.containsKey(k)) return known[k]!;
  if (k.isEmpty || k == '-') return 'Manual';
  return k[0].toUpperCase() + k.substring(1);
}

bool isEmailChannel(String channel) => const {'email', 'gmail', 'outlook'}.contains(channel.toLowerCase());

/// "Today", "Yesterday", then "Mon 22 Sep" (and the year when it is not this year).
String dayLabel(DateTime day, DateTime now) {
  final d = DateTime(day.year, day.month, day.day);
  final n = DateTime(now.year, now.month, now.day);
  final diff = n.difference(d).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  final wd = fmt.weekdaysFull[d.weekday - 1].substring(0, 3);
  final mo = fmt.monthsFull[d.month - 1].substring(0, 3);
  return d.year == n.year ? '$wd ${d.day} $mo' : '$wd ${d.day} $mo ${d.year}';
}

/// The time shown on a message: `14:32`, or empty when the row has no time.
String clockOf(Map<String, dynamic> m) {
  final t = fmt.parseDate(receivedAt(m));
  return t == null ? '' : fmt.hhmm(t);
}

/// The time shown on a conversation row: the clock today, else the short date.
String listTime(Map<String, dynamic> m, DateTime now) {
  final t = fmt.parseDate(receivedAt(m));
  if (t == null) return receivedAt(m);
  final same = t.year == now.year && t.month == now.month && t.day == now.day;
  return same ? fmt.hhmm(t) : fmt.shortDate(receivedAt(m));
}

class InboxThread {
  InboxThread(this.key, this.messages, this.personId);

  /// The person id for a linked thread, or `sender:<handle>` / `channel:<name>` for an unlinked one.
  final String key;
  final List<Map<String, dynamic>> messages; // newest first
  final String? personId;

  bool get linked => personId != null;
  Map<String, dynamic> get latest => messages.first;
  int get unread => messages.where((m) => fmt.s(m['STATUS']) == 'new').length;
}

/// Splits the feed into people (linked, newest first) and unknown senders (unlinked, newest first). Notices
/// alone do not make a thread: a conversation of only system rows is left out.
({List<InboxThread> people, List<InboxThread> unknown}) groupThreads(List<Map<String, dynamic>> feed) {
  final byKey = <String, List<Map<String, dynamic>>>{};
  final personOf = <String, String?>{};
  for (final item in feed) {
    final pid = fmt.s(item['PERSON_ID']);
    String key;
    String? person;
    if (pid.isNotEmpty && pid != '-') {
      key = pid;
      person = pid;
    } else {
      final sender = fmt.s(item['SENDER']);
      key = sender.isNotEmpty && sender != '-' ? 'sender:$sender' : 'channel:${fmt.s(item['CHANNEL'])}';
    }
    byKey.putIfAbsent(key, () => []).add(item);
    personOf[key] = person;
  }
  final people = <InboxThread>[], unknown = <InboxThread>[];
  for (final e in byKey.entries) {
    if (!e.value.any((m) => messageKind(m) != MessageKind.system)) continue;
    final msgs = [...e.value]..sort((a, b) => receivedAt(b).compareTo(receivedAt(a)));
    final t = InboxThread(e.key, msgs, personOf[e.key]);
    (t.linked ? people : unknown).add(t);
  }
  int byRecency(InboxThread a, InboxThread b) => receivedAt(b.latest).compareTo(receivedAt(a.latest));
  people.sort(byRecency);
  unknown.sort(byRecency);
  return (people: people, unknown: unknown);
}
