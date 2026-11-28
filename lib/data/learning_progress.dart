import '../util/fmt.dart' as fmt;
import 'db.dart' show AppDb;

/// Reading progress shows at once, online or offline (Sconl, 28 Nov 2026: "the progress bars and the realtime state is
/// to reflect in the ui immediately, even offline").
///
/// The library payload carries each module's `status` and two server-made totals: a course's `modulesDone` and a
/// track's `progressPct` (over its `moduleCount`). The bars read those totals, so changing one module's status alone
/// left every bar where it was until the next sync. This sets the statuses and moves both totals by the same step, so
/// the bars, the pills and the counts agree before the server has heard anything.
///
/// [statuses] maps `course/file` to the new status. Without [force] a status only moves up the rank
/// (new < opened < learning < done), the same rule the local store keeps; [force] is the reader's Undo.
/// Returns [learning] unchanged when nothing moved.
dynamic withLessonStatuses(dynamic learning, Map<String, String> statuses, {bool force = false}) {
  if (learning is! Map || statuses.isEmpty) return learning;
  final courses = learning['courses'];
  if (courses is! List) return learning;

  var changed = false;
  final doneDeltaByGroup = <String, int>{};
  final outCourses = <dynamic>[];
  for (final raw in courses) {
    if (raw is! Map) {
      outCourses.add(raw);
      continue;
    }
    final courseId = fmt.s(raw['ID']).isNotEmpty ? fmt.s(raw['ID']) : fmt.s(raw['id']);
    final lessons = raw['lessons'];
    if (lessons is! List || !statuses.keys.any((k) => k.startsWith('$courseId/'))) {
      outCourses.add(raw);
      continue;
    }
    var courseDelta = 0;
    var courseChanged = false;
    final outLessons = <dynamic>[];
    for (final l in lessons) {
      if (l is! Map) {
        outLessons.add(l);
        continue;
      }
      final want = statuses['$courseId/${fmt.s(l['file'])}'];
      if (want == null) {
        outLessons.add(l);
        continue;
      }
      final cur = fmt.s(l['status']).toLowerCase().trim();
      final next = force ? want.toLowerCase().trim() : AppDb.mergeStatus(want, cur.isEmpty ? 'new' : cur);
      if (next == cur) {
        outLessons.add(l);
        continue;
      }
      courseDelta += (next == 'done' ? 1 : 0) - (cur == 'done' ? 1 : 0);
      courseChanged = true;
      outLessons.add({...Map<String, dynamic>.from(l), 'status': next});
    }
    if (!courseChanged) {
      outCourses.add(raw);
      continue;
    }
    changed = true;
    final c = Map<String, dynamic>.from(raw)..['lessons'] = outLessons;
    if (courseDelta != 0) {
      if (c['modulesDone'] != null) {
        final total = c['modulesTotal'] != null ? fmt.i(c['modulesTotal']) : outLessons.length;
        c['modulesDone'] = (fmt.i(c['modulesDone']) + courseDelta).clamp(0, total < 0 ? 0 : total);
      }
      final g = fmt.s(c['GROUP_ID']);
      if (g.isNotEmpty) doneDeltaByGroup[g] = (doneDeltaByGroup[g] ?? 0) + courseDelta;
    }
    outCourses.add(c);
  }
  if (!changed) return learning;

  final out = Map<String, dynamic>.from(learning)..['courses'] = outCourses;
  final groups = learning['groups'];
  if (doneDeltaByGroup.isNotEmpty && groups is List) {
    out['groups'] = [
      for (final g in groups)
        if (g is Map && doneDeltaByGroup.containsKey(fmt.s(g['id'] ?? g['ID'])))
          _movedGroup(Map<String, dynamic>.from(g), doneDeltaByGroup[fmt.s(g['id'] ?? g['ID'])]!)
        else
          g,
    ];
  }
  return out;
}

Map<String, dynamic> _movedGroup(Map<String, dynamic> g, int doneDelta) {
  final count = fmt.i(g['moduleCount'] ?? g['MODULE_COUNT']);
  if (count <= 0) return g;
  final key = g.containsKey('progressPct') || !g.containsKey('PROGRESS_PCT') ? 'progressPct' : 'PROGRESS_PCT';
  final pct = (g[key] is num ? (g[key] as num).toDouble() : 0.0) + doneDelta * 100.0 / count;
  // Kept as a fraction so repeated steps do not drift; the card rounds it for display.
  g[key] = pct.clamp(0.0, 100.0);
  return g;
}

/// The live copy of one course in the library payload, or null.
Map<String, dynamic>? liveCourse(dynamic learning, String courseId) {
  if (courseId.isEmpty) return null;
  for (final c in fmt.lm(fmt.m(learning)['courses'])) {
    final id = fmt.s(c['ID']).isNotEmpty ? fmt.s(c['ID']) : fmt.s(c['id']);
    if (id == courseId) return c;
  }
  return null;
}
