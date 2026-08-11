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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppScope.of(context).modules.check();
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
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (lib.prefetching)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10, left: 2),
                  child: Row(
                    children: [
                      const MiniSpinner(),
                      const SizedBox(width: 8),
                      Text(
                        'Taking the library offline · ${lib.prefetchDone} of ${lib.prefetchTotal}',
                        style: T.tiny.copyWith(color: C.text2),
                      ),
                    ],
                  ),
                )
              else if (lib.downloadedCount > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10, left: 2),
                  child: Row(
                    children: [
                      Icon(
                          lib.staleCount > 0
                              ? Icons.sync_problem_rounded
                              : Icons.offline_pin_rounded,
                          size: 13,
                          color: lib.staleCount > 0 ? C.amber : C.green),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          lib.staleCount > 0
                              ? '${lib.downloadedCount} modules on this device · ${lib.staleCount} updated on the agent'
                              : lib.knownCount > 0 &&
                                      lib.downloadedCount >= lib.knownCount
                                  ? 'The whole library is on this device, ${lib.downloadedCount} modules, readable anywhere'
                                  : '${lib.downloadedCount} of ${lib.knownCount} modules on this device',
                          style: T.tiny.copyWith(
                              color: lib.staleCount > 0 ? C.amber : C.text3),
                        ),
                      ),
                    ],
                  ),
                ),
              for (final course in courses)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _CourseTile(course: course),
                ),
            ],
          );
        },
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
          for (final lesson in lessons)
            _LessonRow(courseId: courseId, lesson: lesson),
        ],
      ),
    );
  }
}

class _LessonRow extends StatelessWidget {
  const _LessonRow({required this.courseId, required this.lesson});
  final String courseId;
  final Map<String, dynamic> lesson;

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
  });

  final String course;
  final String file;
  final String title;
  final String status;

  @override
  State<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends State<LessonScreen> {
  late String _status = widget.status;
  final _scroll = ScrollController();

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
  }

  @override
  void dispose() {
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
                      ReadingBody(content),
                    _LessonNotes(course: widget.course, file: widget.file),
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
          : const Icon(Icons.picture_as_pdf_outlined, size: 20),
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
