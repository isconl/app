import 'package:flutter/foundation.dart';

import '../data/db.dart';
import 'fmt.dart' as fmt;

/// BI26100143: the end-of-day review. Pure selection and scheduling rules,
/// plus the little bit of state that survives a restart (the review time and
/// the day last closed).
class DayClosePrefs extends ChangeNotifier {
  DayClosePrefs._();
  static final DayClosePrefs instance = DayClosePrefs._();

  @visibleForTesting
  DayClosePrefs.forTesting();

  static const _key = 'dayclose.prefs.v1';

  bool enabled = true;
  int hour = 21;
  int minute = 0;
  bool skipWeekends = false;

  /// ISO date of the last day the user closed, or null.
  String? closedOn;
  bool _loaded = false;

  bool closedToday(DateTime now) => closedOn == fmt.isoDate(now);

  Future<void> ensureLoaded(AppDb db) async {
    if (_loaded) return;
    _loaded = true;
    try {
      final v = (await db.getSnapshot(_key))?.$1;
      if (v is Map) {
        enabled = v['enabled'] != false;
        hour = (v['hour'] is int ? v['hour'] as int : 21).clamp(0, 23);
        minute = (v['minute'] is int ? v['minute'] as int : 0).clamp(0, 59);
        skipWeekends = v['skipWeekends'] == true;
        closedOn = v['closedOn'] is String ? v['closedOn'] as String : null;
        notifyListeners();
      }
    } catch (_) {
      // Nothing stored: defaults.
    }
  }

  Future<void> update({bool? enabled, int? hour, int? minute, bool? skipWeekends, String? closedOn, AppDb? db}) async {
    if (enabled != null) this.enabled = enabled;
    if (hour != null) this.hour = hour.clamp(0, 23);
    if (minute != null) this.minute = minute.clamp(0, 59);
    if (skipWeekends != null) this.skipWeekends = skipWeekends;
    if (closedOn != null) this.closedOn = closedOn;
    notifyListeners();
    if (db != null) {
      try {
        await db.putSnapshot(_key, {
          'enabled': this.enabled,
          'hour': this.hour,
          'minute': this.minute,
          'skipWeekends': this.skipWeekends,
          'closedOn': this.closedOn,
        });
      } catch (_) {}
    }
  }
}

/// The next [days] review moments after [now]: one per day at hour:minute,
/// weekends left out when asked. A moment already past today is not included.
List<DateTime> reviewTimes(DateTime now, {required int hour, required int minute, bool skipWeekends = false, int days = 14}) {
  final out = <DateTime>[];
  for (var i = 0; i < days + 2 && out.length < days; i++) {
    final t = DateTime(now.year, now.month, now.day + i, hour, minute);
    if (!t.isAfter(now)) continue;
    if (skipWeekends && (t.weekday == DateTime.saturday || t.weekday == DateTime.sunday)) continue;
    out.add(t);
  }
  return out;
}

bool _isDone(Map<String, dynamic> t) => fmt.s(t['STATUS']).toLowerCase() == 'done';
bool _isDropped(Map<String, dynamic> t) => fmt.s(t['STATUS']).toLowerCase() == 'dropped';

/// Tasks finished today, by their DONE_AT date.
List<Map<String, dynamic>> doneToday(List<Map<String, dynamic>> tasks, DateTime now) {
  final today = fmt.isoDate(now);
  return [
    for (final t in tasks)
      if (_isDone(t) && fmt.s(t['DONE_AT']).startsWith(today)) t,
  ];
}

/// Every open task due today or overdue, or sitting in the Today column.
List<Map<String, dynamic>> stillOpen(List<Map<String, dynamic>> tasks, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  return [
    for (final t in tasks)
      if (!_isDone(t) && !_isDropped(t) && _dueOrToday(t, today)) t,
  ];
}

bool _dueOrToday(Map<String, dynamic> t, DateTime today) {
  if (fmt.s(t['STATUS']).toLowerCase() == 'today') return true;
  final due = fmt.parseDate(t['DUE_DATE']);
  if (due == null) return false;
  return !DateTime(due.year, due.month, due.day).isAfter(today);
}

/// The notification line, from the counts known when it was scheduled.
String dayCloseText(int done, int open) =>
    open == 0 ? 'Close the day: $done done, nothing open' : 'Close the day: $done done, $open open';

String tomorrowIso(DateTime now) => fmt.isoDate(DateTime(now.year, now.month, now.day + 1));
