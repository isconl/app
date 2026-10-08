import 'package:flutter/foundation.dart';

import '../data/db.dart';

/// BI26100139: when a snoozed inbox thread comes back.
class SnoozeChoice {
  const SnoozeChoice(this.label, this.until);
  final String label;
  final DateTime until;
}

/// "Later today": three hours on, or 17:00 if that falls sooner and is still ahead.
/// "Tomorrow morning": 09:00 tomorrow. "Next week": the coming Monday 09:00
/// (a Monday today means next Monday, never today).
List<SnoozeChoice> snoozeChoices(DateTime now) {
  var later = now.add(const Duration(hours: 3));
  final five = DateTime(now.year, now.month, now.day, 17);
  if (five.isAfter(now) && five.isBefore(later)) later = five;
  final tomorrow = DateTime(now.year, now.month, now.day + 1, 9);
  final daysToMonday = (DateTime.monday - now.weekday + 7) % 7;
  final monday = DateTime(now.year, now.month, now.day + (daysToMonday == 0 ? 7 : daysToMonday), 9);
  return [
    SnoozeChoice('Later today', later),
    SnoozeChoice('Tomorrow morning', tomorrow),
    SnoozeChoice('Next week', monday),
  ];
}

/// Snoozed threads, kept on this device until the shared SNOOZE_UNTIL field
/// exists in the vault (filed as its own row). A thread key maps to the time
/// it reappears; once that time passes it is simply visible again.
class SnoozeStore extends ChangeNotifier {
  SnoozeStore._();
  static final SnoozeStore instance = SnoozeStore._();

  @visibleForTesting
  SnoozeStore.forTesting();

  static const _key = 'inbox.snooze.v1';
  final _until = <String, DateTime>{};
  bool _loaded = false;

  Future<void> ensureLoaded(AppDb db) async {
    if (_loaded) return;
    _loaded = true;
    try {
      final saved = (await db.getSnapshot(_key))?.$1;
      if (saved is Map) {
        for (final e in saved.entries) {
          final t = DateTime.tryParse('${e.value}');
          if (t != null) _until['${e.key}'] = t;
        }
        notifyListeners();
      }
    } catch (_) {
      // Nothing stored: no thread is snoozed.
    }
  }

  bool isSnoozed(String key, DateTime now) {
    final t = _until[key];
    return t != null && t.isAfter(now);
  }

  Future<void> snooze(String key, DateTime until, AppDb? db) async {
    _until[key] = until;
    notifyListeners();
    await _save(db);
  }

  Future<void> unsnooze(String key, AppDb? db) async {
    if (_until.remove(key) == null) return;
    notifyListeners();
    await _save(db);
  }

  Future<void> _save(AppDb? db) async {
    if (db == null) return;
    final now = DateTime.now();
    _until.removeWhere((_, t) => !t.isAfter(now));
    try {
      await db.putSnapshot(_key, {for (final e in _until.entries) e.key: e.value.toIso8601String()});
    } catch (_) {}
  }
}
