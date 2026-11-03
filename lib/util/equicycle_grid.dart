import 'package:flutter/foundation.dart';

import '../api/client.dart';
import '../data/db.dart';

/// BI26100135 (Equicycle 2, 4/5): the year grid the calendar service serves, `GET /api/calendar/eq/grid?year=26`: 13 cycles of
/// 28 days (D01 always a Sunday), each day with its Gregorian date, sprint, sun event and new or full moon, the Stillweek in
/// a long year, the seasons and the rain periods of a location as dated ranges. The phone does no calendar arithmetic: it
/// draws what it is given, and keeps each year's grid in the local snapshot store so a cold or offline start still has it.
/// Mirrors hub web's eqGridLoad / eqPageStep (hub/web/static/app.js).

class EqCell {
  const EqCell({required this.day, required this.date, required this.weekday, required this.sprint, required this.markers, required this.moon});
  final int day;

  /// `YYYY-MM-DD`.
  final String date;
  final String weekday;

  /// `A`, `B`, or empty in the Stillweek.
  final String sprint;

  /// Sun events on this day: `(kind, name)` with kind `solstice` or `equinox`.
  final List<({String kind, String name})> markers;

  /// `new`, `full`, or null.
  final String? moon;

  static EqCell? fromJson(dynamic j) {
    if (j is! Map) return null;
    final d = j['date'];
    if (d is! String || d.length < 10) return null;
    return EqCell(
      day: (j['day'] as num?)?.toInt() ?? 0,
      date: d.substring(0, 10),
      weekday: '${j['weekday'] ?? ''}',
      sprint: '${j['sprint'] ?? ''}',
      markers: [
        for (final m in (j['markers'] is List ? j['markers'] as List : const []))
          if (m is Map) (kind: '${m['kind']}', name: '${m['name']}'),
      ],
      moon: j['moon'] is String ? j['moon'] as String : null,
    );
  }
}

class EqCycle {
  const EqCycle({required this.cycle, required this.season, required this.theme, required this.start, required this.end, required this.days});
  final int cycle;

  /// `1`..`4` or `closing`.
  final String season;
  final String theme;
  final String start;
  final String end;
  final List<EqCell> days;
}

class EqGrid {
  const EqGrid({
    required this.year,
    required this.yearLabel,
    required this.start,
    required this.end,
    required this.cycles,
    required this.seasonNames,
    required this.stillweek,
    required this.rainsLocation,
    required this.rains,
  });
  final int year;
  final String yearLabel;
  final String start;
  final String end;
  final List<EqCycle> cycles;

  /// Season key (`1`..`4`, `closing`) to its display name.
  final Map<String, String> seasonNames;

  /// The seven Stillweek days, or null in a 364-day year.
  final List<EqCell>? stillweek;
  final String rainsLocation;
  final List<({String name, String start, String end})> rains;

  /// The 13 cycles, plus the Stillweek (page 14) when the year has one.
  int get pages => stillweek == null ? 13 : 14;

  bool inRains(String date) => rains.any((p) => date.compareTo(p.start) >= 0 && date.compareTo(p.end) <= 0);

  static EqGrid? fromJson(dynamic j) {
    if (j is! Map || j['cycles'] is! List) return null;
    final cycles = <EqCycle>[];
    for (final c in j['cycles'] as List) {
      if (c is! Map) continue;
      final days = [for (final d in (c['days'] is List ? c['days'] as List : const [])) ?EqCell.fromJson(d)];
      cycles.add(EqCycle(
        cycle: (c['cycle'] as num?)?.toInt() ?? cycles.length + 1,
        season: '${c['season']}',
        theme: '${c['theme'] ?? ''}',
        start: '${c['start'] ?? ''}',
        end: '${c['end'] ?? ''}',
        days: days,
      ));
    }
    if (cycles.length != 13) return null;
    final sw = j['stillweek'];
    final rains = j['rains'] is Map ? j['rains'] as Map : const {};
    return EqGrid(
      year: (j['year'] as num?)?.toInt() ?? 0,
      yearLabel: '${j['yearLabel'] ?? ''}',
      start: '${j['start'] ?? ''}',
      end: '${j['end'] ?? ''}',
      cycles: cycles,
      seasonNames: {
        for (final s in (j['seasons'] is List ? j['seasons'] as List : const []))
          if (s is Map) '${s['season']}': '${s['name'] ?? ''}',
      },
      stillweek: sw is Map && sw['days'] is List ? [for (final d in sw['days'] as List) ?EqCell.fromJson(d)] : null,
      rainsLocation: '${rains['location'] ?? ''}',
      rains: [
        for (final p in (rains['periods'] is List ? rains['periods'] as List : const []))
          if (p is Map) (name: '${p['name']}', start: '${p['start']}', end: '${p['end']}'),
      ],
    );
  }
}

/// One step (+1 or -1) from a page, crossing into the neighbouring year. Pure: [pagesOf] says how many pages a year has (0 when
/// it is not loaded, taken as 13).
({int year, int page}) eqPageStep(int year, int page, int delta, int Function(int year) pagesOf) {
  final n = page + delta;
  if (n < 1) {
    final py = year - 1;
    final pp = pagesOf(py);
    return (year: py, page: pp == 0 ? 13 : pp);
  }
  final here = pagesOf(year);
  if (n > (here == 0 ? 13 : here)) return (year: year + 1, page: 1);
  return (year: year, page: n);
}

/// The grids by year, in memory and in the local snapshot store.
class EquicycleGrids extends ChangeNotifier {
  EquicycleGrids._();
  static final EquicycleGrids instance = EquicycleGrids._();

  /// A fresh store for tests.
  @visibleForTesting
  EquicycleGrids.forTest();

  final _grids = <int, EqGrid>{};
  final _loading = <int>{};
  final _failed = <int>{};
  final _refreshed = <int>{};
  final _tried = <int, DateTime>{};

  EqGrid? gridFor(int year) => _grids[year];
  bool failed(int year) => _failed.contains(year);

  static String _key(int year) => 'eq2.grid.$year.v1';

  /// Restore this year's saved grid, then refresh it from the server. A failed refresh keeps whatever was saved.
  Future<void> ensure(ApiClient api, AppDb db, int year) async {
    if (_loading.contains(year)) return;
    if (_refreshed.contains(year)) return; // once per start
    // Offline, or the service down: try again at most once a minute, not on every repaint.
    final tried = _tried[year];
    if (tried != null && DateTime.now().difference(tried) < const Duration(minutes: 1)) return;
    _tried[year] = DateTime.now();
    _loading.add(year);
    try {
      if (!_grids.containsKey(year)) {
        try {
          final saved = await db.getSnapshot(_key(year));
          final g = EqGrid.fromJson(saved?.$1);
          if (g != null) {
            _grids[year] = g;
            notifyListeners();
          }
        } catch (_) {
          // No saved copy: the fetch below fills it.
        }
      }
      try {
        final raw = await api.getJson('/api/calendar/eq/grid?year=$year');
        final g = EqGrid.fromJson(raw);
        if (g != null) {
          _grids[year] = g;
          _refreshed.add(year);
          _failed.remove(year);
          notifyListeners();
          try {
            await db.putSnapshot(_key(year), raw);
          } catch (_) {}
        } else if (!_grids.containsKey(year)) {
          _failed.add(year);
          notifyListeners();
        }
      } catch (_) {
        if (!_grids.containsKey(year)) {
          _failed.add(year);
          notifyListeners();
        }
      }
    } finally {
      _loading.remove(year);
    }
  }
}
