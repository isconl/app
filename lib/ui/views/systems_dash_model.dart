import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../util/fmt.dart' as fmt;

/// BI26100131: the numbers behind the Systems dashboard, from rows the app
/// already holds: the ops status, the backlog rollup, snapshot fetch times
/// and the outbox. Status and ages only, nothing secret (CLAUDE.md s17).
class EngineHealth {
  EngineHealth(this.name, this.up);
  final String name;
  final bool up;
}

class SystemsDash {
  SystemsDash({required this.engines, required this.byType, required this.syncAge});
  final List<EngineHealth> engines;

  /// Live rows per backlog category, in plan, build, work, light, content, hands order.
  final Map<String, int> byType;

  /// Time since the newest snapshot landed; null when nothing has been fetched.
  final Duration? syncAge;

  int get healthy => engines.where((e) => e.up).length;

  static const types = ['plan', 'build', 'work', 'light', 'content', 'hands'];

  /// Engines from `/api/ops/status`: `groups` maps a group to services with
  /// `service`, `running` and `exists`. A service that does not exist is not counted.
  static List<EngineHealth> enginesFrom(Map<String, dynamic> status) {
    final out = <EngineHealth>[];
    void add(List<Map<String, dynamic>> rows) {
      for (final s in rows) {
        if (s['exists'] == false) continue;
        final name = fmt.s(s['service']);
        if (name.isEmpty) continue;
        out.add(EngineHealth(name, s['running'] == true));
      }
    }

    for (final g in fmt.m(status['groups']).values) {
      add(fmt.lm(g));
    }
    add(fmt.lm(status['ungrouped']));
    return out;
  }

  static Map<String, int> backlogCounts(Map<String, dynamic> backlog) {
    final by = {for (final t in types) t: 0};
    for (final p in fmt.lm(backlog['projects'])) {
      for (final r in fmt.lm(p['rows'])) {
        final c = fmt.s(r['category']);
        if (by.containsKey(c)) by[c] = by[c]! + 1;
      }
    }
    return by;
  }

  static SystemsDash from({
    required Map<String, dynamic> opsStatus,
    required Map<String, dynamic> backlog,
    required Iterable<DateTime?> fetchTimes,
    required DateTime now,
  }) {
    DateTime? newest;
    for (final t in fetchTimes) {
      if (t != null && (newest == null || t.isAfter(newest))) newest = t;
    }
    return SystemsDash(
      engines: enginesFrom(opsStatus),
      byType: backlogCounts(backlog),
      syncAge: newest == null ? null : now.difference(newest),
    );
  }
}

/// Backup and sync ages colour the same way: amber after 2 hours, red after 24.
Color ageTone(Duration? age) {
  if (age == null) return C.text3;
  if (age >= const Duration(hours: 24)) return C.red;
  if (age >= const Duration(hours: 2)) return C.amber;
  return C.green;
}

/// "5 min", "3 h", "2 d" for an age.
String ageText(Duration d) {
  if (d.inDays >= 1) return '${d.inDays} d';
  if (d.inHours >= 1) return '${d.inHours} h';
  return '${d.inMinutes.clamp(0, 59)} min';
}
