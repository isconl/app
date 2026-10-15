import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../../app_scope.dart';
import '../../data/db.dart';
import '../../util/markdown.dart' show MarkdownAnchors, ModuleLink;
import '../../data/lesson_notes.dart';
import '../../data/modules.dart';
import '../../study/cdm/cdm_lesson_body.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../../util/reader_prefs.dart';
import '../../util/spaced_review.dart';
import 'study_search_view.dart';
import '../shell.dart' show ShellAppBar, SyncIndicator, openMenu;
import '../widgets/common.dart';
import '../widgets/course_controls.dart';
import '../widgets/listen_bar.dart';
import '../widgets/module_lifecycle.dart';
import '../widgets/reader.dart';
import '../widgets/track_admin.dart';
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
          // BI26100538: a library with no courses but with tracks still shows its tracks.
          if (courses.isEmpty && fmt.lm(fmt.m(data)['groups']).isEmpty) {
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
          // BI26100538: nothing disappears. Every track spark returns is shown, an empty one with its
          // empty state, in spark's order.
          final tracks = [
            ...apiGroups,
            if (ungrouped.isNotEmpty) LearningGroup.ungrouped,
          ];
          final coursesForTrack = {
            for (final g in apiGroups) g.id: byGroup[g.id] ?? const [],
            LearningGroup.ungrouped.id: ungrouped,
          };

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(padding: EdgeInsets.only(bottom: 10), child: StudySearchEntry()),
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

              // BI26100538: when the library was last synced from the vault. Amber past 24 hours, so a
              // stalled sync is seen the same day.
              LibraryFreshness(syncedAt: fmt.m(data)['librarySyncedAt'] ?? fmt.m(data)['syncedAt']),

              // BI26100510: create, edit, archive and restore tracks.
              Center(
                child: TextButton(
                  key: const Key('manage-tracks'),
                  onPressed: () => showTrackAdmin(context, fmt.lm(fmt.m(data)['groups'])),
                  child: Text('Manage tracks', style: T.tiny.copyWith(color: C.text3)),
                ),
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

/// BI26100404: a module title is never a front-matter line. The server derives titles from the
/// front matter or the first heading; this guards a cached or older response that still carries
/// `---`, falling back to the humanised file name.
String safeModuleTitle(String title, String file) {
  final t = title.trim();
  if (t.isNotEmpty && !t.startsWith('---')) return t;
  final base = file
      .replaceAll(RegExp(r'\.md$', caseSensitive: false), '')
      .replaceFirst(RegExp(r'^\d{8}_'), '')
      .replaceFirst(RegExp(r'_v\d+_\d+_\d+$', caseSensitive: false), '')
      .replaceFirst(RegExp(r'^\d+[-_]'), '')
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .trim();
  if (base.isEmpty) return file;
  return base[0].toUpperCase() + base.substring(1);
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

/// A track colour as text on [background]: the colour itself when it reads (contrast of at least
/// 3:1), else a variant lightened 25% toward white (BI26100111).
Color legibleTrackColor(Color c, Color background) {
  double contrast(Color a, Color b) {
    final la = a.computeLuminance(), lb = b.computeLuminance();
    final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  return contrast(c, background) >= 3.0 ? c : Color.lerp(c, Colors.white, 0.25)!;
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
    this.coursesOwed = 0,
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
      coursesOwed: ((g['coursesOwed'] ?? g['courses_owed']) is num)
          ? ((g['coursesOwed'] ?? g['courses_owed']) as num).toInt()
          : 0,
    );
  }

  /// A real data problem, not a track: courses whose GROUP_ID doesn't match
  /// any live group. Visibly flagged (amber, distinct label).
  static const ungrouped = LearningGroup(
    id: '_ungrouped',
    label: 'Ungrouped: needs a GROUP_ID',
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

  /// BI26100538: courses the census says this track still owes, when spark reports it.
  final int coursesOwed;

  bool get isWide => tile == 'wide';
}

/// BI26100538: "Library updated 3 h ago", from the time the vault last synced to the VM. Amber once it
/// is more than 24 hours old. Nothing is shown when spark does not report a time.
class LibraryFreshness extends StatelessWidget {
  const LibraryFreshness({super.key, required this.syncedAt, this.now});
  final dynamic syncedAt;
  final DateTime? now;

  /// The age after which the line turns amber.
  static const stale = Duration(hours: 24);

  @override
  Widget build(BuildContext context) {
    final at = fmt.parseDate(syncedAt);
    if (at == null) return const SizedBox.shrink();
    final age = (now ?? DateTime.now()).difference(at);
    final isStale = age > stale;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Center(
        child: Text(
          'Library updated ${fmt.ago(syncedAt)}',
          key: const Key('library-freshness'),
          style: T.tiny.copyWith(color: isStale ? C.amber : C.text3),
        ),
      ),
    );
  }
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
                // BI26100538: a track with no courses is still shown, with an honest empty state.
                if (courses.isEmpty && group.courseCount == 0) ...[
                  const SizedBox(height: 10),
                  Text(
                    'No courses live yet',
                    key: const Key('track-empty'),
                    style: T.small.copyWith(color: C.text2, fontWeight: FontWeight.w600),
                  ),
                  if (group.coursesOwed > 0) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${group.coursesOwed} ${group.coursesOwed == 1 ? 'course' : 'courses'} on the way',
                      key: const Key('track-owed'),
                      style: T.tiny.copyWith(color: C.text3),
                    ),
                  ],
                ],
                Row(
                  children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          style: T.small.copyWith(color: C.text),
                          children: [
                            TextSpan(
                              text: '${group.courseCount} '
                                  '${group.courseCount == 1 ? 'course' : 'courses'} · '
                                  '${group.moduleCount} modules · ',
                            ),
                            TextSpan(
                              text: '${group.progressPct}%',
                              style: T.small.copyWith(
                                color: legibleTrackColor(group.color, bgTint),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
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
                          : (allOffline ? group.color : C.text3),
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

/// BI26100538: a books course is the first course of its track: its archetype is `books`, or its id
/// ends in `-books`.
bool isBooksCourse(Map<String, dynamic> c) {
  final id = fmt.s(c['ID']).isEmpty ? fmt.s(c['id']) : fmt.s(c['ID']);
  return fmt.s(c['archetype'] ?? c['ARCHETYPE']).toLowerCase() == 'books' || id.toLowerCase().endsWith('-books');
}

bool isArchivedCourse(Map<String, dynamic> c) => fmt.s(c['STATUS'] ?? c['status']).toLowerCase() == 'archived';

/// The course's place in its track: `coverage_order` when spark serves it, else `SEQ`.
int _coverageOrder(Map<String, dynamic> c) {
  final v = c['coverage_order'] ?? c['coverageOrder'] ?? c['COVERAGE_ORDER'];
  return v != null ? fmt.i(v) : _courseOrder(c);
}

/// Track order: the books course first, then coverage order, then title. Spark owns the order; this is
/// the same rule applied to what spark returned, so a response that lacks `coverage_order` still reads
/// right.
List<Map<String, dynamic>> orderedCourses(Iterable<Map<String, dynamic>> courses) {
  final out = List<Map<String, dynamic>>.from(courses);
  String title(Map<String, dynamic> c) => fmt.s(c['TITLE'] ?? c['title']).toLowerCase();
  out.sort((a, b) {
    final ba = isBooksCourse(a), bb = isBooksCourse(b);
    if (ba != bb) return ba ? -1 : 1;
    final byCoverage = _coverageOrder(a).compareTo(_coverageOrder(b));
    if (byCoverage != 0) return byCoverage;
    return title(a).compareTo(title(b));
  });
  return out;
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
    // BI26100538: live courses in track order (books first, then coverage order, then title); archived
    // ones are kept, listed under a collapsed heading at the bottom, never removed.
    final sortedCourses = orderedCourses(courses.where((c) => !isArchivedCourse(c)));
    final archivedCourses = orderedCourses(courses.where(isArchivedCourse));

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
            if (sortedCourses.isEmpty && archivedCourses.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: EmptyState('No courses live yet', 'This track has no courses published so far.',
                    icon: Icons.school_rounded),
              ),
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
            if (archivedCourses.isNotEmpty)
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  key: const Key('archived-section'),
                  tilePadding: EdgeInsets.zero,
                  title: Text('Archived (${archivedCourses.length})',
                      style: T.small.copyWith(color: C.text3, fontWeight: FontWeight.w600)),
                  children: [
                    for (var i = 0; i < archivedCourses.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: CourseSummaryCard(
                          course: archivedCourses[i],
                          index: i,
                          trackColor: effectiveColor,
                        ),
                      ),
                  ],
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
                    // BI26100538: a bold title over a smaller, lighter subtitle that wraps to two lines.
                    Text(title, key: const Key('course-title'), style: T.w600(T.title)),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(subtitle,
                          key: const Key('course-subtitle'),
                          maxLines: 2,
                          overflow: TextOverflow.fade,
                          style: T.small.copyWith(color: C.text3, fontSize: (T.small.fontSize ?? 13) - 1)),
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
                    color: allHere ? effectiveColor : (stale > 0 ? C.amber : C.text3)),
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
                        color: stale > 0 ? C.amber : (allHere ? effectiveColor : C.text3)),
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
          CourseControls(courseId: courseId, course: widget.course),
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
          // BI26100110: retired and superseded modules, out of the reading list, restorable from here.
          ModuleHistory(courseId: courseId, hidden: fmt.lm(widget.course['hiddenLessons'])),
        ],
      ),
    );
  }
}

/// BI26100137: the module number carries the status. Grey is new, the track colour is opened, amber is in
/// progress, green is done. One mapping, so every list of modules agrees.
Color moduleStatusColor(String status, Color trackColor) => switch (status.toLowerCase()) {
      'done' => C.green,
      'learning' => C.amber,
      'opened' => trackColor,
      _ => C.text3,
    };

/// BI26100538: the chip colour for a status, legible on the dark surface: the track colour for Opened
/// (lightened toward white when it is too dark to read), yellow for Learning, green for Done.
Color statusChipColor(String status, Color trackColor) => switch (status.toLowerCase()) {
      'done' => C.green,
      'learning' => C.amber,
      'opened' => legibleTrackColor(trackColor, C.bg),
      _ => C.text3,
    };

/// A small status chip for a module row: Opened, Learning or Done.
@visibleForTesting
class ModuleStatusChip extends StatelessWidget {
  const ModuleStatusChip({super.key, required this.status, required this.trackColor});
  final String status;
  final Color trackColor;

  @override
  Widget build(BuildContext context) {
    final c = statusChipColor(status, trackColor);
    final s = status.toLowerCase();
    final label = s == 'done' ? 'Done' : (s == 'learning' ? 'Learning' : 'Opened');
    return Container(
      key: const Key('status-chip'),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c),
      ),
      child: Text(label, style: T.tiny.copyWith(color: c, fontWeight: FontWeight.w600)),
    );
  }
}

String moduleStatusWords(String status) => switch (status.toLowerCase()) {
      'done' => 'done',
      'learning' => 'in progress',
      'opened' => 'opened',
      _ => 'not opened',
    };

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
    final title = safeModuleTitle(stripEmoji(rawTitle), file);

    final pos = lesson['position'] ?? lesson['SEQ'] ?? lesson['seq'] ?? lesson['order'];
    final numVal = pos != null ? fmt.i(pos) : index + 1;
    final numStr = numVal.toString().padLeft(2, '0');

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(Sz.rSm),
        // BI26100110: long-press opens the retire confirm sheet (it needs a module id, so a row without one ignores it).
        onLongPress: fmt.s(lesson['moduleId']).isEmpty ? null : () => showModuleLifecycleSheet(context, op: 'retire', courseId: courseId, lesson: lesson),
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
                child: Semantics(
                  label: 'Module $numStr, ${moduleStatusWords(status)}',
                  excludeSemantics: true,
                  child: Text(
                    numStr,
                    key: const Key('module-number'),
                    style: T.small.copyWith(
                      color: moduleStatusColor(status, trackColor),
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // BI26100538 (Sconl, 6 Oct): the module list shows only the bold three-word title.
                    Text(
                      title,
                      key: const Key('module-title'),
                      style: T.w600(T.body2).copyWith(
                        color: status == 'done' ? C.text3 : C.text,
                      ),
                    ),
                    // BI26100325: how far through an unfinished module.
                    if (status != 'done' && status != 'new')
                      ReadingBar(course: courseId, file: file, color: trackColor),
                    // BI26100110: a lifecycle badge for anything but a live module (superseded, draft, missing).
                    LifecycleBadges(lesson),
                  ],
                ),
              ),
              if (st.state == ModuleState.stale)
                const Tooltip(
                  message: 'Updated on the agent - opens the new version',
                  child: Icon(Icons.sync_problem_rounded, size: 12, color: C.amber),
                ),
              // BI26100538: the status chip. Opened is the track colour, Learning is yellow, Done is green.
              if (status == 'opened' || status == 'learning' || status == 'done')
                Padding(
                  padding: const EdgeInsets.only(left: 6, top: 1),
                  child: ModuleStatusChip(status: status, trackColor: trackColor),
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

/// BI26100325: a thin progress bar under an unfinished module, from the saved
/// reading position. Hidden until there is one, and when no database is in scope.
@visibleForTesting
class ReadingBar extends StatelessWidget {
  const ReadingBar({super.key, required this.course, required this.file, required this.color});
  final String course;
  final String file;
  final Color color;

  @override
  Widget build(BuildContext context) {
    AppDb db;
    try {
      db = AppScope.of(context).db;
    } catch (_) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<double?>(
      future: db.lessonResumeFractionLocal(course: course, file: file),
      builder: (context, snap) {
        final f = snap.data;
        if (f == null || f < 0.02) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 6, right: 10),
          child: ClipRRect(
            key: const Key('reading-bar'),
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: f.clamp(0.0, 1.0),
              minHeight: 3,
              backgroundColor: C.surface,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        );
      },
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
    this.initialParagraph,
    this.foundText,
    this.initialAnchor = '',
  });

  /// BI26100537: open at this section anchor (`grasp-1`, `week-7-2`), from a `module:` deep link.
  final String initialAnchor;

  /// BI26100156: open at this paragraph (as the reader counts them), from a search result.
  final int? initialParagraph;

  /// The matched paragraph's text, shown briefly so the jump is visible.
  final String? foundText;

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

  /// BI26100325: block anchors for the module body, so "where I stopped" is a
  /// block, not a pixel offset.
  final _anchors = MarkdownAnchors();
  bool _showScrollTop = false;

  /// BI26100141: focus mode hides the bar and buttons while scrolling down.
  bool _barVisible = true;

  /// BI26100156: the matched text is shown for a few seconds after a search jump.
  bool _showFound = false;
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
    ReaderPrefs.instance.addListener(_onPrefs);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ReaderPrefs.instance.ensureLoaded(AppScope.of(context).db);
    });
  }

  void _onPrefs() {
    if (!mounted) return;
    setState(() {
      if (!ReaderPrefs.instance.focus) _barVisible = true;
    });
  }

  /// Scrolling down hides the bar and buttons; scrolling up, or the top of the page, brings them back.
  void _updateBarVisibility() {
    if (!_scroll.hasClients || !ReaderPrefs.instance.focus) return;
    final dir = _scroll.position.userScrollDirection;
    var visible = _barVisible;
    if (_scroll.offset < 24 || dir == ScrollDirection.forward) {
      visible = true;
    } else if (dir == ScrollDirection.reverse) {
      visible = false;
    }
    if (visible != _barVisible) setState(() => _barVisible = visible);
  }

  // BI26092613: local, always-on scroll-position tracking -- written
  // to local db and queued in outbox in the same call, debounced to 2 s
  // while scrolling and on leaving the screen, as a fraction 0 to 1.
  void _onScroll() {
    _updateBarVisibility();
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
    // BI26100325: by block as well, so a font-size change lands on the same block.
    ReadingAnchor? anchor;
    if (_anchors.count > 0) {
      final block = _anchors.topVisible(_scroll);
      anchor = ReadingAnchor(
        block: block,
        movement: _anchors.movementOf(block),
        blocksTotal: _anchors.count,
        wordsLeft: _anchors.wordsFrom(block),
        title: widget.title.isEmpty ? widget.file : widget.title,
      );
    }
    services.db.saveLessonResumeLocal(
      course: widget.course,
      file: widget.file,
      scrollPct: pct,
      fraction: fraction,
      anchor: anchor,
    );
    services.mutations.saveLessonResume(
      course: widget.course,
      lesson: widget.file,
      scrollPct: pct,
      fraction: fraction,
      block: anchor?.block,
      movement: anchor?.movement,
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
      // BI26100537: a deep link to a section wins over everything else.
      if (widget.initialAnchor.isNotEmpty && _anchors.revealAnchor(widget.initialAnchor)) return;
      final jump = widget.initialParagraph;
      if (jump != null) {
        // A search result wins over the saved reading position.
        final total = _currentContent == null
            ? 0
            : _currentContent!.split(RegExp(r'\n\s*\n')).where((p) => p.trim().isNotEmpty).length;
        if (total > 0) {
          final target = _scroll.position.maxScrollExtent * (jump / total);
          _scroll.jumpTo(target.clamp(0, _scroll.position.maxScrollExtent));
          setState(() => _showFound = true);
          Future.delayed(const Duration(seconds: 4), () {
            if (mounted) setState(() => _showFound = false);
          });
        }
        return;
      }
      final db = AppScope.of(context).db;
      // BI26100325: the saved block wins; if it no longer exists, the start of
      // its movement; only then the old scroll fraction.
      final anchor = await db.lessonAnchorLocal(course: widget.course, file: widget.file);
      if (!mounted || !_scroll.hasClients) return;
      if (anchor != null && _anchors.count > 0) {
        var i = anchor.block;
        if (i < 0 || i >= _anchors.count) {
          i = _anchors.firstBlockOf(anchor.movement) ?? -1;
        }
        if (i >= 0) {
          if (i > 0 && _anchors.reveal(i)) return;
          if (i == 0) return;
        }
      }
      final frac = await db.lessonResumeFractionLocal(
            course: widget.course,
            file: widget.file,
          );
      if (frac == null || !mounted || !_scroll.hasClients) return;
      final target = _scroll.position.maxScrollExtent * frac;
      if (target > 0) _scroll.jumpTo(target.clamp(0, _scroll.position.maxScrollExtent));
    });
  }

  /// Replace this screen with another module of the same course.
  void _openLesson(Map<String, dynamic> lesson) => Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => LessonScreen(
            course: widget.course,
            file: fmt.s(lesson['file']),
            title: fmt.s(lesson['title']),
            status: fmt.s(lesson['status']),
            allLessons: widget.allLessons,
            trackColor: widget.trackColor,
          ),
        ),
      );

  /// BI26100537: a `module:<course>/<NN>#anchor` link. Same module: scroll to the section. Another
  /// module of this course: open exactly that module at that section, never the course index.
  void _openModuleLink(ModuleLink link) {
    final index = link.index;
    bool matches(Map<String, dynamic> l) {
      final f = fmt.s(l['file']);
      return f.startsWith(index) && (f.length == index.length || !RegExp(r'\d').hasMatch(f[index.length]));
    }

    if (link.course != widget.course) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
          content: Text('That module is in another course. Open the course, then the module.')));
      return;
    }
    if (matches({'file': widget.file})) {
      if (link.anchor.isNotEmpty) _anchors.revealAnchor(link.anchor);
      return;
    }
    final target = widget.allLessons.where(matches).toList();
    if (target.isEmpty) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => LessonScreen(
          course: widget.course,
          file: fmt.s(target.first['file']),
          title: fmt.s(target.first['title']),
          status: fmt.s(target.first['status']),
          allLessons: widget.allLessons,
          trackColor: widget.trackColor,
          initialAnchor: link.anchor,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _resumeDebounce?.cancel();
    _undoTimer?.cancel();
    _saveResumeNow();
    _scroll.removeListener(_onScroll);
    ReaderPrefs.instance.removeListener(_onPrefs);
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
          SpacedReview.instance.withdraw(widget.course, widget.file, db: services.db);
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

    // BI26100537 (standard 4.0.0, §3.11): Mark as done is the app's success green, a theme token,
    // whatever the track colour is.
    final isDarkTrack = C.green.computeLuminance() < 0.5;
    return FilledButton(
      key: const Key('mark-as-done'),
      style: FilledButton.styleFrom(
        backgroundColor: C.green,
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
        // BI26100145: a finished module enters the 1, 7 and 30 day review schedule.
        SpacedReview.instance.enrol(
            course: widget.course,
            file: widget.file,
            title: widget.title.isEmpty ? widget.file : widget.title,
            now: DateTime.now(),
            db: services.db);
      },
      child: const Text('Mark as done'),
    );
  }

  Widget _lessonOfflineNote() => Padding(
        padding: const EdgeInsets.only(top: 26),
        child: Text(
          'Lesson content loads when online, then stays cached '
          'on this device for reading offline.',
          style: T.body2.copyWith(color: C.text3, height: 1.6),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final snap = services.store.detail(
      'lesson',
      '${widget.course}/${widget.file}',
      '/api/learning/lesson?course=${Uri.encodeComponent(widget.course)}&file=${Uri.encodeComponent(widget.file)}',
    );
    final heading = widget.title.isEmpty ? widget.file : widget.title;
    final prefs = ReaderPrefs.instance;
    final mq = MediaQuery.of(context);
    final textScale = prefs.effectiveScale(mq.textScaler.scale(1.0));
    final barShown = !prefs.focus || _barVisible;
    // With focus mode on, the body runs behind the bar so hiding it never shifts the text.
    final topPad = prefs.focus ? mq.padding.top + kToolbarHeight : 0.0;

    return Scaffold(
      extendBodyBehindAppBar: prefs.focus,
      // BI26100405: scroll-to-top is the one primary FAB; notes is a secondary above it.
      floatingActionButton: IgnorePointer(
        ignoring: !barShown,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 180),
          offset: Offset(0, barShown ? 0 : 2),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            opacity: barShown ? 1 : 0,
            // One primary, bottom-right: scroll to top (it appears once you have scrolled a screen).
            // Notes is secondary: small and grey, above it. Same pattern as the holdings view.
            child: FabStack(
              primary: _showScrollTop
                  ? FabAction(
                      heroTag: 'fab_lesson_scroll_top',
                      tooltip: 'Scroll to top',
                      icon: Icons.keyboard_arrow_up_rounded,
                      onPressed: () {
                        if (_scroll.hasClients) {
                          _scroll.animateTo(
                            0,
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.easeOutCubic,
                          );
                        }
                      },
                    )
                  : null,
              secondary: [
                FabAction(
                  heroTag: 'fab_lesson_notes',
                  tooltip: 'Notes',
                  icon: Icons.edit_note_rounded,
                  onPressed: () => _openNotesSheet(context),
                ),
              ],
            ),
          ),
        ),
      ),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 180),
          offset: Offset(0, barShown ? 0 : -1.2),
          child: ShellAppBar(
            title: heading,
            showBrand: false,
            actions: [
              IconButton(
                key: const Key('reader-aa'),
                tooltip: 'Text size and spacing',
                icon: Text('Aa', style: T.w600(T.body2).copyWith(color: C.text)),
                onPressed: () => showReaderComfortSheet(context),
              ),
              _ExportPdfButton(course: widget.course, file: widget.file),
            ],
          ),
        ),
      ),
      body: MediaQuery(
        data: mq.copyWith(textScaler: TextScaler.linear(textScale)),
        child: Stack(children: [
      Column(
        children: [
          ReadingProgress(controller: _scroll),
          Expanded(
            child: SnapshotView(
              snapshot: snap,
              controller: _scroll,
              // The reading surface owns its own margins, so the scroll view
              // contributes nothing horizontally. Bottom room is for the
              // thumb, not for a nav bar - this screen is pushed, not tabbed.
              padding: EdgeInsets.fromLTRB(0, topPad, 0, 56),
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
                final docId = fmt.s(lessonMap['docId'] ?? lessonMap['doc_id']);
                final docVersion = fmt.s(lessonMap['docVersion'] ?? lessonMap['doc_version']);
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
                              // BI26100538: Opened in the track colour, Learning yellow, Done green.
                              stateColor: statusChipColor(st, widget.trackColor),
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
                    // BI26101394: a document-served module with no markdown still gets a Listen bar.
                    if (content.isEmpty && docId.isNotEmpty && docVersion.isNotEmpty)
                      CdmListenBar(docId: docId, version: docVersion, course: widget.course, file: widget.file),
                    if (docId.isNotEmpty && docVersion.isNotEmpty)
                      // BI26092620: a module served as a deck document is drawn natively
                      // from the version-keyed cache; the markdown reader is its fallback.
                      CdmLessonBody(
                        docId: docId,
                        version: docVersion,
                        courseId: widget.course,
                        fallback: content.isEmpty
                            ? _lessonOfflineNote()
                            : ReadingBody(content,
                                anchors: _anchors,
                                onModuleLink: _openModuleLink,
                                courseId: widget.course,
                                baseUrl: services.api.baseUrl,
                                token: services.api.token),
                      )
                    else if (content.isEmpty)
                      _lessonOfflineNote()
                    else
                      ReadingBody(content,
                          anchors: _anchors,
                          onModuleLink: _openModuleLink,
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
                    // BI26100537 (standard 4.0.0, section 3.11): Previous Module and Next Module side by
                    // side, equal width, fixed labels. At either end the button is disabled, not removed.
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 20),
                      child: Row(
                        key: const Key('module-nav'),
                        children: [
                          Expanded(
                            child: _LessonNavButton(
                              key: const Key('previous-module'),
                              icon: Icons.chevron_left_rounded,
                              iconTrailing: false,
                              label: 'Previous Module',
                              onTap: _computedPrevLesson == null
                                  ? null
                                  : () => _openLesson(_computedPrevLesson!),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _LessonNavButton(
                              key: const Key('next-module'),
                              icon: Icons.chevron_right_rounded,
                              iconTrailing: true,
                              label: 'Next Module',
                              onTap: _computedNextLesson == null
                                  ? null
                                  : () => _openLesson(_computedNextLesson!),
                            ),
                          ),
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
          if (_showFound && widget.foundText != null)
            Positioned(
              top: topPad,
              left: 12,
              right: 12,
              child: Material(
                key: const Key('found-banner'),
                color: C.greenBg,
                borderRadius: BorderRadius.circular(Sz.rMd),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(widget.foundText!, maxLines: 3, overflow: TextOverflow.ellipsis, style: T.small.copyWith(color: C.text)),
                ),
              ),
            ),
          if (!barShown)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: mq.padding.top + 28,
              child: GestureDetector(
                key: const Key('reader-top-edge'),
                behavior: HitTestBehavior.translucent,
                onTap: () => setState(() => _barVisible = true),
              ),
            ),
        ]),
      ),
    );
  }
}

/// BI26100141: text size, line spacing and focus mode. Changes apply live and are remembered.
Future<void> showReaderComfortSheet(BuildContext context) {
  final db = AppScope.of(context).db;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: C.panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Sz.rXl)),
      side: BorderSide(color: C.border),
    ),
    builder: (ctx) => SafeArea(
      child: ListenableBuilder(
        listenable: ReaderPrefs.instance,
        builder: (ctx, _) {
          final p = ReaderPrefs.instance;
          return Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('TEXT SIZE', style: T.label),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (var i = 0; i < ReaderPrefs.sizeLabels.length; i++)
                      ChoiceChip(
                        key: Key('size-${ReaderPrefs.sizeLabels[i]}'),
                        label: Text(ReaderPrefs.sizeLabels[i]),
                        selected: p.sizeStep == i,
                        onSelected: (_) => p.update(size: i, db: db),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Text('LINE SPACING', style: T.label),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      key: const Key('spacing-normal'),
                      label: const Text('Normal'),
                      selected: !p.relaxed,
                      onSelected: (_) => p.update(relaxed: false, db: db),
                    ),
                    ChoiceChip(
                      key: const Key('spacing-relaxed'),
                      label: const Text('Relaxed'),
                      selected: p.relaxed,
                      onSelected: (_) => p.update(relaxed: true, db: db),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SwitchListTile(
                  key: const Key('focus-switch'),
                  contentPadding: EdgeInsets.zero,
                  title: Text('Focus mode', style: T.body2),
                  subtitle: Text(
                    'Hide the bar and buttons while you scroll down',
                    style: T.tiny,
                  ),
                  value: p.focus,
                  onChanged: (v) => p.update(focus: v, db: db),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
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
    super.key,
    required this.icon,
    required this.iconTrailing,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final bool iconTrailing;
  final String label;

  /// Null disables the button (the first or last module of a course) without changing its label.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final iconWidget = Icon(icon, size: 18, color: C.green);
    // Flexible, so two equal-width buttons survive a large text size without overflowing.
    final labelWidget = Flexible(
      child: Text(label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: T.small.copyWith(color: C.green, fontWeight: FontWeight.w600)),
    );
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

