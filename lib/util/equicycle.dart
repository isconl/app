import 'package:flutter/foundation.dart';

import '../api/client.dart';
import '../data/db.dart';

/// BI26100205 (Equicycle 2): the phone holds no calendar arithmetic of its
/// own. The signal engine owns the calendar; `GET /api/calendar/eq/year`
/// gives a year's start, length and Stillweek, and the app keeps those few
/// tables in memory and in the local snapshot store so a cold or offline
/// start still has them. A position is then a day count from a year's start.
/// Mirrors hub web's eq2Position (hub/web/static/app.js).
class EqYear {
  const EqYear({
    required this.year,
    required this.start,
    required this.length,
    this.stillweek,
  });
  final int year;

  /// First day of the Equicycle year, as a calendar date (no time part).
  final DateTime start;

  /// 364, or 371 when the year carries a Stillweek.
  final int length;
  final Map<String, dynamic>? stillweek;

  static EqYear? fromJson(dynamic j, {int? fallbackYear}) {
    if (j is! Map) return null;
    final start = parseDate(j['start']);
    final length = j['length'];
    if (start == null || length is! num || length <= 0) return null;
    final y = j['year'];
    return EqYear(
      year: y is num ? y.toInt() : (fallbackYear ?? start.year),
      start: start,
      length: length.toInt(),
      stillweek: j['stillweek'] is Map
          ? Map<String, dynamic>.from(j['stillweek'] as Map)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'year': year,
        'start': isoDay(start),
        'length': length,
        'stillweek': stillweek,
      };
}

DateTime? parseDate(dynamic v) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch('$v');
  if (m == null) return null;
  return DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
}

String isoDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Whole days between two calendar dates, immune to daylight-saving shifts.
int _daysBetween(DateTime a, DateTime b) =>
    (DateTime.utc(b.year, b.month, b.day)
                .difference(DateTime.utc(a.year, a.month, a.day))
                .inMilliseconds /
            86400000)
        .round();

class EqPosition {
  const EqPosition({
    required this.year,
    required this.length,
    required this.start,
    required this.dayOfYear,
    required this.stillweek,
    required this.cycle,
    required this.day,
    required this.stillweekDay,
    required this.sprint,
    required this.sprintDay,
  });
  final int year;
  final int length;
  final DateTime start;
  final int dayOfYear;
  final bool stillweek;
  final int cycle;
  final int day;
  final int? stillweekDay;
  final int sprint;
  final int sprintDay;

  /// The cycle key the server stores themes under: `eq2:26-C04`.
  String get cycleKey => eq2CycleKey(year, cycle);

  /// First day of this position's cycle (cycle 13 starts on day 337 of the year).
  DateTime get cycleStart =>
      DateTime(start.year, start.month, start.day + (cycle - 1) * 28);
}

String eq2CycleKey(int eqYear, int cycleNum) =>
    'eq2:${(eqYear % 100).toString().padLeft(2, '0')}-C${cycleNum.toString().padLeft(2, '0')}';

/// A date's Equicycle 2 position from the year tables, or null when no table
/// covers it. Pure given [years].
EqPosition? eq2Position(DateTime date, Iterable<EqYear> years) {
  for (final info in years) {
    final days = _daysBetween(info.start, date);
    if (days < 0 || days >= info.length) continue;
    final still = days >= 364;
    return EqPosition(
      year: info.year,
      length: info.length,
      start: info.start,
      dayOfYear: days + 1,
      stillweek: still,
      cycle: still ? 13 : days ~/ 28 + 1,
      day: still ? 28 : days % 28 + 1,
      stillweekDay: still ? days - 363 : null,
      sprint: still ? 26 : days ~/ 14 + 1,
      sprintDay: still ? 14 : days % 14 + 1,
    );
  }
  return null;
}

/// The cached year tables. One instance for the app; views listen to it and
/// repaint when a fetch lands.
class EquicycleYears extends ChangeNotifier {
  EquicycleYears._();
  static final EquicycleYears instance = EquicycleYears._();

  @visibleForTesting
  EquicycleYears.forTesting([Iterable<EqYear> years = const []]) {
    for (final y in years) {
      _years[y.year] = y;
    }
  }

  static const _snapshotKey = 'eq2.years.v1';
  final _years = <int, EqYear>{};
  bool _loading = false;
  bool _loaded = false;
  DateTime? _lastTry;

  Iterable<EqYear> get years => _years.values;
  bool get isEmpty => _years.isEmpty;

  EqPosition? positionFor(DateTime date) => eq2Position(date, _years.values);

  /// Restore the stored tables, then refresh Y-1, Y and Y+1 from the server.
  /// Safe to call from every build: it runs once per app start.
  Future<void> ensureLoaded(ApiClient api, AppDb db) async {
    if (_loaded || _loading) return;
    // Offline: try again at most once a minute, not on every repaint.
    if (_lastTry != null && DateTime.now().difference(_lastTry!) < const Duration(minutes: 1)) return;
    _lastTry = DateTime.now();
    _loading = true;
    try {
      try {
        final saved = await db.getSnapshot(_snapshotKey);
        final v = saved?.$1;
        if (v is List) {
          for (final j in v) {
            final y = EqYear.fromJson(j);
            if (y != null) _years[y.year] = y;
          }
          if (_years.isNotEmpty) notifyListeners();
        }
      } catch (_) {
        // No stored table: the fetch below fills it.
      }
      final y = DateTime.now().year;
      var fetched = false;
      await Future.wait([y - 1, y, y + 1].map((yr) async {
        try {
          final d = await api.getJson('/api/calendar/eq/year?year=$yr');
          final t = EqYear.fromJson(d, fallbackYear: yr);
          if (t != null) {
            _years[yr] = t;
            fetched = true;
          }
        } catch (_) {
          // Offline: whatever is cached stays.
        }
      }));
      if (fetched) {
        notifyListeners();
        try {
          await db.putSnapshot(
              _snapshotKey, [for (final t in _years.values) t.toJson()]);
        } catch (_) {}
      }
      _loaded = fetched;
    } finally {
      _loading = false;
    }
  }
}
