import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../services/course_standard.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../shell.dart' show SecondaryScreen;
import '../widgets/common.dart';
import 'learning.dart' show LessonScreen;

/// Opens the course standards page as its own screen.
void openCourseStandards(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => const SecondaryScreen(title: 'Course standards', child: CourseStandardsView()),
  ));
}

/// BI26112307: every archetype of the live course standard, each with when it is used, what it changes and one
/// live module written to it. Read from hub (`GET /api/learning/standard`, the standard's own §11), never copied
/// into the app, and kept on the phone so the page opens offline.
class CourseStandardsView extends StatefulWidget {
  const CourseStandardsView({super.key, this.refreshOnOpen = true});

  /// Tests turn this off so the page starts no network work of its own.
  final bool refreshOnOpen;

  @override
  State<CourseStandardsView> createState() => _CourseStandardsViewState();
}

class _CourseStandardsViewState extends State<CourseStandardsView> {
  final _standard = CourseStandard.instance;
  bool _loading = false;
  String? _problem;

  @override
  void initState() {
    super.initState();
    if (widget.refreshOnOpen) WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    final services = AppScope.maybeOf(context);
    if (services == null) return;
    setState(() => _loading = true);
    await _standard.ensureLoaded(services.api, services.db);
    final problem = await _standard.refresh(services.api, services.db);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _problem = problem;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _standard,
      builder: (context, _) {
        final list = _standard.archetypes;
        if (list.isEmpty) {
          if (_loading) return const Center(child: CircularProgressIndicator());
          return EmptyState(
            'No archetypes yet',
            _problem ?? 'The course standard has not been read from the server yet. Connect once and open this page again.',
            icon: Icons.menu_book_rounded,
          );
        }
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Text(
                'Every module is written to one archetype. It changes which parts of the module carry the weight, '
                'never the shape. Tap one to see an example.',
                style: T.small.copyWith(color: C.text2),
              ),
              if (_standard.current != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Standard ${_standard.current}', key: const Key('standards-version'), style: T.statusMono),
                ),
              if (_problem != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(_problem!, style: T.tiny.copyWith(color: C.text3)),
                ),
              const SectionLabel('Archetypes'),
              for (final a in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Panel(
                    key: Key('archetype-${a.name}'),
                    onTap: () => _openArchetype(context, a),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(a.name, style: T.w600(T.body)),
                        if (a.usedFor.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(a.usedFor, style: T.small.copyWith(color: C.text2)),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _openArchetype(BuildContext context, StandardArchetype a) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.panel,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(a.name, style: T.title),
                const SectionLabel('When it is used'),
                Text(a.usedFor.isEmpty ? 'The standard does not say yet.' : a.usedFor, style: T.body),
                const SectionLabel('What it changes'),
                Text(a.explanation.isEmpty ? 'The standard does not explain this one yet.' : a.explanation, style: T.body),
                const SectionLabel('Example'),
                if (a.hasExample)
                  Panel(
                    key: Key('archetype-example-${a.name}'),
                    onTap: () {
                      Navigator.pop(sheet);
                      openStandardExample(context, a);
                    },
                    child: Row(
                      children: [
                        Expanded(child: Text(a.exampleTitle.isEmpty ? a.exampleModule : a.exampleTitle, style: T.body)),
                        const Icon(Icons.chevron_right_rounded, color: C.text3),
                      ],
                    ),
                  )
                else
                  Text('No live module uses this archetype yet.', style: T.small.copyWith(color: C.text3)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens the example module of an archetype from the phone's library, or says plainly why it cannot.
void openStandardExample(BuildContext context, StandardArchetype a) {
  final lessons = AppScope.maybeOf(context)?.modules.lessonsOf(a.exampleCourse) ?? const <Map<String, dynamic>>[];
  final target = lessons.where((l) => fmt.s(l['moduleId']) == a.exampleModule).toList();
  if (target.isEmpty) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content: Text(lessons.isEmpty
            ? 'That module is not on this phone yet. Connect to the server once to load the ${a.exampleCourse} course.'
            : 'That module is not in the library yet.')));
    return;
  }
  Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => LessonScreen(
        course: a.exampleCourse,
        file: fmt.s(target.first['file']),
        title: fmt.s(target.first['title']),
        status: fmt.s(target.first['status']),
        allLessons: lessons,
      ),
    ),
  );
}
