import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../../app_scope.dart';
import '../../data/db.dart';
import '../../data/lesson_notes.dart';
import '../../data/modules.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../shell.dart' show ShellAppBar, SyncIndicator, openMenu;
import '../widgets/common.dart';
import '../widgets/listen_bar.dart';
import '../widgets/reader.dart';
import 'learning_export_stub.dart'
    if (dart.library.io) 'learning_export_native.dart' as export_impl;

/// Courses -> lessons -> reader.
///
/// A module downloaded here stays on the device until its content changes. The
/// state of every module is visible rather than implied, because "can I read
/// this on the train" is a question the UI should answer before the train and
/// not at the moment of failure. See lib/data/modules.dart.
class LearningView extends StatefulWidget {
  const LearningView({super.key});

  @override
  State<LearningView> createState() => _LearningViewState();
}

class _LearningViewState extends State<LearningView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final lib = AppScope.of(context).modules;
      // Check manifest first, then immediately pull anything missing/stale.
      // This is what puts the whole library on the device without the user
      // having to open every module manually.
      await lib.check();
      if (mounted) lib.prefetchAll();
    });
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return ListenableBuilder(
      listenable: services.modules,
      builder: (context, _) => SnapshotView(
        snapshot: services.store.learning,
        builder: (context, data) {
          final courses = fmt.lm(fmt.m(data)['courses']);
          if (courses.isEmpty) {
            return const EmptyState(
              'No courses yet',
              'Courses live in the vault under memory/learning.',
              icon: Icons.school_rounded,
            );
          }
          final lib = services.modules;

          // BN26090604, BI26092611: groups come straight from /api/learning's own
          // `groups` array -- the same live taxonomy the web renders from, in
          // SORT_ORDER. Zero hardcoded track names/order/color; do not re-sort
          // in the client.
          final apiGroups = fmt.lm(fmt.m(data)['groups'])
              .map(LearningGroup.fromApi)
              .toList();
          final groupsById = {for (final g in apiGroups) g.id: g};

          final Map<String, List<Map<String, dynamic>>> byGroup = {};
          final ungrouped = <Map<String, dynamic>>[];
          for (final c in courses) {
            final groupId = fmt.s(c['GROUP_ID']);
            if (groupId.isNotEmpty && groupsById.containsKey(groupId)) {
              byGroup.putIfAbsent(groupId, () => []).add(c);
            } else {
              // A course with no real GROUP_ID is a genuine data problem
              // (per OI26090601 -- every course should resolve to a real
              // group now) -- surfaced visibly, never silently folded into
              // a fabricated "Other" bucket.
              ungrouped.add(c);
            }
          }
          final tracks = [
            for (final g in apiGroups)
              if (byGroup[g.id]?.isNotEmpty ?? false) g,
            if (ungrouped.isNotEmpty) LearningGroup.ungrouped,
          ];
          final coursesForTrack = {
            for (final g in apiGroups) g.id: byGroup[g.id] ?? const [],
            LearningGroup.ungrouped.id: ungrouped,
          };

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── transient prefetch progress only - the idle summary moved
              // down to each track card, where "how much of THIS is offline"
              // is actually actionable rather than one global number nobody
              // can act on from the landing screen.
              if (lib.prefetching)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10, left: 2),
                  child: Row(
                    children: [
                      const MiniSpinner(),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Taking the library offline · ${lib.prefetchDone} of ${lib.prefetchTotal}',
                          style: T.tiny.copyWith(color: C.text2),
                        ),
                      ),
                    ],
                  ),
                ),

              // ── landing: 2-column staggered grid (BI26092611) ─────────────
              // Sconl 26 Sep 2026: emoji-free, colour-coded track cards.
              // A square card takes one cell at about 1:1; a wide card spans both
              // columns at about 2:1. If tile is missing, square is used.
              StaggeredGrid.count(
                crossAxisCount: 2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                children: [
                  for (final group in tracks)
                    StaggeredGridTile.fit(
                      crossAxisCellCount: group.isWide ? 2 : 1,
                      child: TrackCard(
                        group: group,
                        courses: coursesForTrack[group.id] ?? const [],
                      ),
                    ),
                ],
              ),

              // ── low-emphasis library-wide action, moved off the top ──────
              if (!lib.prefetching &&
                  (lib.staleCount > 0 || lib.downloadedCount < lib.knownCount))
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Center(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(Sz.rSm),
                      onTap: () => lib.prefetchAll(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        child: Text(
                          lib.staleCount > 0
                              ? 'Refresh everything (${lib.staleCount} updated)'
                              : 'Download the whole library',
                          style: T.tiny.copyWith(
                              color: C.green, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Strips emoji codepoints from [text] (BI26092611).
String stripEmoji(String text) {
  if (text.isEmpty) return text;
  final emojiRegex = RegExp(
    r'[\u{1F300}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}\u{1F1E6}-\u{1F1FF}\u{1F600}-\u{1F64F}\u{1F680}-\u{1F6FF}\u{1FA00}-\u{1FAFF}]',
    unicode: true,
  );
  return text.replaceAll(emojiRegex, '').replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Parses a hex color string, falling back to [fallback] (defaulting to [C.green]).
/// Accepts 6-hex digits with or without leading '#'.
Color hexColor(String? hex, {Color fallback = C.green}) {
  if (hex == null || hex.isEmpty) return fallback;
  final h = hex.replaceFirst('#', '').trim();
  if (h.length != 6) return fallback;
  final v = int.tryParse(h, radix: 16);
  return v == null ? fallback : Color(0xFF000000 | v);
}

/// One entry from /api/learning's `groups` array -- label, color, tile,
/// sort order, and aggregate counts (BI26092611).
class LearningGroup {
  const LearningGroup({
    required this.id,
    required this.label,
    required this.description,
    required this.color,
    required this.tile,
    required this.sortOrder,
    required this.courseCount,
    required this.moduleCount,
    required this.progressPct,
    required this.status,
  });

  factory LearningGroup.fromApi(Map<String, dynamic> g) {
    final tileRaw = fmt.s(g['tile'] ?? g['TILE']).toLowerCase();
    final tile = tileRaw == 'wide' ? 'wide' : 'square';
    final sortOrderRaw = g['SORT_ORDER'] ?? g['sortOrder'];
    final sortOrder = (sortOrderRaw is num) ? sortOrderRaw.toInt() : 99;
    final colorHex = fmt.s(g['color'] ?? g['COLOR']);

    return LearningGroup(
      id: fmt.s(g['id'] ?? g['ID']),
      label: fmt.s(g['label'] ?? g['LABEL']).isEmpty
          ? fmt.s(g['id'] ?? g['ID'])
          : fmt.s(g['label'] ?? g['LABEL']),
      description: fmt.s(g['description'] ?? g['DESCRIPTION']),
      color: hexColor(colorHex),
      tile: tile,
      sortOrder: sortOrder,
      courseCount: ((g['courseCount'] ?? g['COURSE_COUNT']) is num)
          ? (g['courseCount'] ?? g['COURSE_COUNT'] as num).toInt()
          : 0,
      moduleCount: ((g['moduleCount'] ?? g['MODULE_COUNT']) is num)
          ? (g['moduleCount'] ?? g['MODULE_COUNT'] as num).toInt()
          : 0,
      progressPct: ((g['progressPct'] ?? g['PROGRESS_PCT']) is num)
          ? (g['progressPct'] ?? g['PROGRESS_PCT'] as num).toInt()
          : 0,
      status: fmt.s(g['status'] ?? g['STATUS']),
    );
  }

  /// A real data problem, not a track: courses whose GROUP_ID doesn't match
  /// any live group. Visibly flagged (amber, distinct label).
  static const ungrouped = LearningGroup(
    id: '_ungrouped',
    label: 'Ungrouped — needs a GROUP_ID',
    description: '',
    color: C.amber,
    tile: 'wide',
    sortOrder: 999,
    courseCount: 0,
    moduleCount: 0,
    progressPct: 0,
    status: '',
  );

  final String id;
  final String label;
  final String description;
  final Color color;
  final String tile;
  final int sortOrder;
  final int courseCount;
  final int moduleCount;
  final int progressPct;
  final String status;

  bool get isWide => tile == 'wide';
}

/// Offline coverage only -- courseCount/moduleCount/doneCount now come
/// straight from the API's own group aggregate (LearningGroup), never
/// recomputed here, so the two can't drift out of sync with each other.
class _TrackStats {
  _TrackStats(List<Map<String, dynamic>> courses, [ModuleLibrary? lib]) {
    for (final c in courses) {
      final lessons = fmt.lm(c['lessons']);
      final courseId = fmt.s(c['ID']).isEmpty ? fmt.s(c['id']) : fmt.s(c['ID']);
      for (final l in lessons) {
        final file = fmt.s(l['file']);
        if (file.isEmpty) continue;
        totalModules++;
        if (lib != null) {
          final st = lib.status(courseId, file);
          if (st.downloaded) offlineModules++;
          if (st.state == ModuleState.stale) staleModules++;
        }
      }
    }
  }

  int totalModules = 0;
  int offlineModules = 0;
  int staleModules = 0;
}

/// Track landing card - emoji-free, colour-coded track cards (BI26092611).
/// A square card takes one cell at about 1:1; a wide card spans both columns
/// at about 2:1. Left/top edge in track color, 6-8% tint background, and
/// progress bar in track color with track in C.border.
class TrackCard extends StatelessWidget {
  const TrackCard({
    super.key,
    required this.group,
    required this.courses,
  });

  final LearningGroup group;
  final List<Map<String, dynamic>> courses;

  @override
  Widget build(BuildContext context) {
    ModuleLibrary? lib;
    try {
      lib = AppScope.of(context).modules;
    } catch (_) {}
    final stats = _TrackStats(courses, lib);
    final pct = group.progressPct / 100;
    final allOffline = stats.totalModules > 0 &&
        stats.offlineModules == stats.totalModules &&
        stats.staleModules == 0;

    final bgTint = Color.alphaBlend(group.color.withValues(alpha: 0.07), C.panel);

    return Panel(
      color: bgTint,
      borderColor: C.border,
      padding: EdgeInsets.zero,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TrackDetailScreen(
            track: group.label,
            courses: courses,
            trackColor: group.color,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Thin top band in the track color (BI26092611)
          Container(
            height: 3.5,
            width: double.infinity,
            color: group.color,
          ),
          Padding(
            padding: const EdgeInsets.all(Sz.pad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        stripEmoji(group.label),
                        style: T.title.copyWith(color: C.text),
                        maxLines: group.isWide ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, size: 18, color: C.text3),
                  ],
                ),
                if (group.description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    stripEmoji(group.description),
                    style: T.small.copyWith(color: C.text3),
                    maxLines: group.isWide ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 9),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 4,
                    backgroundColor: C.border,
                    valueColor: AlwaysStoppedAnimation(group.color),
                  ),
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${group.courseCount} '
                        '${group.courseCount == 1 ? 'course' : 'courses'} · '
                        '${group.moduleCount} modules · ${group.progressPct}%',
                        style: T.small.copyWith(color: C.text),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      stats.staleModules > 0
                          ? Icons.sync_problem_rounded
                          : (allOffline
                              ? Icons.offline_pin_rounded
                              : Icons.cloud_download_rounded),
                      size: 12,
                      color: stats.staleModules > 0
                          ? C.amber
                          : (allOffline ? C.green : C.text3),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        stats.staleModules > 0
                            ? '${stats.offlineModules}/${stats.totalModules} on device · ${stats.staleModules} updated'
                            : allOffline
                                ? 'All on this device'
                                : '${stats.offlineModules}/${stats.totalModules} on this device',
                        style: T.tiny.copyWith(
                          color: stats.staleModules > 0 ? C.amber : C.text3,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Formats date as "12 Sep" (or keeps existing formatted string).
String _formatDateDayMonth(dynamic v) {
  final dt = fmt.parseDate(v);
  if (dt == null) return fmt.s(v);
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${dt.day} ${months[dt.month - 1]}';
}

int _courseOrder(Map<String, dynamic> c) {
  if (c['position'] != null) return fmt.i(c['position']);
  if (c['SEQ'] != null) return fmt.i(c['SEQ']);
  if (c['seq'] != null) return fmt.i(c['seq']);
  return 999999;
}

int _moduleOrder(Map<String, dynamic> l) {
  if (l['position'] != null) return fmt.i(l['position']);
  if (l['SEQ'] != null) return fmt.i(l['SEQ']);
  if (l['seq'] != null) return fmt.i(l['seq']);
  if (l['order'] != null) return fmt.i(l['order']);
  return 999999;
}

/// Track detail: the course list for one track only, each course collapsed
/// to a compact summary card. Tap a course to see its full module list.
@visibleForTesting
class TrackDetailScreen extends StatelessWidget {
  const TrackDetailScreen({
    super.key,
    required this.track,
    required this.courses,
    this.trackColor,
  });
  final String track;
  final List<Map<String, dynamic>> courses;
  final Color? trackColor;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = trackColor ?? C.green;
    final sortedCourses = List<Map<String, dynamic>>.from(courses);
    sortedCourses.sort((a, b) {
      final posA = _courseOrder(a);
      final posB = _courseOrder(b);
      if (posA != posB) return posA.compareTo(posB);
      return 0;
    });

    final firstIncompleteIndex = sortedCourses.indexWhere((c) {
      final lessons = fmt.lm(c['lessons']);
      final total = c['modulesTotal'] != null
          ? fmt.i(c['modulesTotal'])
          : lessons.length;
      final done = c['modulesDone'] != null
          ? fmt.i(c['modulesDone'])
          : lessons
              .where((l) => fmt.s(l['status']).toLowerCase() == 'done')
              .length;
      return total == 0 || done < total;
    });

    return Scaffold(
      appBar: ShellAppBar(
        title: track,
        showBrand: true,
        actions: const [SyncIndicator()],
        onMenu: () => openMenu(context),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(Sz.pad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < sortedCourses.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: CourseSummaryCard(
                  course: sortedCourses[i],
                  index: i,
                  isFirstIncomplete: i == firstIncompleteIndex,
                  trackColor: effectiveColor,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Compact course card for the track-detail list: title, progress, module
/// count. Full lesson list lives one tap deeper, in [_CourseDetailScreen].
@visibleForTesting
class CourseSummaryCard extends StatelessWidget {
  const CourseSummaryCard({
    super.key,
    required this.course,
    this.index = 0,
    this.isFirstIncomplete = false,
    this.trackColor = C.green,
  });
  final Map<String, dynamic> course;
  final int index;
  final bool isFirstIncomplete;
  final Color trackColor;

  @override
  Widget build(BuildContext context) {
    final lessons = fmt.lm(course['lessons']);
    final total = course['modulesTotal'] != null
        ? fmt.i(course['modulesTotal'])
        : lessons.length;
    final done = course['modulesDone'] != null
        ? fmt.i(course['modulesDone'])
        : lessons
            .where((l) => fmt.s(l['status']).toLowerCase() == 'done')
            .length;
    final pct = total == 0 ? 0.0 : (done / total).clamp(0.0, 1.0);

    final tVal = fmt.s(course['TITLE']);
    final rawTitle = tVal.isNotEmpty
        ? tVal
        : fmt.s(course['title'] ?? course['ID'] ?? course['id']);
    final title = stripEmoji(rawTitle);

    final subVal = fmt.s(course['SUBTITLE']);
    final rawSubtitle = subVal.isNotEmpty ? subVal : fmt.s(course['subtitle']);
    final subtitle = stripEmoji(rawSubtitle);

    // Subtle number 01, 02 top-right with tabular figures
    final pos = course['position'] ?? course['SEQ'] ?? course['seq'];
    final numVal = pos != null ? fmt.i(pos) : index + 1;
    final numStr = numVal.toString().padLeft(2, '0');

    // Meta line: n/m modules · opened 3d ago, falling back to · updated 12 Sep when never opened
    final lastOpened = fmt.s(course['lastOpenedAt'] ?? course['last_opened_at'] ?? course['lastOpened']);
    final updatedAt = fmt.s(course['updatedAt'] ?? course['updated_at'] ?? course['UPDATED_AT']);

    String metaLine = '$done/$total modules';
    if (lastOpened.isNotEmpty) {
      metaLine += ' · opened ${fmt.ago(lastOpened)}';
    } else if (updatedAt.isNotEmpty) {
      metaLine += ' · updated ${_formatDateDayMonth(updatedAt)}';
    }

    final anyInProgress = lessons.any((l) {
      final st = fmt.s(l['status']).toLowerCase();
      return st == 'learning' || st == 'opened';
    });
    final nothingStarted = done == 0 && lastOpened.isEmpty && !anyInProgress;
    final chipLabel = nothingStarted ? 'Start here' : 'Continue';

    return Panel(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CourseDetailScreen(
            course: course,
            title: title,
            trackColor: trackColor,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: T.title),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(subtitle, style: T.small.copyWith(color: C.text3)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                numStr,
                style: T.small.copyWith(
                  color: C.text3.withValues(alpha: 0.4),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 4,
              backgroundColor: C.border,
              valueColor: AlwaysStoppedAnimation(trackColor),
            ),
          ),
          const SizedBox(height: 6),
          Text(metaLine, style: T.small.copyWith(color: C.text3)),
          if (isFirstIncomplete) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: trackColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: trackColor.withValues(alpha: 0.3)),
              ),
              child: Text(
                chipLabel,
                style: T.tiny.copyWith(
                  color: trackColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Course detail: the existing [_CourseTile]'s full expanded content
/// (module list, take-offline, per-lesson rows), reused as-is rather than
/// rebuilt, pushed as its own screen instead of always-expanded inline.
@visibleForTesting
class CourseDetailScreen extends StatelessWidget {
  const CourseDetailScreen({
    super.key,
    required this.course,
    required this.title,
    this.trackColor,
  });
  final Map<String, dynamic> course;
  final String title;
  final Color? trackColor;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ShellAppBar(
        title: title,
        showBrand: true,
        actions: const [SyncIndicator()],
        onMenu: () => openMenu(context),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(Sz.pad),
        child: CourseTile(course: course, trackColor: trackColor),
      ),
    );
  }
}

@visibleForTesting
class CourseTile extends StatefulWidget {
  const CourseTile({super.key, required this.course, this.trackColor});
  final Map<String, dynamic> course;
  final Color? trackColor;

  @override
  State<CourseTile> createState() => _CourseTileState();
}

class _CourseTileState extends State<CourseTile> {
  bool _pulling = false;
  int _pulled = 0;
  int _total = 0;

  Future<void> _takeOffline(String courseId, List<String> files) async {
    setState(() { _pulling = true; _pulled = 0; _total = files.length; });
    ModuleLibrary? lib;
    try {
      lib = AppScope.of(context).modules;
    } catch (_) {}
    if (lib != null) {
      await lib.downloadCourse(courseId, files, onProgress: (d, t) {
        if (mounted) setState(() { _pulled = d; _total = t; });
      });
    }
    if (!mounted) return;
    setState(() => _pulling = false);
    toast(context, '$courseId is on this device');
  }

  @override
  Widget build(BuildContext context) {
    final effectiveColor = widget.trackColor ?? C.green;
    ModuleLibrary? lib;
    try {
      lib = AppScope.of(context).modules;
    } catch (_) {}

    final rawLessons = fmt.lm(widget.course['lessons']);
    final lessons = List<Map<String, dynamic>>.from(rawLessons);
    lessons.sort((a, b) {
      final posA = _moduleOrder(a);
      final posB = _moduleOrder(b);
      if (posA != posB) return posA.compareTo(posB);
      return 0;
    });

    final done = lessons
        .where((l) => fmt.s(l['status']).toLowerCase() == 'done')
        .length;
    final pct = lessons.isEmpty ? 0.0 : done / lessons.length;
    final courseId = fmt.s(widget.course['ID']).isEmpty
        ? fmt.s(widget.course['id'])
        : fmt.s(widget.course['ID']);

    final files = lessons.map((l) => fmt.s(l['file'])).where((f) => f.isNotEmpty).toList();
    final offline = files
        .where((f) => lib?.status(courseId, f).downloaded ?? false)
        .length;
    final stale = files
        .where((f) => lib?.status(courseId, f).state == ModuleState.stale)
        .length;
    final allHere = files.isNotEmpty && offline == files.length && stale == 0;

    final nextIndex = lessons.indexWhere((l) => fmt.s(l['status']).toLowerCase() != 'done');

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  fmt.s(widget.course['TITLE']).isEmpty
                      ? courseId
                      : fmt.s(widget.course['TITLE']),
                  style: T.w600(T.body2),
                ),
              ),
              Text('$done/${lessons.length}',
                  style: T.mono.copyWith(color: effectiveColor)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 4,
              backgroundColor: C.border,
              valueColor: AlwaysStoppedAnimation(effectiveColor),
            ),
          ),
          if (files.isNotEmpty) ...[
            const SizedBox(height: 9),
            Row(
              children: [
                Icon(
                    allHere ? Icons.offline_pin_rounded : Icons.cloud_download_rounded,
                    size: 12,
                    color: allHere ? C.green : (stale > 0 ? C.amber : C.text3)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _pulling
                        ? 'Downloading $_pulled of $_total...'
                        : stale > 0
                            ? '$offline of ${files.length} on this device · $stale updated'
                            : allHere
                                ? 'All ${files.length} on this device'
                                : '$offline of ${files.length} on this device',
                    style: T.tiny.copyWith(
                        color: stale > 0 ? C.amber : (allHere ? C.green : C.text3)),
                  ),
                ),
                if (!allHere && !_pulling)
                  InkWell(
                    borderRadius: BorderRadius.circular(Sz.rSm),
                    onTap: () => _takeOffline(courseId, files),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      child: Text(stale > 0 ? 'Update all' : 'Take offline',
                          style: T.tiny.copyWith(
                              color: C.green, fontWeight: FontWeight.w600)),
                    ),
                  ),
                if (_pulling) const MiniSpinner(),
              ],
            ),
          ],
          const SizedBox(height: 10),
          for (var i = 0; i < lessons.length; i++)
            LessonRow(
              courseId: courseId,
              lesson: lessons[i],
              nextLesson: i + 1 < lessons.length ? lessons[i + 1] : null,
              allLessons: lessons,
              index: i,
              isNext: i == nextIndex,
              trackColor: effectiveColor,
            ),
        ],
      ),
    );
  }
}

@visibleForTesting
class ModuleStateDot extends StatelessWidget {
  const ModuleStateDot({super.key, required this.status, required this.color});
  final String status;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final s = status.toLowerCase();
    if (s == 'done') {
      return Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
        ),
      );
    } else if (s == 'opened' || s == 'learning') {
      return CustomPaint(
        size: const Size(10, 10),
        painter: _HalfFilledDotPainter(color: color),
      );
    } else {
      return Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: C.text3, width: 1.5),
        ),
      );
    }
  }
}

class _HalfFilledDotPainter extends CustomPainter {
  const _HalfFilledDotPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Draw filled left half
    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi / 2,
      math.pi,
      true,
      fillPaint,
    );

    // Draw outer ring
    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, radius - 0.75, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _HalfFilledDotPainter oldDelegate) =>
      oldDelegate.color != color;
}

@visibleForTesting
class LessonRow extends StatelessWidget {
  const LessonRow({
    super.key,
    required this.courseId,
    required this.lesson,
    this.nextLesson,
    this.allLessons = const [],
    this.index = 0,
    this.isNext = false,
    this.trackColor = C.green,
  });
  final String courseId;
  final Map<String, dynamic> lesson;
  final Map<String, dynamic>? nextLesson;
  final List<Map<String, dynamic>> allLessons;
  final int index;
  final bool isNext;
  final Color trackColor;

  @override
  Widget build(BuildContext context) {
    ModuleLibrary? lib;
    try {
      lib = AppScope.of(context).modules;
    } catch (_) {}

    final file = fmt.s(lesson['file']);
    final rawStatus = fmt.s(lesson['status']).toLowerCase();
    final lastOpened = fmt.s(lesson['lastOpenedAt'] ?? lesson['last_opened_at'] ?? lesson['lastOpened']);
    final status = rawStatus.isNotEmpty
        ? rawStatus
        : (lastOpened.isNotEmpty ? 'opened' : 'new');
    final st = lib?.status(courseId, file) ?? const ModuleStatus(ModuleState.absent);

    final tVal = fmt.s(lesson['TITLE']);
    final rawTitle = tVal.isNotEmpty ? tVal : fmt.s(lesson['title'] ?? file);
    final title = stripEmoji(rawTitle);

    final subVal = fmt.s(lesson['SUBTITLE']);
    final rawSubtitle = subVal.isNotEmpty ? subVal : fmt.s(lesson['subtitle']);
    final subtitle = stripEmoji(rawSubtitle);

    final pos = lesson['position'] ?? lesson['SEQ'] ?? lesson['seq'] ?? lesson['order'];
    final numVal = pos != null ? fmt.i(pos) : index + 1;
    final numStr = numVal.toString().padLeft(2, '0');

    // Meta line: "8 min read · updated 20 Sep"
    String? readTimeStr;
    final readTimeVal = lesson['readTime'] ?? lesson['readingTime'] ?? lesson['minRead'] ?? lesson['read_time'];
    if (readTimeVal != null) {
      final sVal = fmt.s(readTimeVal);
      if (sVal.contains('min')) {
        readTimeStr = sVal;
      } else {
        final m = fmt.i(readTimeVal);
        if (m > 0) readTimeStr = '$m min read';
      }
    } else if (lesson['words'] != null) {
      final w = fmt.i(lesson['words']);
      if (w > 0) {
        final mins = (w / 220).ceil();
        readTimeStr = '$mins min read';
      }
    }

    String? updatedStr;
    final updatedVal = lesson['updatedAt'] ?? lesson['updated_at'] ?? lesson['UPDATED_AT'] ?? lesson['reviewedAt'] ?? st.updated;
    if (updatedVal != null && fmt.s(updatedVal).isNotEmpty) {
      final d = _formatDateDayMonth(updatedVal);
      if (d.isNotEmpty) updatedStr = 'updated $d';
    }

    final metaParts = [
      if (readTimeStr != null && readTimeStr.isNotEmpty) readTimeStr,
      if (updatedStr != null && updatedStr.isNotEmpty) updatedStr,
    ];
    final metaLine = metaParts.join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(Sz.rSm),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => LessonScreen(
              course: courseId,
              file: file,
              title: title,
              status: rawStatus.isEmpty ? status : rawStatus,
              nextLesson: nextLesson,
              allLessons: allLessons,
              trackColor: trackColor,
              reviewedAt: fmt.s(lesson['reviewedAt'] ??
                  lesson['reviewed_at'] ??
                  lesson['REVIEWED_AT']),
              version: fmt.s(lesson['version'] ?? lesson['VERSION']),
            ),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isNext ? trackColor.withValues(alpha: 0.08) : Colors.transparent,
            borderRadius: BorderRadius.circular(Sz.rSm),
            border: isNext
                ? Border.all(color: trackColor.withValues(alpha: 0.25))
                : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  numStr,
                  style: T.small.copyWith(
                    color: C.text3.withValues(alpha: 0.4),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 4.5),
                child: ModuleStateDot(status: status, color: trackColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: T.w600(T.body2).copyWith(
                        color: status == 'done' ? C.text3 : C.text,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: T.small.copyWith(color: C.text3),
                      ),
                    ],
                    if (metaLine.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        metaLine,
                        style: T.tiny.copyWith(color: C.text3),
                      ),
                    ],
                  ],
                ),
              ),
              if (st.state == ModuleState.stale)
                const Tooltip(
                  message: 'Updated on the agent - opens the new version',
                  child: Icon(Icons.sync_problem_rounded, size: 12, color: C.amber),
                )
              else if (st.downloaded)
                const Tooltip(
                  message: 'On this device',
                  child: Icon(Icons.offline_pin_rounded, size: 12, color: C.green),
                ),
              const SizedBox(width: 6),
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(Icons.chevron_right_rounded, size: 15, color: C.text3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LessonScreen extends StatefulWidget {
  const LessonScreen({
    super.key,
    required this.course,
    required this.file,
    required this.title,
    required this.status,
    this.nextLesson,
    this.allLessons = const [],
    this.trackColor = C.green,
    this.reviewedAt,
    this.version,
  });

  final String course;
  final String file;
  final String title;
  final String status;
  final Map<String, dynamic>? nextLesson;
  final List<Map<String, dynamic>> allLessons;
  final Color trackColor;
  final String? reviewedAt;
  final String? version;

  @override
  State<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends State<LessonScreen> {
  late String _status = widget.status;
  String? _previousStatus;
  bool _canUndo = false;
  Timer? _undoTimer;
  final _scroll = ScrollController();
  Timer? _resumeDebounce;
  bool _restoredResume = false;
  bool _showScrollTop = false;
  String? _currentContent;

  Map<String, dynamic>? get _computedNextLesson {
    if (widget.nextLesson != null) return widget.nextLesson;
    if (widget.allLessons.isNotEmpty) {
      final idx = widget.allLessons
          .indexWhere((l) => fmt.s(l['file']) == widget.file);
      if (idx >= 0 && idx + 1 < widget.allLessons.length) {
        return widget.allLessons[idx + 1];
      }
    }
    return null;
  }

  // BL26091028: mirrors _computedNextLesson for the Previous direction --
  // mobile had no Previous nav at all before this (web has both).
  Map<String, dynamic>? get _computedPrevLesson {
    if (widget.allLessons.isNotEmpty) {
      final idx = widget.allLessons
          .indexWhere((l) => fmt.s(l['file']) == widget.file);
      if (idx > 0) return widget.allLessons[idx - 1];
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    // The cached body is served immediately - that is the whole point of
    // keeping it. A refresh is issued ONLY when the agent's revision differs
    // from the one on disk, so opening a module you already have costs nothing
    // and works with no signal.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final lib = AppScope.of(context).modules;
      final st = lib.status(widget.course, widget.file);
      if (st.state == ModuleState.stale) {
        await lib.download(widget.course, widget.file);
      }
      if (!mounted) return;
      final services = AppScope.of(context);
      final localStatus = await services.db.lessonStatusLocal(
        course: widget.course,
        file: widget.file,
      );
      if (!mounted) return;
      var eff = _status;
      if (localStatus != null &&
          AppDb.statusRank(localStatus) > AppDb.statusRank(eff)) {
        eff = localStatus;
        setState(() => _status = eff);
      }
      // BI26092613: Opening the module sets Opened (only if it was new/unstarted).
      if (eff.isEmpty || eff.toLowerCase() == 'new') {
        setState(() => _status = 'opened');
        services.db.saveLessonStatusLocal(
          course: widget.course,
          file: widget.file,
          status: 'opened',
        );
        services.mutations.lessonProgress(widget.course, widget.file, 'opened');
      }
    });
    _scroll.addListener(_onScroll);
  }

  // BI26092613: local, always-on scroll-position tracking -- written
  // to local db and queued in outbox in the same call, debounced to 2 s
  // while scrolling and on leaving the screen, as a fraction 0 to 1.
  void _onScroll() {
    if (!_scroll.hasClients || _scroll.position.maxScrollExtent <= 0) return;
    // BI26092614: scroll-to-top appears only after scrolling past one screen height.
    final show = _scroll.offset > MediaQuery.of(context).size.height;
    if (show != _showScrollTop) {
      setState(() => _showScrollTop = show);
    }

    final maxExtent = _scroll.position.maxScrollExtent;
    final fraction = (maxExtent > 0 ? _scroll.position.pixels / maxExtent : 0.0)
        .clamp(0.0, 1.0);

    // BI26092613: Scrolling past 10% sets Learning (only if it was opened).
    if (fraction > 0.10 && _status.toLowerCase() == 'opened') {
      setState(() => _status = 'learning');
      final services = AppScope.of(context);
      services.db.saveLessonStatusLocal(
        course: widget.course,
        file: widget.file,
        status: 'learning',
      );
      services.mutations.lessonProgress(widget.course, widget.file, 'learning');
    }

    // BI26092613: Saved locally, debounced to 2 s while scrolling.
    _resumeDebounce?.cancel();
    _resumeDebounce = Timer(const Duration(seconds: 2), () {
      _saveResumeNow();
    });
  }

  void _saveResumeNow() {
    if (!mounted || !_scroll.hasClients || _scroll.position.maxScrollExtent <= 0) return;
    final maxExtent = _scroll.position.maxScrollExtent;
    final fraction = (maxExtent > 0 ? _scroll.position.pixels / maxExtent : 0.0)
        .clamp(0.0, 1.0);
    final pct = (fraction * 100).round().clamp(0, 100);
    final services = AppScope.of(context);
    services.db.saveLessonResumeLocal(
      course: widget.course,
      file: widget.file,
      scrollPct: pct,
      fraction: fraction,
    );
    services.mutations.saveLessonResume(
      course: widget.course,
      lesson: widget.file,
      scrollPct: pct,
      fraction: fraction,
    );
  }

  /// BI26092614: calculates the index of the topmost visible block/paragraph.
  int _computeTopmostBlockIndex() {
    if (_currentContent == null || _currentContent!.isEmpty || !_scroll.hasClients) {
      return 0;
    }
    final maxExtent = _scroll.position.maxScrollExtent;
    if (maxExtent <= 0) return 0;
    final paragraphs = _currentContent!
        .split(RegExp(r'\n\s*\n'))
        .where((p) => p.trim().isNotEmpty)
        .toList();
    if (paragraphs.isEmpty) return 0;
    final progress = (_scroll.offset / maxExtent).clamp(0.0, 1.0);
    return (progress * paragraphs.length).floor().clamp(0, paragraphs.length - 1);
  }

  /// BI26092614: opens the notes bottom sheet with block anchor context.
  void _openNotesSheet(BuildContext context) {
    HapticFeedback.selectionClick();
    final anchor = _computeTopmostBlockIndex();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Sz.rXl)),
        side: BorderSide(color: C.border),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: C.borderMid,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                _LessonNotes(
                  course: widget.course,
                  file: widget.file,
                  anchor: anchor,
                  inSheet: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Jumps to the locally-saved scroll position once the content has laid
  /// out (needs maxScrollExtent to be known -- a post-frame callback after
  /// SnapshotView's builder has actually rendered the reading surface, not
  /// before). Called from the content builder below since that's the first
  /// point layout is guaranteed to exist; `_restoredResume` guards against
  /// re-jumping on every rebuild.
  void _maybeRestoreResume() {
    if (_restoredResume) return;
    _restoredResume = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !_scroll.hasClients) return;
      final frac = await AppScope.of(context).db.lessonResumeFractionLocal(
            course: widget.course,
            file: widget.file,
          );
      if (frac == null || !mounted || !_scroll.hasClients) return;
      final target = _scroll.position.maxScrollExtent * frac;
      if (target > 0) _scroll.jumpTo(target.clamp(0, _scroll.position.maxScrollExtent));
    });
  }

  @override
  void dispose() {
    _resumeDebounce?.cancel();
    _undoTimer?.cancel();
    _saveResumeNow();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  Widget _buildDoneButton(AppServices services) {
    if (_canUndo) {
      return OutlinedButton.icon(
        icon: const Icon(Icons.undo_rounded, size: 16),
        label: const Text('Done · undo'),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: widget.trackColor),
          foregroundColor: widget.trackColor,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        onPressed: () {
          _undoTimer?.cancel();
          final revertTo = _previousStatus ?? 'learning';
          setState(() {
            _canUndo = false;
            _status = revertTo;
          });
          services.db.saveLessonStatusLocal(
            course: widget.course,
            file: widget.file,
            status: revertTo,
            force: true,
          );
          services.mutations.lessonProgress(
            widget.course,
            widget.file,
            revertTo,
            force: true,
          );
        },
      );
    }

    if (_status.toLowerCase() == 'done') {
      return OutlinedButton.icon(
        icon: const Icon(Icons.check_circle_rounded, size: 16, color: C.green),
        label: const Text('Completed'),
        style: OutlinedButton.styleFrom(
          foregroundColor: C.text3,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        onPressed: null,
      );
    }

    final isDarkTrack = widget.trackColor.computeLuminance() < 0.5;
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: widget.trackColor,
        foregroundColor: isDarkTrack ? Colors.white : Colors.black,
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
      onPressed: () {
        _previousStatus = _status;
        setState(() {
          _status = 'done';
          _canUndo = true;
        });
        _undoTimer?.cancel();
        _undoTimer = Timer(const Duration(seconds: 5), () {
          if (mounted) setState(() => _canUndo = false);
        });

        services.db.saveLessonStatusLocal(
          course: widget.course,
          file: widget.file,
          status: 'done',
        );
        services.mutations.lessonProgress(
          widget.course,
          widget.file,
          'done',
        );
      },
      child: const Text('Mark as done'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final snap = services.store.detail(
      'lesson',
      '${widget.course}/${widget.file}',
      '/api/learning/lesson?course=${Uri.encodeComponent(widget.course)}&file=${Uri.encodeComponent(widget.file)}',
    );
    final heading = widget.title.isEmpty ? widget.file : widget.title;

    return Scaffold(
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SquareFab(
            heroTag: 'fab_lesson_notes',
            tooltip: 'Notes',
            icon: const Icon(Icons.edit_note_rounded),
            onPressed: () => _openNotesSheet(context),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SizeTransition(
                sizeFactor: animation,
                child: child,
              ),
            ),
            child: _showScrollTop
                ? Padding(
                    key: const ValueKey('fab_scroll_top_visible'),
                    padding: const EdgeInsets.only(top: 12),
                    child: SquareFab(
                      heroTag: 'fab_lesson_scroll_top',
                      tooltip: 'Scroll to top',
                      icon: const Icon(Icons.vertical_align_top_rounded),
                      onPressed: () {
                        if (_scroll.hasClients) {
                          _scroll.animateTo(
                            0,
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.easeOutCubic,
                          );
                        }
                      },
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey('fab_scroll_top_hidden')),
          ),
        ],
      ),
      appBar: ShellAppBar(
        title: heading,
        showBrand: false,
        actions: [
          _ExportPdfButton(course: widget.course, file: widget.file),
        ],
      ),
      body: Column(
        children: [
          ReadingProgress(controller: _scroll),
          Expanded(
            child: SnapshotView(
              snapshot: snap,
              controller: _scroll,
              // The reading surface owns its own margins, so the scroll view
              // contributes nothing horizontally. Bottom room is for the
              // thumb, not for a nav bar - this screen is pushed, not tabbed.
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 56),
              builder: (context, data) {
                final lessonMap = fmt.m(data);
                final content = fmt.s(lessonMap['content']);
                final updatedAt = fmt.s(lessonMap['updatedAt']);
                final reviewedAt = fmt.s(lessonMap['reviewedAt'] ??
                    lessonMap['reviewed_at'] ??
                    lessonMap['REVIEWED_AT'] ??
                    widget.reviewedAt);
                final version = fmt.s(lessonMap['version'] ??
                    lessonMap['VERSION'] ??
                    widget.version);
                _currentContent = content;
                _maybeRestoreResume();
                return ReadingSurface(
                  children: [
                    ReadingHeader(
                      title: heading,
                      kicker: widget.course,
                      meta: content.isEmpty
                          ? null
                          : readingMeta(
                              content,
                              updatedAt: updatedAt.isEmpty ? null : updatedAt,
                              reviewedAt:
                                  reviewedAt.isEmpty ? null : reviewedAt,
                              version: version.isEmpty ? null : version,
                            ),
                      trailing: Row(
                        children: [
                          for (final (st, label) in [
                            ('opened', 'Opened'),
                            ('learning', 'Learning'),
                            ('done', 'Done'),
                          ]) ...[
                            Pill(
                              label,
                              selected: _status.toLowerCase() == st,
                              color: widget.trackColor,
                              onTap: null,
                            ),
                            const SizedBox(width: 6),
                          ],
                        ],
                      ),
                    ),
                    if (content.isNotEmpty)
                      ListenBar(
                          course: widget.course,
                          file: widget.file,
                          markdown: content),
                    if (content.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 26),
                        child: Text(
                          'Lesson content loads when online, then stays cached '
                          'on this device for reading offline.',
                          style: T.body2.copyWith(color: C.text3, height: 1.6),
                        ),
                      )
                    else
                      ReadingBody(content,
                          courseId: widget.course,
                          baseUrl: services.api.baseUrl,
                          token: services.api.token),
                    _LessonNotes(course: widget.course, file: widget.file),
                    // BI26092613: "Mark as done" button at the end of the module,
                    // full width, in the track colour. Shows "Done · undo" for 5 seconds.
                    Padding(
                      padding: const EdgeInsets.only(top: 24, bottom: 8),
                      child: SizedBox(
                        width: double.infinity,
                        child: _buildDoneButton(services),
                      ),
                    ),
                    if (_computedNextLesson != null || _computedPrevLesson != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 20),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            if (_computedPrevLesson != null)
                              _LessonNavButton(
                                icon: Icons.chevron_left_rounded,
                                iconTrailing: false,
                                label: lessonNavLabel('Previous',
                                    fmt.s(_computedPrevLesson!['title']).isEmpty
                                        ? fmt.s(_computedPrevLesson!['file'])
                                        : fmt.s(_computedPrevLesson!['title'])),
                                onTap: () => Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => LessonScreen(
                                      course: widget.course,
                                      file: fmt.s(_computedPrevLesson!['file']),
                                      title: fmt.s(_computedPrevLesson!['title']),
                                      status: fmt.s(_computedPrevLesson!['status']),
                                      allLessons: widget.allLessons,
                                      trackColor: widget.trackColor,
                                    ),
                                  ),
                                ),
                              )
                            else
                              const SizedBox.shrink(),
                            if (_computedNextLesson != null)
                              _LessonNavButton(
                                icon: Icons.chevron_right_rounded,
                                iconTrailing: true,
                                label: lessonNavLabel('Next',
                                    fmt.s(_computedNextLesson!['title']).isEmpty
                                        ? fmt.s(_computedNextLesson!['file'])
                                        : fmt.s(_computedNextLesson!['title'])),
                                onTap: () => Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => LessonScreen(
                                      course: widget.course,
                                      file: fmt.s(_computedNextLesson!['file']),
                                      title: fmt.s(_computedNextLesson!['title']),
                                      status: fmt.s(_computedNextLesson!['status']),
                                      allLessons: widget.allLessons,
                                      trackColor: widget.trackColor,
                                    ),
                                  ),
                                ),
                              )
                            else if (widget.allLessons.isNotEmpty)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.check_circle_rounded,
                                      size: 16, color: C.green),
                                  const SizedBox(width: 8),
                                  Text('Course complete',
                                      style: T.small.copyWith(color: C.text3)),
                                ],
                              )
                            else
                              const SizedBox.shrink(),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Margin notes on a lesson.
///
/// Two other readers besides him: the tutor loads them as context, and the
/// agent reads them when revising the course - a note saying "this section is
/// now wrong" is the cheapest possible course-update instruction. Which is why
/// this is worth having on the phone, where most of the reading happens.
/// Export this module as a PDF and hand it to the phone.
///
/// The agent builds the PDF - one renderer, one set of callout colours, one
/// document whether it was asked for from the console or from here. This end
/// only has to move the bytes to disk and let Android open them, which is what
/// makes "export from the mobile app" a small feature rather than a second
/// implementation of the whole document.
class _ExportPdfButton extends StatefulWidget {
  const _ExportPdfButton({required this.course, required this.file});
  final String course;
  final String file;

  @override
  State<_ExportPdfButton> createState() => _ExportPdfButtonState();
}

class _ExportPdfButtonState extends State<_ExportPdfButton> {
  bool _busy = false;

  Future<void> _run() async {
    if (_busy) return;
    setState(() => _busy = true);
    final services = AppScope.of(context);
    try {
      final res = await services.api.getBytes(
          '/api/learning/export?course=${Uri.encodeComponent(widget.course)}'
          '&lesson=${Uri.encodeComponent(widget.file)}');

      final name = res.filename.isEmpty
          ? '${widget.course}-${widget.file.replaceAll(RegExp(r'\.md$'), '')}.pdf'
          : res.filename;
      final opened = await export_impl.saveAndOpenExport(name, res.bytes);

      if (!mounted) return;
      toast(
          context,
          opened
              ? '${(res.bytes.length / 1024).round()} KB - opening'
              : kIsWeb
                  ? 'PDF export isn\'t available in the web console yet'
                  : 'Saved, but nothing on this phone opens a PDF',
          error: !opened);
    } catch (e) {
      if (!mounted) return;
      toast(context, 'Export failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: _busy ? null : _run,
      tooltip: 'Export this module as a PDF',
      icon: _busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.download_rounded, size: 20),
    );
  }
}

/// BL26091006/BL26091028: shared Next/Previous nav button -- an outlined
/// pill with the 3-word-lead-in label and a chevron on whichever side
/// matches the direction (leading for Previous, trailing for Next).
class _LessonNavButton extends StatelessWidget {
  const _LessonNavButton({
    required this.icon,
    required this.iconTrailing,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final bool iconTrailing;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final iconWidget = Icon(icon, size: 18, color: C.green);
    final labelWidget = Text(label,
        style: T.small.copyWith(color: C.green, fontWeight: FontWeight.w600));
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Sz.rSm)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        side: const BorderSide(color: C.greenDim),
      ),
      onPressed: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: iconTrailing
            ? [labelWidget, const SizedBox(width: 4), iconWidget]
            : [iconWidget, const SizedBox(width: 4), labelWidget],
      ),
    );
  }
}

typedef _LessonNotes = LessonNotes;

/// Module notes widget. Keeps storage isolated behind LessonNotesRepository
/// (Study-on-Canvas contract).
class LessonNotes extends StatefulWidget {
  const LessonNotes({
    super.key,
    required this.course,
    required this.file,
    this.anchor,
    this.inSheet = false,
    this.repository,
  });

  final String course;
  final String file;
  final int? anchor;
  final bool inSheet;
  final LessonNotesRepository? repository;

  @override
  State<LessonNotes> createState() => _LessonNotesState();
}

class _LessonNotesState extends State<LessonNotes> {
  final _controller = TextEditingController();
  late bool _open = widget.inSheet;
  bool _loading = false;
  bool _loaded = false;
  bool _saving = false;
  String? _error;
  int? _anchor;

  LessonNotesRepository _repo(BuildContext context) =>
      widget.repository ?? AppScope.of(context).lessonNotes;

  @override
  void initState() {
    super.initState();
    _anchor = widget.anchor;
    if (widget.inSheet) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loaded || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final note = await _repo(context).getNote(
        course: widget.course,
        file: widget.file,
      );
      if (!mounted) return;
      if (note != null) {
        _controller.text = note.text;
        _anchor ??= note.anchor;
      }
      setState(() => _loaded = true);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not load your notes ($e).');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final res = await _repo(context).saveNote(
      course: widget.course,
      file: widget.file,
      text: _controller.text,
      anchor: _anchor,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (!res.ok) {
      toast(context, res.error!, error: true);
    } else if (res.queued) {
      toast(context, 'Note queued - will sync');
    } else {
      toast(context, 'Note saved');
    }
  }

  @override
  Widget build(BuildContext context) {
    final noteBody = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null)
          ErrorRetry(_error!, onRetry: () {
            _loaded = false;
            _load();
          }),
        TextField(
          controller: _controller,
          maxLines: null,
          minLines: 5,
          style: T.body.copyWith(
              fontSize: 15, height: 1.62, color: C.text),
          decoration: InputDecoration(
            filled: false,
            contentPadding: const EdgeInsets.symmetric(vertical: 6),
            hintText: 'Write it here.',
            hintStyle: T.body2.copyWith(color: C.text3, fontSize: 15),
            enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: C.border)),
            focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: C.green)),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const MiniSpinner()
                  : const Icon(Icons.save_rounded, size: 16),
              label: const Text('Save note'),
            ),
            if (_anchor != null)
              Text(
                'Anchored to paragraph ${_anchor! + 1}',
                style: T.tiny.copyWith(color: C.text3),
              ),
          ],
        ),
      ],
    );

    if (widget.inSheet) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('NOTES', style: T.label.copyWith(color: C.text2)),
              if (_loading) const MiniSpinner(),
            ],
          ),
          const SizedBox(height: 10),
          noteBody,
        ],
      );
    }

    return ReadingSection(
      label: 'Your notes',
      trailing: InkWell(
        borderRadius: BorderRadius.circular(Sz.rSm),
        onTap: () {
          setState(() => _open = !_open);
          if (_open) _load();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_loading) ...[const MiniSpinner(), const SizedBox(width: 8)],
              Text(_open ? 'Close' : 'Write', style: T.tiny.copyWith(color: C.green)),
              Icon(
                  _open
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 16,
                  color: C.green),
            ],
          ),
        ),
      ),
      child: !_open
          ? Text(
              'What you made of it. The tutor loads these as context, and the '
              'agent reads them when it revises the course.',
              style: T.body2.copyWith(color: C.text3, height: 1.6),
            )
          : noteBody,
    );
  }
}

