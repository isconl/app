import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../widgets/common.dart';

/// Month grid + upcoming key dates. Events merge local + M365 server-side.
class CalendarView extends StatefulWidget {
  const CalendarView({super.key});

  @override
  State<CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends State<CalendarView> {
  late DateTime _month;
  DateTime? _selected;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _selected = DateTime(now.year, now.month, now.day);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final services = AppScope.of(context);
      services.sync.touch(services.store.dates);
    });
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return Stack(
      children: [
        SnapshotView(
          snapshot: services.store.calendar,
          builder: (context, data) {
            final events = fmt.lm(fmt.m(data)['events']);
            final byDay = <String, List<Map<String, dynamic>>>{};
            for (final e in events) {
              final day = fmt.s(e['date']);
              if (day.isNotEmpty) byDay.putIfAbsent(day, () => []).add(e);
            }
            final selKey =
                _selected == null ? '' : fmt.isoDate(_selected!);
            final dayEvents = byDay[selKey] ?? const [];

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _monthHeader(),
                const SizedBox(height: 8),
                Panel(
                  padding: const EdgeInsets.all(8),
                  child: _grid(byDay),
                ),
                SectionLabel(_selected == null
                    ? 'Events'
                    : fmt.weekdayDate(_selected!)),
                if (dayEvents.isEmpty)
                  const Panel(
                      child:
                          Text('No events this day. Tap + to add one.'))
                else
                  ...dayEvents.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Panel(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          child: Row(
                            children: [
                              Container(
                                width: 3,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: fmt.s(e['source']) == 'microsoft'
                                      ? C.cyan
                                      : C.green,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(fmt.s(e['title']), style: T.body2),
                                    const SizedBox(height: 2),
                                    Text(
                                      [
                                        if (fmt.s(e['time']).isNotEmpty)
                                          fmt.s(e['time']),
                                        if (fmt
                                            .s(e['location'])
                                            .isNotEmpty)
                                          fmt.s(e['location']),
                                        if (fmt.s(e['category']).isNotEmpty)
                                          fmt.s(e['category']),
                                      ].join(' · '),
                                      style: T.monoSmall,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      )),
                const _KeyDates(),
              ],
            );
          },
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            backgroundColor: C.greenDim,
            foregroundColor: Colors.white,
            onPressed: () => _addEventSheet(context),
            child: const Icon(Icons.add_rounded),
          ),
        ),
      ],
    );
  }

  Widget _monthHeader() {
    return Row(
      children: [
        Text('${fmt.monthsFull[_month.month - 1]} ${_month.year}',
            style: T.title),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.chevron_left_rounded, color: C.text2),
          onPressed: () => setState(
              () => _month = DateTime(_month.year, _month.month - 1)),
        ),
        TextButton(
          onPressed: () {
            final now = DateTime.now();
            setState(() {
              _month = DateTime(now.year, now.month);
              _selected = DateTime(now.year, now.month, now.day);
            });
          },
          child: const Text('Today'),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right_rounded, color: C.text2),
          onPressed: () => setState(
              () => _month = DateTime(_month.year, _month.month + 1)),
        ),
      ],
    );
  }

  Widget _grid(Map<String, List<Map<String, dynamic>>> byDay) {
    final firstDay = DateTime(_month.year, _month.month, 1);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leading = (firstDay.weekday + 6) % 7; // Monday-first
    final today = DateTime.now();
    final cells = <Widget>[];

    for (final wd in ['M', 'T', 'W', 'T', 'F', 'S', 'S']) {
      cells.add(Center(
          child:
              Text(wd, style: T.monoSmall.copyWith(color: C.text3))));
    }
    for (var idx = 0; idx < leading; idx++) {
      cells.add(const SizedBox.shrink());
    }
    for (var day = 1; day <= daysInMonth; day++) {
      final date = DateTime(_month.year, _month.month, day);
      final key = fmt.isoDate(date);
      final has = byDay.containsKey(key);
      final isToday = date.year == today.year &&
          date.month == today.month &&
          date.day == today.day;
      final isSel = _selected != null &&
          date.year == _selected!.year &&
          date.month == _selected!.month &&
          date.day == _selected!.day;
      cells.add(GestureDetector(
        onTap: () => setState(() => _selected = date),
        child: Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: isSel ? C.greenBg : null,
            border: Border.all(
                color: isSel
                    ? C.green
                    : isToday
                        ? C.borderMid
                        : Colors.transparent),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('$day',
                  style: T.small.copyWith(
                    color: isSel
                        ? C.greenBright
                        : isToday
                            ? C.text
                            : C.text2,
                    fontWeight: isToday || isSel
                        ? FontWeight.w600
                        : FontWeight.w400,
                  )),
              SizedBox(
                height: 5,
                child: has
                    ? const StatusDot(C.green, size: 4)
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ));
    }
    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 0.95,
      children: cells,
    );
  }

  Future<void> _addEventSheet(BuildContext context) {
    final title = TextEditingController();
    final date = TextEditingController(
        text: _selected == null ? '' : fmt.isoDate(_selected!));
    final time = TextEditingController();
    final location = TextEditingController();
    var makeTask = false;
    final services = AppScope.of(context);

    return showFormSheet(
      context,
      title: 'New event',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Field(label: 'Title', controller: title, autofocus: true),
            Field(label: 'Date', controller: date, hint: 'YYYY-MM-DD'),
            Field(label: 'Time (optional)', controller: time, hint: '14:30'),
            Field(label: 'Location (optional)', controller: location),
            Row(
              children: [
                Expanded(
                    child:
                        Text('Also create a task', style: T.body2)),
                Switch(
                    value: makeTask,
                    onChanged: (v) => setSheet(() => makeTask = v)),
              ],
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: () async {
                if (title.text.trim().isEmpty ||
                    date.text.trim().isEmpty) {
                  return;
                }
                Navigator.pop(ctx);
                final res = await services.mutations.addEvent({
                  'title': title.text.trim(),
                  'date': date.text.trim(),
                  if (time.text.trim().isNotEmpty)
                    'time': time.text.trim(),
                  if (location.text.trim().isNotEmpty)
                    'location': location.text.trim(),
                  'makeTask': makeTask,
                });
                if (!context.mounted) return;
                if (!res.ok) {
                  toast(context, res.error!, error: true);
                } else if (res.queued) {
                  toast(context, 'Event queued - will sync');
                }
              },
              child: const Text('Add event'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Upcoming key dates (birthdays, renewals, milestones).
class _KeyDates extends StatelessWidget {
  const _KeyDates();

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return ListenableBuilder(
      listenable: services.store.dates,
      builder: (context, _) {
        final upcoming =
            fmt.lm(fmt.m(services.store.dates.value)['upcoming']);
        if (upcoming.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionLabel('Key dates'),
            Panel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var idx = 0;
                      idx < upcoming.length && idx < 8;
                      idx++) ...[
                    if (idx > 0) const Divider(),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: Sz.pad, vertical: 10),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 44,
                            child: Text(
                              _daysBadge(fmt.i(upcoming[idx]['days'], -1)),
                              style: T.mono.copyWith(
                                color: fmt.i(upcoming[idx]['days'], 99) <= 1
                                    ? C.amber
                                    : C.green,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              fmt.s(upcoming[idx]['label']).isEmpty
                                  ? fmt.s(upcoming[idx]['title'])
                                  : fmt.s(upcoming[idx]['label']),
                              style: T.body2,
                            ),
                          ),
                          Text(fmt.shortDate(upcoming[idx]['date']),
                              style: T.monoSmall),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  String _daysBadge(int days) {
    if (days < 0) return '—';
    if (days == 0) return 'today';
    return 'in ${days}d';
  }
}
