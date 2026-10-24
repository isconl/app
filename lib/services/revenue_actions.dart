/// BI26102202: what "Today's revenue actions" shows, kept apart from the widget so the rules are testable.
///
/// Rows: open rows whose subset is growth, practice, enquiries or first-tenant, or whose title starts with "marketing",
/// kept in the order slate served them (its value order), at most [revenueRowLimit].
/// Days since the last client conversation: the newest touch of anyone tagged client or lead in circle.
library;

import 'package:slate_ui/slate_ui.dart';

const revenueRowLimit = 5;
const revenueSubsets = {'growth', 'practice', 'enquiries', 'first-tenant'};
const revenueTags = {'client', 'lead'};

/// Open means not done and not shelved; a gated row is still shown (it is the day's money work, even if it waits on Sconl).
bool isRevenueRow(RowSummary r) {
  final s = r.status.toLowerCase();
  if (s == 'done' || s == 'shelved') return false;
  final sub = (r.subset ?? '').toLowerCase();
  return revenueSubsets.contains(sub) || r.title.toLowerCase().startsWith('marketing');
}

List<RowSummary> pickRevenueRows(List<RowSummary> all, {int limit = revenueRowLimit}) =>
    [for (final r in all) if (isRevenueRow(r)) r].take(limit).toList();

enum ClientGap { none, ok, amber, red }

/// None before any conversation is logged; amber after 7 days, red after 14.
ClientGap clientGap(int? days) {
  if (days == null) return ClientGap.none;
  if (days >= 14) return ClientGap.red;
  if (days >= 7) return ClientGap.amber;
  return ClientGap.ok;
}

DateTime? _date(Object? v) {
  if (v == null) return null;
  final s = '$v';
  if (s.isEmpty || s == '-') return null;
  final n = num.tryParse(s);
  if (n != null) return DateTime.fromMillisecondsSinceEpoch((n < 100000000000 ? n * 1000 : n).toInt());
  return DateTime.tryParse(s);
}

/// The people in circle's list tagged client or lead.
bool isClientPerson(Map<String, dynamic> p) {
  final raw = '${p['TAGS'] ?? ''},${p['GROUP'] ?? ''}'.toLowerCase();
  return raw.split(',').map((t) => t.trim()).any(revenueTags.contains);
}

/// Whole days between the newest client or lead touch and [now]; null when there is none.
int? daysSinceClientConversation(List<Map<String, dynamic>> people, DateTime now) {
  DateTime? newest;
  for (final p in people) {
    if (!isClientPerson(p)) continue;
    final t = _date(p['lastTouch']);
    if (t != null && (newest == null || t.isAfter(newest))) newest = t;
  }
  if (newest == null) return null;
  final d = DateTime(now.year, now.month, now.day).difference(DateTime(newest.year, newest.month, newest.day)).inDays;
  return d < 0 ? 0 : d;
}

String gapLine(int? days) => switch (days) {
      null => 'No client conversation recorded yet',
      0 => 'Last client conversation: today',
      1 => 'Last client conversation: yesterday',
      _ => 'Last client conversation: $days days ago',
    };
