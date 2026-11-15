/// BI26111595: key dates worked out on the phone, so the calendar, the key-date cards and the hub's reminders are
/// right every day and offline, from the dates list alone (pulse `dates.tsv`: ID, TITLE, DATE, KIND, WHO, RECURS,
/// COLOR). Nothing here reads the server's day counts, which go stale on a phone that has been offline.
library;

import 'dart:ui' show Color;

import '../theme.dart';
import 'fmt.dart' as fmt;

const _monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// One key date with its next occurrence worked out against [today].
class KeyDate {
  KeyDate._(this.raw, this.id, this.title, this.kind, this.origin, this.yearKnown, this.recurs, this.next, this.daysAway,
      this.daysSince, this.what);

  final Map<String, dynamic> raw;
  final String id;
  final String title;

  /// Lowercase kind: birthday, anniversary, deadline, first job, ...
  final String kind;
  final DateTime origin;

  /// False when the year is a placeholder (Sconl, 15 Nov 2026: a birthday's year is never assumed to be 2000).
  final bool yearKnown;
  final bool recurs;

  /// The next day this date matters, today or later.
  final DateTime next;
  final int daysAway;

  /// Days since a past one-off date, else null.
  final int? daysSince;

  /// What happens on [next]: "turns 34", "8 years", "1,000 days", or the title's own day.
  final String what;

  bool get isBirthday => kind == 'birthday';

  /// "15 Nov", or "15 Nov 1992" when the year is real and asked for.
  String dayMonth({bool withYear = false}) =>
      '${origin.day} ${_monthNames[origin.month - 1]}${withYear && yearKnown ? ' ${origin.year}' : ''}';
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// The same month and day in [year]; 29 Feb falls on 28 Feb in a common year.
DateTime _inYear(DateTime origin, int year) {
  if (origin.month == 2 && origin.day == 29) {
    final leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
    return DateTime(year, 2, leap ? 29 : 28);
  }
  return DateTime(year, origin.month, origin.day);
}

/// A year written as a stand-in for "unknown": 2000 on a birthday (how undated birthdays were stored), or anything
/// before 1901.
bool placeholderYear(int year, String kind) => year <= 1900 || (kind == 'birthday' && year == 2000);

const _dayMilestones = [100, 365, 500, 1000];

KeyDate? keyDateFrom(Map<String, dynamic> d, DateTime today) {
  final iso = fmt.s(d['DATE']);
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(iso);
  if (m == null) return null;
  final kind = fmt.s(d['KIND']).toLowerCase().trim();
  final origin = DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  final t = _day(today);
  final yearKnown = !placeholderYear(origin.year, kind);
  // Read raw: the store writes '-' for a one-off, and fmt.s reads '-' as empty.
  final r = '${d['RECURS'] ?? ''}'.trim().toLowerCase();
  final recurs = r == 'yearly' || r == 'yes' || r == 'true';
  final title = fmt.s(d['TITLE']);
  DateTime next;
  int? since;
  String what;
  if (recurs || kind == 'birthday' || kind == 'anniversary') {
    next = _inYear(origin, t.year);
    if (next.isBefore(t)) next = _inYear(origin, t.year + 1);
    final years = next.year - origin.year;
    what = !yearKnown || years <= 0
        ? (kind == 'birthday' ? 'birthday' : title)
        : kind == 'birthday'
            ? 'turns $years'
            : '$years year${years == 1 ? '' : 's'}';
  } else if (!origin.isBefore(t)) {
    next = origin;
    what = kind == 'deadline' ? 'due' : 'on the day';
  } else {
    // A past one-off: the next round count of days since it.
    since = t.difference(origin).inDays;
    final target = _dayMilestones.firstWhere((x) => x > since!, orElse: () => ((since! ~/ 1000) + 1) * 1000);
    next = origin.add(Duration(days: target));
    what = '${_thousands(target)} days';
  }
  final away = next.difference(t).inDays;
  return KeyDate._(d, fmt.s(d['ID']), title, kind, origin, yearKnown, recurs, next, away, since, what);
}

String _thousands(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

/// How much a kind matters when picking what to show: a higher weight pulls a date forward. People first.
double kindWeight(String kind) => switch (kind) {
      'birthday' => 1.6,
      'deadline' => 1.5,
      'anniversary' => 1.3,
      _ => 1.0,
    };

/// The relevance score; lower shows first. Today beats everything; then days away, shortened by the kind's weight,
/// so a birthday in 20 days (12.5) comes before a work first in 15 (15). A one-off that has passed counts only toward
/// its next round number of days, at half weight, so it shows when nothing nearer matters.
double relevance(KeyDate k) {
  if (k.daysAway == 0) return -1;
  final base = k.daysAway / kindWeight(k.kind);
  return k.daysSince != null ? base * 2 : base;
}

/// BI26111595: the three key dates to show, most relevant first: one wide card and two side by side. Ties go to the
/// heavier kind, then the title, so the pick is stable from one day to the next.
List<KeyDate> pickKeyDates(List<Map<String, dynamic>> dates, DateTime today, {int count = 3}) {
  final all = [for (final d in dates) ?keyDateFrom(d, today)];
  all.sort((a, b) {
    final r = relevance(a).compareTo(relevance(b));
    if (r != 0) return r;
    final w = kindWeight(b.kind).compareTo(kindWeight(a.kind));
    return w != 0 ? w : a.title.compareTo(b.title);
  });
  return all.take(count).toList();
}

/// Every key date that falls between [from] and [to] (inclusive), as calendar events, so the grids and the day list
/// show them. Each carries `source: keydate` and its kind, for the dot colour.
Map<String, List<Map<String, dynamic>>> keyDateEvents(List<Map<String, dynamic>> dates, DateTime from, DateTime to) {
  final out = <String, List<Map<String, dynamic>>>{};
  final f = _day(from), t = _day(to);
  for (final d in dates) {
    final k = keyDateFrom(d, f);
    if (k == null) continue;
    final days = <DateTime>[];
    if (k.recurs || k.kind == 'birthday' || k.kind == 'anniversary') {
      for (var y = f.year; y <= t.year; y++) {
        final x = _inYear(k.origin, y);
        if (!x.isBefore(f) && !x.isAfter(t)) days.add(x);
      }
    } else if (!k.origin.isBefore(f) && !k.origin.isAfter(t)) {
      days.add(k.origin);
    }
    for (final x in days) {
      final kx = keyDateFrom(d, x)!;
      out.putIfAbsent(fmt.isoDate(x), () => []).add({
        'title': kx.isBirthday ? '${k.title}${kx.what.startsWith('turns') ? ' (${kx.what})' : ''}' : k.title,
        'date': fmt.isoDate(x),
        'source': 'keydate',
        'kind': k.kind,
        'id': k.id,
      });
    }
  }
  return out;
}

/// Birthdays in the next [within] days, soonest first, for the hub's reminders.
List<KeyDate> upcomingBirthdays(List<Map<String, dynamic>> dates, DateTime today, {int within = 14}) {
  final b = [
    for (final d in dates)
      if (keyDateFrom(d, today) case final k? when k.isBirthday && k.daysAway <= within) k
  ];
  b.sort((a, c) => a.daysAway.compareTo(c.daysAway));
  return b;
}

/// "today", "tomorrow", "in 12 days".
String daysAwayWords(int n) => n == 0 ? 'today' : n == 1 ? 'tomorrow' : 'in $n days';

/// The colour each kind wears, on its card, its calendar dot and the day list (ported from the web's kindColor map).
const keyDateKindColors = <String, Color>{
  'birthday': C.violet,
  'anniversary': C.green,
  'graduation': C.green,
  'first graduation': C.green,
  'first job': C.blue,
  'first': C.blue,
  'deadline': C.amber,
};
Color keyDateColor(String kind) => keyDateKindColors[kind.toLowerCase()] ?? C.text3;
