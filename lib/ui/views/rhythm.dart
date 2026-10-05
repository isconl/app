import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../widgets/common.dart';

/// Rhythm: today's habits and the year behind them.
///
/// Four of the habits are derived rather than ticked - the server infers them
/// from commits, lessons, journal entries and finished tasks. Those are shown
/// as evidence, not as checkboxes, because a tick that the next sync overwrites
/// is a lie about who is in control.
class RhythmView extends StatelessWidget {
  const RhythmView({super.key});

  static const _autoHabits = {'h-gh', 'h-learn', 'h-journal', 'h-tasks'};

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return SnapshotView(
      snapshot: services.store.rhythm,
      builder: (context, data) {
        final map = fmt.m(data);
        final habits = fmt.lm(map['habits']);
        final logs = fmt.m(map['logs']);
        final days = fmt.lm(map['days']);
        final today = fmt.isoDate(DateTime.now());
        final todayLog = fmt.m(logs[today]);

        final doneToday =
            habits.where((h) => fmt.b(todayLog[fmt.s(h['id'])])).length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                    child: _stat('TODAY', '$doneToday/${habits.length}',
                        C.greenBright)),
                const SizedBox(width: Sz.gap),
                Expanded(
                    child: _stat('STREAK', '${_streak(days)}d', C.cyan)),
                const SizedBox(width: Sz.gap),
                Expanded(
                    child: _stat('YEAR', '${_activeDays(days)}d', C.violet)),
              ],
            ),
            SectionLabel('Today',
                trailing: TextButton.icon(
                  onPressed: () => _editHabit(context, services, habits, null),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Habit'),
                )),
            ...habits.map((h) {
              final id = fmt.s(h['id']);
              final auto = _autoHabits.contains(id);
              final done = fmt.b(todayLog[id]);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _HabitTile(
                  habit: h,
                  done: done,
                  auto: auto,
                  onEdit: () => _editHabit(context, services, habits, h),
                  onToggle: auto
                      ? null
                      : () async {
                          final res = await services.mutations.toggleHabit(
                              date: today, habitId: id, done: !done);
                          if (!context.mounted) return;
                          if (!res.ok) {
                            toast(context, res.error!, error: true);
                          } else if (res.queued) {
                            toast(context, 'Queued - will sync');
                          }
                        },
                ),
              );
            }),
            const SectionLabel('The year'),
            Panel(child: _Heatmap(days: days)),
            const SizedBox(height: 10),
            Text(
              'Derived habits (commits, lessons, journal, tasks) are read from '
              'what you actually did. Only the rest are yours to tick.',
              style: T.tiny,
            ),
          ],
        );
      },
    );
  }

  /// BI26092515: add or edit a habit, with its focus word, minimum version and
  /// anchor. The whole list is sent back (the server replaces it), including
  /// the four derived habits when the store was still on its seeds.
  Future<void> _editHabit(BuildContext context, dynamic services,
      List<Map<String, dynamic>> habits, Map<String, dynamic>? existing) {
    final title = TextEditingController(text: fmt.s(existing?['title']));
    final word = TextEditingController(text: fmt.s(existing?['focusWord']));
    final minimum =
        TextEditingController(text: fmt.s(existing?['minimumVersion']));
    final anchor = TextEditingController(text: fmt.s(existing?['anchor']));
    return showFormSheet(
      context,
      title: existing == null ? 'New habit' : 'Edit habit',
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Field(label: 'Habit', controller: title, autofocus: existing == null),
          Field(
              label: 'Focus word',
              controller: word,
              hint: 'optional, e.g. Recovery: links it to a cycle focus'),
          Field(
              label: 'Minimum version',
              controller: minimum,
              hint: 'optional, e.g. 10-min walk after lunch'),
          Field(
              label: 'Anchor',
              controller: anchor,
              hint: 'optional: the when/where it is stacked on'),
          const SizedBox(height: 4),
          FilledButton(
            onPressed: () async {
              if (title.text.trim().isEmpty) return;
              Navigator.pop(ctx);
              final focus = word.text.trim();
              final updated = <String, dynamic>{
                ...?existing,
                if (existing == null)
                  'id': 'h-${DateTime.now().millisecondsSinceEpoch}',
                'title': title.text.trim(),
                'focusWord': focus,
                'minimumVersion': minimum.text.trim(),
                'anchor': anchor.text.trim(),
                // A habit starts when it is first linked to a word; editing
                // keeps its original start.
                if (focus.isNotEmpty && fmt.s(existing?['startedAt']).isEmpty)
                  'startedAt': fmt.isoDate(DateTime.now()),
              };
              // Blank optional fields are sent as empty text, which the
              // server treats as "not set".
              final next = existing == null
                  ? [...habits, updated]
                  : [
                      for (final h in habits)
                        fmt.s(h['id']) == fmt.s(existing['id']) ? updated : h,
                    ];
              final res = await services.mutations.saveHabits(next);
              if (!context.mounted) return;
              if (!res.ok) {
                toast(context, res.error!, error: true);
              } else if (res.queued) {
                toast(context, 'Queued - will sync');
              }
            },
            child: Text(existing == null ? 'Add' : 'Save'),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Panel(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: T.label),
          const SizedBox(height: 4),
          Text(value, style: T.headline.copyWith(color: color, fontSize: 16)),
        ],
      ),
    );
  }

  /// Consecutive active days ending today (or yesterday, so an unfinished
  /// morning does not read as a broken streak).
  int _streak(List<Map<String, dynamic>> days) {
    var streak = 0;
    for (var idx = days.length - 1; idx >= 0; idx--) {
      final count = fmt.i(days[idx]['count']);
      if (count > 0) {
        streak++;
      } else if (idx != days.length - 1) {
        break;
      }
    }
    return streak;
  }

  int _activeDays(List<Map<String, dynamic>> days) =>
      days.where((d) => fmt.i(d['count']) > 0).length;
}

class _HabitTile extends StatelessWidget {
  const _HabitTile({
    required this.habit,
    required this.done,
    required this.auto,
    required this.onToggle,
    required this.onEdit,
  });

  final Map<String, dynamic> habit;
  final bool done;
  final bool auto;
  final VoidCallback? onToggle;
  final VoidCallback onEdit;

  /// BI26092515: colour of a stage tag. The stage itself is derived by the
  /// server from the cycle mix; this only paints it.
  static Color _stageColor(String stage) {
    switch (stage) {
      case 'primary':
        return C.greenBright;
      case 'secondary':
        return C.cyan;
      case 'tertiary':
        return C.violet;
      case 'maintenance':
        return C.text2;
      default:
        return C.text3;
    }
  }

  @override
  Widget build(BuildContext context) {
    final word = fmt.s(habit['focusWord']);
    final stage = fmt.s(habit['stage']);
    final minimum = fmt.s(habit['minimumVersion']);
    final anchor = fmt.s(habit['anchor']);
    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      onTap: onToggle,
      onLongPress: onEdit,
      borderColor: done ? C.greenDim.withValues(alpha: 0.5) : C.border,
      color: done ? C.greenBg2 : C.panel,
      child: Row(
        children: [
          // BN26091026/BG26091017: never render a raw, user-authored
          // icon/emoji field straight from data -- one fixed monochrome
          // glyph for every habit, matching web's svgIcon('pin', ...) fix.
          Icon(Icons.push_pin_outlined, size: 17, color: C.text2),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(fmt.s(habit['title']),
                    style: T.w500(T.body2.copyWith(
                        color: done ? C.text : C.text2))),
                if (auto)
                  Text('tracked automatically', style: T.tiny),
                if (word.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: _stageColor(stage).withValues(alpha: 0.6)),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                              stage.isEmpty ? word : '$word · $stage',
                              style: T.tiny
                                  .copyWith(color: _stageColor(stage))),
                        ),
                      ],
                    ),
                  ),
                if (minimum.isNotEmpty || anchor.isNotEmpty)
                  Text(
                      [
                        if (minimum.isNotEmpty) minimum,
                        if (anchor.isNotEmpty) 'after: $anchor',
                      ].join(' · '),
                      style: T.tiny),
              ],
            ),
          ),
          if (auto)
            Icon(
              done
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 20,
              color: done ? C.green : C.text3,
            )
          else
            Checkbox(
              value: done,
              onChanged: onToggle == null ? null : (_) => onToggle!(),
            ),
        ],
      ),
    );
  }
}

/// A year of activity as a 7-row grid, most recent column on the right.
class _Heatmap extends StatelessWidget {
  const _Heatmap({required this.days});
  final List<Map<String, dynamic>> days;

  static const _cell = 9.0;
  static const _gap = 2.0;

  Color _shade(int count) {
    if (count <= 0) return C.surface;
    if (count == 1) return C.greenDim.withValues(alpha: 0.45);
    if (count == 2) return C.greenDim.withValues(alpha: 0.7);
    if (count <= 4) return C.green;
    return C.greenBright;
  }

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) {
      return const EmptyState('No rhythm yet',
          'Tick a habit and this fills in.', icon: Icons.grid_on_rounded);
    }
    // Pad the front so the first column starts on a Sunday, which is what makes
    // the rows read as weekdays rather than an arbitrary 7-way split.
    final first = fmt.parseDate(days.first['date']) ?? DateTime.now();
    final lead = first.weekday % 7;
    final cells = <Map<String, dynamic>?>[
      ...List.filled(lead, null),
      ...days,
    ];
    final weeks = (cells.length / 7).ceil();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          reverse: true, // open on the present, not on last August
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var w = 0; w < weeks; w++)
                Padding(
                  padding: const EdgeInsets.only(right: _gap),
                  child: Column(
                    children: [
                      for (var dow = 0; dow < 7; dow++)
                        Builder(builder: (_) {
                          final idx = w * 7 + dow;
                          final cell =
                              idx < cells.length ? cells[idx] : null;
                          if (cell == null) {
                            return const SizedBox(
                                width: _cell, height: _cell + _gap);
                          }
                          final count = fmt.i(cell['count']);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: _gap),
                            child: Tooltip(
                              message:
                                  '${fmt.shortDate(cell['date'])} · ${fmt.plural(count, 'thing')}',
                              child: Container(
                                width: _cell,
                                height: _cell,
                                decoration: BoxDecoration(
                                  color: _shade(count),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('less', style: T.monoSmall),
            const SizedBox(width: 5),
            for (final n in [0, 1, 2, 3, 5])
              Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Container(
                  width: _cell,
                  height: _cell,
                  decoration: BoxDecoration(
                    color: _shade(n),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            const SizedBox(width: 3),
            Text('more', style: T.monoSmall),
          ],
        ),
      ],
    );
  }
}
