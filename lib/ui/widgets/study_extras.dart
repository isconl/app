import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../services/study_extras.dart';
import '../../theme.dart';
import '../../util/markdown.dart';

StudyExtrasApi _defaultApi(BuildContext context) => HubStudyExtrasApi(AppScope.of(context).api);

Color _toneColor(String tone) => switch (tone) {
      'urgent' => C.red,
      'soon' => C.amber,
      'later' => C.cyan,
      _ => C.text3,
    };

/// Campus: what to read right now, and why, in bands, as the console shows it. Tap a
/// module to open it. Collapsed by a tap on the header.
class CampusCard extends StatefulWidget {
  const CampusCard({super.key, this.api, required this.onOpen});
  final StudyExtrasApi? api;

  /// Opens a module (course id, lesson file); with no lesson, the course.
  final void Function(String courseId, String lesson) onOpen;

  @override
  State<CampusCard> createState() => _CampusCardState();
}

class _CampusCardState extends State<CampusCard> {
  Future<Campus>? _f;
  bool _open = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _f ??= (widget.api ?? _defaultApi(context)).campus();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Campus>(
        future: _f,
        builder: (context, snap) {
          final c = snap.data;
          // Nothing to say, or the agent cannot be reached: the Study page stands without it.
          if (c == null || c.isEmpty) return const SizedBox.shrink();
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(border: Border.all(color: C.border), borderRadius: BorderRadius.circular(Sz.rMd)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              InkWell(
                key: const Key('campus-head'),
                onTap: () => setState(() => _open = !_open),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Campus', style: T.title),
                        Text('What to read right now, and why${c.minutes > 0 ? ', about ${c.minutes} min for the urgent ones' : ''}', style: T.small),
                      ]),
                    ),
                    if (c.computed) Text('computed', key: const Key('campus-computed'), style: T.tiny.copyWith(color: C.amber)),
                    Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded),
                  ]),
                ),
              ),
              if (_open)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (final b in c.bands.where((b) => b.items.isNotEmpty)) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 4),
                        child: Row(children: [
                          Container(width: 3, height: 14, color: _toneColor(b.tone)),
                          const SizedBox(width: 8),
                          Text(b.label.toUpperCase(), style: T.label),
                          const Spacer(),
                          Text('${b.items.length}', style: T.monoSmall),
                        ]),
                      ),
                      for (final i in b.items)
                        InkWell(
                          key: Key('campus-${i.courseId}-${i.lesson}'),
                          onTap: () => widget.onOpen(i.courseId, i.lesson),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Expanded(child: Text(i.title, style: T.body2)),
                                if (i.done) Text('read', style: T.tiny.copyWith(color: C.greenBright)),
                              ]),
                              Text('${i.courseTitle}${i.minutes > 0 ? ' · ${i.minutes} min' : ''}', style: T.tiny),
                              if (i.headline.isNotEmpty) Text(i.headline, style: T.small),
                              if (i.why.isNotEmpty) Text(i.why, style: T.tiny.copyWith(fontStyle: FontStyle.italic)),
                            ]),
                          ),
                        ),
                    ],
                  ]),
                ),
            ]),
          );
        },
      );
}

/// A heat grid of activity with the console's three numbers: contributions, active
/// days and the day streak. [loader] is what to fetch; [onRefresh] adds a Refresh
/// button that forces a fresh read (GitHub's own data is cached).
class ContributionsCard extends StatefulWidget {
  const ContributionsCard({super.key, required this.title, required this.loader, this.canRefresh = false, this.weeks = 26});
  final String title;
  final Future<Contributions> Function(bool refresh) loader;
  final bool canRefresh;

  /// How many weeks of columns to show (the grid scrolls sideways past this on small phones).
  final int weeks;

  @override
  State<ContributionsCard> createState() => _ContributionsCardState();
}

class _ContributionsCardState extends State<ContributionsCard> {
  late Future<Contributions> _f = widget.loader(false);
  bool _refreshing = false;

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    final f = widget.loader(true);
    setState(() {
      _f = f;
    });
    try {
      await f;
    } catch (_) {}
    if (mounted) setState(() => _refreshing = false);
  }

  static const _shades = [0.0, 0.22, 0.42, 0.68, 1.0];

  @override
  Widget build(BuildContext context) => FutureBuilder<Contributions>(
        future: _f,
        builder: (context, snap) {
          Widget body;
          if (snap.connectionState != ConnectionState.done) {
            body = Text('Loading...', style: T.small);
          } else if (snap.hasError) {
            body = Text('Could not load the activity map.', key: const Key('contrib-error'), style: T.small.copyWith(color: C.red));
          } else {
            final c = snap.data!;
            if (c.days.isEmpty) {
              body = Text('No activity recorded yet.', key: const Key('contrib-empty'), style: T.small);
            } else {
              body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  _stat('${c.total}', c.total == 1 ? 'contribution' : 'contributions', const Key('contrib-total')),
                  _stat('${c.activeDays}', c.activeDays == 1 ? 'active day' : 'active days', const Key('contrib-active')),
                  _stat('${c.streak}', 'day streak', const Key('contrib-streak')),
                ]),
                const SizedBox(height: 10),
                _grid(c),
              ]);
            }
          }
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(border: Border.all(color: C.border), borderRadius: BorderRadius.circular(Sz.rMd)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(widget.title, style: T.title)),
                if (widget.canRefresh)
                  TextButton(key: const Key('contrib-refresh'), onPressed: _refreshing ? null : _refresh, child: Text(_refreshing ? 'Loading...' : 'Refresh')),
              ]),
              const SizedBox(height: 6),
              body,
            ]),
          );
        },
      );

  Widget _stat(String n, String label, Key key) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(n, key: key, style: T.headline),
          Text(label, style: T.tiny),
        ]),
      );

  Widget _grid(Contributions c) {
    // Pad so the first column starts on the right weekday (the console does the same).
    final first = DateTime.tryParse(c.days.first.date);
    final pad = first == null ? 0 : first.weekday % 7; // Sunday = 0
    final cells = <ContribDay?>[...List<ContribDay?>.filled(pad, null), ...c.days];
    final weeks = <List<ContribDay?>>[];
    for (var i = 0; i < cells.length; i += 7) {
      weeks.add(cells.sublist(i, i + 7 > cells.length ? cells.length : i + 7));
    }
    final shown = weeks.length > widget.weeks ? weeks.sublist(weeks.length - widget.weeks) : weeks;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      child: Row(children: [
        for (final w in shown)
          Column(children: [
            for (var d = 0; d < 7; d++)
              Container(
                key: d < w.length && w[d] != null ? Key('day-${w[d]!.date}') : null,
                width: 10,
                height: 10,
                margin: const EdgeInsets.all(1.2),
                decoration: BoxDecoration(
                  color: d < w.length && w[d] != null
                      ? (c.level(w[d]!.count) == 0 ? C.surface : C.greenBright.withValues(alpha: _shades[c.level(w[d]!.count)]))
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
          ]),
      ]),
    );
  }
}

/// "Prime me": the module most relevant to a task, before starting it. Shows the first
/// 40 lines, with the whole lesson one tap away.
class PrimeCard extends StatefulWidget {
  const PrimeCard({super.key, required this.query, this.api, this.onOpen});

  /// The task's title and why.
  final String query;
  final StudyExtrasApi? api;
  final void Function(String course, String file)? onOpen;

  @override
  State<PrimeCard> createState() => _PrimeCardState();
}

class _PrimeCardState extends State<PrimeCard> {
  Future<PrimeResult>? _f;
  bool _full = false;

  void _find() {
    setState(() {
      _full = false;
      _f = (widget.api ?? _defaultApi(context)).prime(widget.query);
    });
  }

  @override
  Widget build(BuildContext context) {
    final head = Row(children: [
      Expanded(child: Text('Prime me', style: T.title)),
      TextButton(key: const Key('prime-go'), onPressed: _find, child: Text(_f == null ? 'Find the lesson' : 'Refresh')),
    ]);
    Widget body;
    if (_f == null) {
      body = Text('Finds the module most relevant to this task, so you walk in knowing the framework and not just the deadline.', style: T.small);
    } else {
      body = FutureBuilder<PrimeResult>(
        future: _f,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return Text('Scanning the vault...', style: T.small);
          if (snap.hasError) return Text('${snap.error}'.replaceFirst('ApiException(0): ', ''), key: const Key('prime-error'), style: T.small.copyWith(color: C.red));
          final p = snap.data!;
          if (!p.ok) return Text(p.error.isEmpty ? 'No matching lesson found.' : p.error, key: const Key('prime-none'), style: T.small);
          final lines = p.content.split('\n');
          final preview = lines.take(40).join('\n');
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${p.course} · ${p.file}', key: const Key('prime-source'), style: T.tiny),
            const SizedBox(height: 6),
            Markdown(_full ? p.content : preview),
            if (lines.length > 40)
              TextButton(
                key: const Key('prime-more'),
                onPressed: () => setState(() => _full = !_full),
                child: Text(_full ? 'Show less' : 'Show the full lesson'),
              ),
            if (widget.onOpen != null) TextButton(key: const Key('prime-open'), onPressed: () => widget.onOpen!(p.course, p.file), child: const Text('Open in the reader')),
          ]);
        },
      );
    }
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(border: Border.all(color: C.border), borderRadius: BorderRadius.circular(Sz.rMd)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [head, const SizedBox(height: 6), body]),
    );
  }
}

/// Under a paragraph: the tutor's answer (or that it is thinking, or why it could not
/// answer), with a way to dismiss it. Nothing at all until a question was asked.
class TutorFooter extends StatelessWidget {
  const TutorFooter({super.key, required this.controller, required this.paragraph, required this.text});
  final TutorController controller;
  final int paragraph;

  /// The paragraph's text, quoted to the tutor.
  final String text;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final answer = controller.answers[paragraph];
          final error = controller.errors[paragraph];
          final busy = controller.thinking.contains(paragraph);
          if (answer == null && error == null && !busy) {
            if (!controller.mode) return const SizedBox.shrink();
            return Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: Key('tutor-ask-$paragraph'),
                onPressed: () => askTutorAbout(context, controller, paragraph, text),
                icon: const Icon(Icons.school_outlined, size: 16),
                label: const Text('Ask the tutor'),
              ),
            );
          }
          return Container(
            key: Key('tutor-$paragraph'),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: C.cyan, width: 2.5)),
              color: C.cyanBg,
              borderRadius: BorderRadius.circular(Sz.rSm),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('TUTOR', style: T.label.copyWith(color: C.cyan)),
                const Spacer(),
                IconButton(
                  key: Key('tutor-dismiss-$paragraph'),
                  tooltip: 'Dismiss',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded, size: 16),
                  onPressed: () => controller.dismiss(paragraph),
                ),
              ]),
              if (busy) Text('The tutor is reading...', key: const Key('tutor-thinking'), style: T.small),
              if (error != null) Text(error, key: const Key('tutor-error'), style: T.small.copyWith(color: C.red)),
              if (answer != null) Markdown(answer),
            ]),
          );
        },
      );
}

/// Long-press on a paragraph asks this: the passage is quoted, the reader types the
/// question, and the answer shows under that paragraph.
Future<void> askTutorAbout(BuildContext context, TutorController controller, int paragraph, String text) async {
  final question = await showDialog<String>(
    context: context,
    builder: (_) => _TutorDialog(passage: text),
  );
  if (question == null || question.trim().isEmpty) return;
  await controller.ask(paragraph, text, question);
}

class _TutorDialog extends StatefulWidget {
  const _TutorDialog({required this.passage});
  final String passage;
  @override
  State<_TutorDialog> createState() => _TutorDialogState();
}

class _TutorDialogState extends State<_TutorDialog> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.passage.trim().replaceAll(RegExp(r'\s+'), ' ');
    return AlertDialog(
      title: const Text('Ask the tutor'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(p.length > 160 ? '${p.substring(0, 157)}...' : p, key: const Key('tutor-passage'), style: T.small.copyWith(fontStyle: FontStyle.italic)),
          const SizedBox(height: 10),
          TextField(key: const Key('tutor-question'), controller: _c, autofocus: true, minLines: 2, maxLines: 5, decoration: const InputDecoration(hintText: 'What is unclear?')),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(key: const Key('tutor-send'), onPressed: () => Navigator.pop(context, _c.text), child: const Text('Ask')),
      ],
    );
  }
}
