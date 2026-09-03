import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../data/modules.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../shell.dart' show ShellAppBar;
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

          // Group courses by CLASSROOM track (matching the web UI organization)
          final Map<String, List<Map<String, dynamic>>> byTrack = {};
          for (final c in courses) {
            final track = fmt.s(c['CLASSROOM']).isEmpty
                ? 'Other'
                : fmt.s(c['CLASSROOM']);
            byTrack.putIfAbsent(track, () => []).add(c);
          }
          // Preserve the natural order tracks appear in the data
          final tracks = byTrack.keys.toList();

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

              // ── landing: one card per track, not a flat course/module list ──
              for (final track in tracks)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _TrackCard(
                    track: track,
                    courses: byTrack[track]!,
                    accent: _trackAccent(tracks.indexOf(track)),
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

/// Cycles the four callout accents across tracks so each has a stable colour
/// without hardcoding to specific track names - new tracks just fall in line.
Color _trackAccent(int index) =>
    const [C.green, C.cyan, C.violet, C.amber][index % 4];

/// Per-track aggregate: courses started, module progress, offline coverage.
class _TrackStats {
  _TrackStats(List<Map<String, dynamic>> courses, ModuleLibrary lib) {
    courseCount = courses.length;
    for (final c in courses) {
      final lessons = fmt.lm(c['lessons']);
      final done =
          lessons.where((l) => fmt.s(l['status']).toLowerCase() == 'done').length;
      if (done > 0) coursesStarted++;
      totalModules += lessons.length;
      doneModules += done;
      final courseId = fmt.s(c['ID']).isEmpty ? fmt.s(c['id']) : fmt.s(c['ID']);
      for (final l in lessons) {
        final file = fmt.s(l['file']);
        if (file.isEmpty) continue;
        final st = lib.status(courseId, file);
        if (st.downloaded) offlineModules++;
        if (st.state == ModuleState.stale) staleModules++;
      }
    }
  }

  int courseCount = 0;
  int coursesStarted = 0;
  int totalModules = 0;
  int doneModules = 0;
  int offlineModules = 0;
  int staleModules = 0;
}

/// Track landing card - name, aggregate progress, offline coverage. No course
/// or module detail here; that is the entire fix for the old flat list's
/// overwhelm. Tap to drill into the track's course list.
class _TrackCard extends StatelessWidget {
  const _TrackCard({
    required this.track,
    required this.courses,
    required this.accent,
  });

  final String track;
  final List<Map<String, dynamic>> courses;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final lib = AppScope.of(context).modules;
    final stats = _TrackStats(courses, lib);
    final pct = stats.totalModules == 0
        ? 0.0
        : stats.doneModules / stats.totalModules;
    final allOffline = stats.totalModules > 0 &&
        stats.offlineModules == stats.totalModules &&
        stats.staleModules == 0;

    return Panel(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _TrackDetailScreen(track: track, courses: courses),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(track, style: T.title)),
              const Icon(Icons.chevron_right_rounded, size: 18, color: C.text3),
            ],
          ),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 4,
              backgroundColor: C.surface,
              valueColor: AlwaysStoppedAnimation(accent),
            ),
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${stats.coursesStarted} of ${stats.courseCount} '
                  '${stats.courseCount == 1 ? 'course' : 'courses'} started · '
                  '${stats.doneModules}/${stats.totalModules} modules',
                  style: T.small,
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
                      : (allOffline ? C.green : C.text3)),
              const SizedBox(width: 6),
              Text(
                stats.staleModules > 0
                    ? '${stats.offlineModules}/${stats.totalModules} on device · ${stats.staleModules} updated'
                    : allOffline
                        ? 'All on this device'
                        : '${stats.offlineModules}/${stats.totalModules} on this device',
                style: T.tiny.copyWith(
                    color: stats.staleModules > 0 ? C.amber : C.text3),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Track detail: the course list for one track only, each course collapsed
/// to a compact summary card. Tap a course to see its full module list.
class _TrackDetailScreen extends StatelessWidget {
  const _TrackDetailScreen({required this.track, required this.courses});
  final String track;
  final List<Map<String, dynamic>> courses;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ShellAppBar(title: track, showBrand: false),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(Sz.pad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final course in courses)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _CourseSummaryCard(course: course),
              ),
          ],
        ),
      ),
    );
  }
}

/// Compact course card for the track-detail list: title, progress, module
/// count. Full lesson list lives one tap deeper, in [_CourseDetailScreen].
class _CourseSummaryCard extends StatelessWidget {
  const _CourseSummaryCard({required this.course});
  final Map<String, dynamic> course;

  @override
  Widget build(BuildContext context) {
    final lessons = fmt.lm(course['lessons']);
    final done =
        lessons.where((l) => fmt.s(l['status']).toLowerCase() == 'done').length;
    final pct = lessons.isEmpty ? 0.0 : done / lessons.length;
    final title = fmt.s(course['TITLE']).isEmpty
        ? (fmt.s(course['ID']).isEmpty ? fmt.s(course['id']) : fmt.s(course['ID']))
        : fmt.s(course['TITLE']);

    return Panel(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _CourseDetailScreen(course: course, title: title),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: T.w600(T.body2)),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(value: pct, minHeight: 4),
                ),
                const SizedBox(height: 6),
                Text('$done/${lessons.length} modules',
                    style: T.tiny.copyWith(color: C.text3)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right_rounded, size: 18, color: C.text3),
        ],
      ),
    );
  }
}

/// Course detail: the existing [_CourseTile]'s full expanded content
/// (module list, take-offline, per-lesson rows), reused as-is rather than
/// rebuilt, pushed as its own screen instead of always-expanded inline.
class _CourseDetailScreen extends StatelessWidget {
  const _CourseDetailScreen({required this.course, required this.title});
  final Map<String, dynamic> course;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ShellAppBar(title: title, showBrand: false),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(Sz.pad),
        child: _CourseTile(course: course),
      ),
    );
  }
}

class _CourseTile extends StatefulWidget {
  const _CourseTile({required this.course});
  final Map<String, dynamic> course;

  @override
  State<_CourseTile> createState() => _CourseTileState();
}

class _CourseTileState extends State<_CourseTile> {
  bool _pulling = false;
  int _pulled = 0;
  int _total = 0;

  Future<void> _takeOffline(String courseId, List<String> files) async {
    setState(() { _pulling = true; _pulled = 0; _total = files.length; });
    final lib = AppScope.of(context).modules;
    await lib.downloadCourse(courseId, files, onProgress: (d, t) {
      if (mounted) setState(() { _pulled = d; _total = t; });
    });
    if (!mounted) return;
    setState(() => _pulling = false);
    toast(context, '$courseId is on this device');
  }

  @override
  Widget build(BuildContext context) {
    final lib = AppScope.of(context).modules;
    final lessons = fmt.lm(widget.course['lessons']);
    final done = lessons
        .where((l) => fmt.s(l['status']).toLowerCase() == 'done')
        .length;
    final pct = lessons.isEmpty ? 0.0 : done / lessons.length;
    final courseId = fmt.s(widget.course['ID']).isEmpty
        ? fmt.s(widget.course['id'])
        : fmt.s(widget.course['ID']);

    final files = lessons.map((l) => fmt.s(l['file'])).where((f) => f.isNotEmpty).toList();
    final offline = files
        .where((f) => lib.status(courseId, f).downloaded)
        .length;
    final stale = files
        .where((f) => lib.status(courseId, f).state == ModuleState.stale)
        .length;
    final allHere = files.isNotEmpty && offline == files.length && stale == 0;

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
                  style: T.mono.copyWith(color: C.greenBright)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(value: pct, minHeight: 4),
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
            _LessonRow(
              courseId: courseId,
              lesson: lessons[i],
              nextLesson: i + 1 < lessons.length ? lessons[i + 1] : null,
              allLessons: lessons,
            ),
        ],
      ),
    );
  }
}

class _LessonRow extends StatelessWidget {
  const _LessonRow({
    required this.courseId,
    required this.lesson,
    this.nextLesson,
    this.allLessons = const [],
  });
  final String courseId;
  final Map<String, dynamic> lesson;
  final Map<String, dynamic>? nextLesson;
  final List<Map<String, dynamic>> allLessons;

  @override
  Widget build(BuildContext context) {
    final lib = AppScope.of(context).modules;
    final file = fmt.s(lesson['file']);
    final status = fmt.s(lesson['status']).toLowerCase();
    final st = lib.status(courseId, file);

    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LessonScreen(
            course: courseId,
            file: file,
            title: fmt.s(lesson['title']),
            status: fmt.s(lesson['status']),
            nextLesson: nextLesson,
            allLessons: allLessons,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(
              switch (status) {
                'done' => Icons.check_circle_rounded,
                'learning' => Icons.play_circle_outline_rounded,
                _ => Icons.circle_outlined,
              },
              size: 15,
              color: switch (status) {
                'done' => C.green,
                'learning' => C.amber,
                _ => C.text3,
              },
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                fmt.s(lesson['title']).isEmpty ? file : fmt.s(lesson['title']),
                style: T.small.copyWith(
                  color: status == 'done' ? C.text3 : C.text2,
                ),
              ),
            ),
            // Offline state, as a 10px dot rather than a word. It is reference
            // information you scan a column of, not something to read.
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
            const Icon(Icons.chevron_right_rounded, size: 15, color: C.text3),
          ],
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
  });

  final String course;
  final String file;
  final String title;
  final String status;
  final Map<String, dynamic>? nextLesson;
  final List<Map<String, dynamic>> allLessons;

  @override
  State<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends State<LessonScreen> {
  late String _status = widget.status;
  final _scroll = ScrollController();
  Timer? _resumeDebounce;
  bool _restoredResume = false;
  bool _showScrollTop = false;

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
      if (st.state == ModuleState.absent) return;   // SnapshotView fetches it
      if (st.state == ModuleState.stale) {
        await lib.download(widget.course, widget.file);
      }
    });
    _scroll.addListener(_onScroll);
  }

  // BN26083103: local, always-on scroll-position tracking -- written
  // unconditionally (online or offline, since it's on-device), debounced
  // 1.2s of stillness, matching the web console's own resume-tracker
  // (app.js, "The reader's scroll is written back on a debounce (1.2s of
  // stillness)"). The best-effort server sync (saveLessonResume(), already
  // written elsewhere, queueable:false) fires on the same tick, but only
  // when online -- the local row is now the durable source of truth, so a
  // dropped server write is no longer a real data-loss risk.
  void _onScroll() {
    if (!_scroll.hasClients || _scroll.position.maxScrollExtent <= 0) return;
    final show = _scroll.offset > (MediaQuery.of(context).size.height * 0.6);
    if (show != _showScrollTop) {
      setState(() => _showScrollTop = show);
    }
    // First layout after a restore-triggered jump also fires this listener
    // -- don't let that overwrite the just-restored position with itself;
    // harmless either way, but skip it while a restore is still pending.
    _resumeDebounce?.cancel();
    _resumeDebounce = Timer(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      final pct = (_scroll.position.pixels / _scroll.position.maxScrollExtent * 100)
          .clamp(0, 100)
          .round();
      final services = AppScope.of(context);
      services.db.saveLessonResumeLocal(
        course: widget.course,
        file: widget.file,
        scrollPct: pct,
      );
      if (services.sync.online) {
        services.mutations.saveLessonResume(
          course: widget.course,
          lesson: widget.file,
          scrollPct: pct,
        );
      }
    });
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
      final pct = await AppScope.of(context).db.lessonResumeLocal(
            course: widget.course,
            file: widget.file,
          );
      if (pct == null || !mounted || !_scroll.hasClients) return;
      final target = _scroll.position.maxScrollExtent * (pct / 100);
      if (target > 0) _scroll.jumpTo(target.clamp(0, _scroll.position.maxScrollExtent));
    });
  }

  @override
  void dispose() {
    _resumeDebounce?.cancel();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
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
      floatingActionButton: _showScrollTop
          ? FloatingActionButton.small(
              backgroundColor: C.surface,
              foregroundColor: C.text,
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Sz.rSm),
                side: const BorderSide(color: C.border),
              ),
              onPressed: () => _scroll.jumpTo(0),
              tooltip: 'Scroll to top',
              child: const Icon(Icons.arrow_upward_rounded, size: 18),
            )
          : null,
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
                final content = fmt.s(fmt.m(data)['content']);
                _maybeRestoreResume();
                return ReadingSurface(
                  children: [
                    ReadingHeader(
                      title: heading,
                      kicker: widget.course,
                      meta: content.isEmpty ? null : readingMeta(content),
                      trailing: Row(
                        children: [
                          for (final st in ['new', 'learning', 'done']) ...[
                            Pill(st,
                                selected: _status.toLowerCase() == st,
                                onTap: () async {
                                  setState(() => _status = st);
                                  final res = await services.mutations
                                      .lessonProgress(
                                          widget.course, widget.file, st);
                                  if (!context.mounted) return;
                                  if (!res.ok) {
                                    toast(context, res.error!, error: true);
                                  } else if (res.queued) {
                                    toast(context,
                                        'Progress queued - will sync');
                                  }
                                }),
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
                          baseUrl: services.api.baseUrl),
                    _LessonNotes(course: widget.course, file: widget.file),
                    if (_computedNextLesson != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 24, bottom: 20),
                        child: Center(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              shape: const StadiumBorder(),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 12),
                              side: const BorderSide(color: C.greenDim),
                            ),
                            onPressed: () => Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (_) => LessonScreen(
                                  course: widget.course,
                                  file: fmt.s(_computedNextLesson!['file']),
                                  title: fmt.s(_computedNextLesson!['title']),
                                  status: fmt.s(_computedNextLesson!['status']),
                                  allLessons: widget.allLessons,
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.arrow_forward_rounded,
                                size: 16, color: C.green),
                            label: Text(
                              'Next: ${fmt.s(_computedNextLesson!['title']).isEmpty ? fmt.s(_computedNextLesson!['file']) : fmt.s(_computedNextLesson!['title'])}',
                              style: T.small.copyWith(
                                  color: C.green, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      )
                    else if (widget.allLessons.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 24, bottom: 20),
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.check_circle_rounded,
                                  size: 16, color: C.green),
                              const SizedBox(width: 8),
                              Text('Course complete',
                                  style: T.small.copyWith(color: C.text3)),
                            ],
                          ),
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

class _LessonNotes extends StatefulWidget {
  const _LessonNotes({required this.course, required this.file});
  final String course;
  final String file;

  @override
  State<_LessonNotes> createState() => _LessonNotesState();
}

class _LessonNotesState extends State<_LessonNotes> {
  final _controller = TextEditingController();
  bool _open = false;
  bool _loading = false;
  bool _loaded = false;
  bool _saving = false;
  String? _error;

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
      final res = await AppScope.of(context).api.getJson(
            '/api/learning/notes?course=${Uri.encodeQueryComponent(widget.course)}'
            '&file=${Uri.encodeQueryComponent(widget.file)}',
          );
      if (!mounted) return;
      _controller.text = fmt.s(fmt.m(res)['text']);
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
    final res = await AppScope.of(context).mutations.saveLessonNote(
          course: widget.course,
          file: widget.file,
          text: _controller.text,
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
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null)
                  ErrorRetry(_error!, onRetry: () {
                    _loaded = false;
                    _load();
                  }),
                // Borderless while resting, so the note field reads as more
                // page rather than as a widget dropped onto one. The green
                // underline on focus is the only state it needs.
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
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const MiniSpinner()
                        : const Icon(Icons.save_rounded, size: 16),
                    label: const Text('Save note'),
                  ),
                ),
              ],
            ),
    );
  }
}
