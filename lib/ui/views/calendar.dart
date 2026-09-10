import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/day_blocks.dart';
import '../../util/fmt.dart' as fmt;
import '../widgets/common.dart';
import 'learning_export_stub.dart'
    if (dart.library.io) 'learning_export_native.dart' as export_impl;

/// BN26082504: which grid this view renders. Gregorian is the existing
/// month grid (unchanged); Equicycle is Architect's own 28-day cycle, ported
/// from the web's renderEqCalendar(). BN26091024: Planner (the web's
/// week/hour grid, renderPlannerCalendar()) is now built here too, following
/// BT26091023's 5am-first / merged-Rest-row structure from the start.
enum _CalMode { gregorian, equicycle, planner }

/// Ported from the web's getEquicycleContext() -- the year anchors on
/// the first Sunday of June, so a 28-day cycle divides evenly into 4 true
/// weeks. Pure function, no state, easy to keep in sync with the web version
/// if the anchor rule ever changes there.
class _EqContext {
  _EqContext(DateTime today)
      : cycleStart = _computeCycleStart(today),
        dayInCycle = _computeDayInCycle(today) {
    cycleNum = ((today.difference(cycleStart).inDays) ~/ 28) + 1;
  }
  late final DateTime cycleStart;
  late final int dayInCycle;
  late final int cycleNum;
  static const _themes = [
    'Plant', 'Push', 'Climb', 'Reap', 'Dig', 'Weave', 'Mend', 'Scout',
    'Scale', 'Make', 'Run', 'Stock', 'Audit',
  ];
  String get theme => _themes[(cycleNum - 1).clamp(0, 12)];

  static DateTime _eqStart(DateTime today) {
    final eqYear = today.month < 6 ? today.year - 1 : today.year;
    final june1 = DateTime(eqYear, 6, 1);
    final daysAhead = (7 - june1.weekday % 7) % 7;
    return DateTime(eqYear, 6, 1 + daysAhead);
  }

  static int _daysSince(DateTime today) {
    final start = _eqStart(today);
    final diff = DateTime(today.year, today.month, today.day)
        .difference(DateTime(start.year, start.month, start.day))
        .inDays;
    return diff < 0 ? 0 : diff;
  }

  static int _computeDayInCycle(DateTime today) =>
      (_daysSince(today) % 28) + 1;

  static DateTime _computeCycleStart(DateTime today) => DateTime(
      today.year, today.month, today.day)
      .subtract(Duration(days: _computeDayInCycle(today) - 1));
}

/// Month grid + upcoming key dates. Events merge local + M365 server-side.
class CalendarView extends StatefulWidget {
  const CalendarView({super.key});

  @override
  State<CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends State<CalendarView> {
  late DateTime _month;
  DateTime? _selected;
  _CalMode _mode = _CalMode.gregorian;
  bool _busy = false;

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

  Future<void> _importIcs() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['ics'],
      withData: true,
    );
    final files = result?.files ?? const [];
    if (files.isEmpty || files.first.bytes == null) return;
    final file = files.first;
    if (!mounted) return;
    final services = AppScope.of(context);
    setState(() => _busy = true);
    try {
      final text = utf8.decode(file.bytes!, allowMalformed: true);
      final res = await services.api
          .postJson('/api/calendar/import', {'ics': text, 'label': file.name});
      final map = res is Map ? res : <String, dynamic>{};
      if (map['success'] == true) {
        final added = fmt.i(map['added'], 0);
        final found = fmt.i(map['found'], 0);
        services.store.calendar.refresh();
        if (mounted) {
          toast(
              context,
              added > 0
                  ? '$added imported (${found - added} already known)'
                  : 'Nothing new - all $found were already here');
        }
      } else if (mounted) {
        toast(context, fmt.s(map['error']).isEmpty ? 'Import failed' : fmt.s(map['error']), error: true);
      }
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportIcs() async {
    if (!mounted) return;
    final services = AppScope.of(context);
    setState(() => _busy = true);
    try {
      final res = await services.api.getJson('/api/calendar/export');
      final map = res is Map ? res : <String, dynamic>{};
      if (map['ok'] != true) {
        if (mounted) {
          toast(context, fmt.s(map['error']).isEmpty ? 'Export failed' : fmt.s(map['error']), error: true);
        }
        return;
      }
      final ics = fmt.s(map['ics']);
      final name =
          'isconl-calendar-${fmt.isoDate(DateTime.now())}.ics';
      final opened =
          await export_impl.saveAndOpenExport(name, utf8.encode(ics));
      if (mounted && !opened) {
        toast(context, 'Exported to $name, but nothing on this device opens .ics files');
      } else if (mounted) {
        toast(context, 'Calendar exported');
      }
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
                _modeAndActionsRow(),
                const SizedBox(height: 8),
                if (_mode == _CalMode.gregorian) ...[
                  _monthHeader(),
                  const SizedBox(height: 8),
                  Panel(
                    padding: const EdgeInsets.all(8),
                    child: _grid(byDay),
                  ),
                ] else if (_mode == _CalMode.equicycle)
                  Panel(
                    padding: const EdgeInsets.all(8),
                    child: _equicycleGrid(byDay),
                  )
                else
                  Panel(
                    padding: const EdgeInsets.all(4),
                    child: _plannerGrid(byDay),
                  ),
                if (_mode != _CalMode.planner) ...[
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
                ],
                _KeyDates(onAdd: () => _addDateSheet(context)),
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

  Widget _modeAndActionsRow() {
    return Row(
      children: [
        // BN26091024: explicit green selected-state -- SegmentedButton has
        // no style override by default, so it was falling back to Material
        // 3's default blue secondaryContainer tone instead of the app's own
        // green theme primary (theme.dart's ColorScheme.dark never sets
        // secondaryContainer, so nothing derived it from C.green).
        SegmentedButton<_CalMode>(
          style: SegmentedButton.styleFrom(
            selectedBackgroundColor: C.green,
            selectedForegroundColor: C.textInverse,
          ),
          segments: const [
            ButtonSegment(value: _CalMode.gregorian, label: Text('Gregorian')),
            ButtonSegment(value: _CalMode.equicycle, label: Text('Equicycle')),
            ButtonSegment(value: _CalMode.planner, label: Text('Planner')),
          ],
          selected: {_mode},
          onSelectionChanged: (s) => setState(() => _mode = s.first),
        ),
        const Spacer(),
        if (_busy)
          const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2))
        else ...[
          IconButton(
            tooltip: 'Import .ics',
            icon: const Icon(Icons.file_upload_outlined, color: C.text2),
            onPressed: _importIcs,
          ),
          IconButton(
            tooltip: 'Export .ics',
            icon: const Icon(Icons.file_download_outlined, color: C.text2),
            onPressed: _exportIcs,
          ),
        ],
      ],
    );
  }

  Widget _equicycleGrid(Map<String, List<Map<String, dynamic>>> byDay) {
    final today = DateTime.now();
    final ctx = _EqContext(today);
    final weekdayLabels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    final cells = <Widget>[
      for (final wd in weekdayLabels)
        Center(child: Text(wd, style: T.monoSmall.copyWith(color: C.text3))),
    ];
    for (var dayN = 1; dayN <= 28; dayN++) {
      final date = ctx.cycleStart.add(Duration(days: dayN - 1));
      final key = fmt.isoDate(date);
      final items = byDay[key] ?? const [];
      final isToday = dayN == ctx.dayInCycle;
      final isSel = _selected != null && fmt.isoDate(_selected!) == key;
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
              Text('$dayN',
                  style: T.small.copyWith(
                    color: isSel
                        ? C.greenBright
                        : isToday
                            ? C.text
                            : C.text2,
                    fontWeight:
                        isToday || isSel ? FontWeight.w600 : FontWeight.w400,
                  )),
              Text('${date.day}/${date.month}',
                  style: T.monoSmall.copyWith(color: C.text3, fontSize: 8)),
              SizedBox(
                height: 5,
                child: items.isNotEmpty
                    ? const StatusDot(C.green, size: 4)
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text('Cycle ${ctx.cycleNum} · Day ${ctx.dayInCycle} · ${ctx.theme}',
              style: T.title),
        ),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 0.95,
          children: cells,
        ),
      ],
    );
  }

  // BN26091024: the week/hour grid, mobile's first Planner build -- follows
  // BT26091023's web restructure from the start (5am-first hourly rows, the
  // overnight 10pm-5am span merged into one 7x-tall "Rest" row), including
  // the same minute-precise remap() the web version uses so nothing needs
  // redoing once mobile gets per-weekday block data (today every column
  // legitimately shows the same blocks -- see context_ring_card.dart's own
  // note on this, same underlying data model).
  static const double _kHourPx = 34;
  static const int _kDayStart = 300; // 5am, in minutes

  static int _plannerRemap(int m) => ((m - _kDayStart) % 1440 + 1440) % 1440;

  static List<List<int>> _plannerSplit(int start, int end) {
    final s = _plannerRemap(start);
    final dur = (end <= start ? end + 1440 : end) - start;
    final e = s + dur;
    return e > 1440 ? [[s, 1440], [0, e - 1440]] : [[s, e]];
  }

  static Color _plannerTone(String axis) =>
      Color(kAxisToneHex[axis] ?? 0xFF8B949E);

  void _plannerBlockPopup(String name, String when) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(name, style: T.title),
        content: when.isEmpty ? null : Text(when, style: T.body2),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _plannerGrid(Map<String, List<Map<String, dynamic>>> byDay) {
    final services = AppScope.of(context);
    final today = DateTime.now();
    final weekStart = today.subtract(Duration(days: today.weekday % 7));
    const dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

    return ListenableBuilder(
      listenable: services.store.dayBlock,
      builder: (context, _) {
        final rawBlocks =
            fmt.lm(fmt.m(services.store.dayBlock.value)['blocks']);
        final blocks = rawBlocks.isNotEmpty ? rawBlocks : kDefaultDayBlocks;
        const colWidth = 108.0;
        const gutterWidth = 34.0;
        final totalHeight = 24 * _kHourPx;

        // 17 individual hourly labels (5am through the 9pm-10pm slot), then
        // one merged 7x-tall "Rest" row (10pm-5am) -- 17 + 7 = 24 hours, so
        // this always matches the columns' own 24*_kHourPx total height.
        Widget hourLabel(int h) {
          final s = h == 0
              ? '12a'
              : h < 12
                  ? '${h}a'
                  : h == 12
                      ? '12p'
                      : '${h - 12}p';
          return SizedBox(
            height: _kHourPx,
            child: Align(
              alignment: Alignment.topRight,
              child: Text(s, style: T.monoSmall.copyWith(color: C.text3, fontSize: 9)),
            ),
          );
        }

        final gutter = SizedBox(
          width: gutterWidth,
          child: Column(
            children: [
              const SizedBox(height: 40), // matches day-header height below
              for (var i = 0; i < 17; i++) hourLabel(5 + i),
              SizedBox(
                height: 7 * _kHourPx,
                child: Align(
                  alignment: Alignment.topRight,
                  child: Text('REST',
                      style: T.monoSmall.copyWith(color: C.text3, fontSize: 8)),
                ),
              ),
            ],
          ),
        );

        final columns = List.generate(7, (i) {
          final d = weekStart.add(Duration(days: i));
          final key = fmt.isoDate(d);
          final isToday = d.year == today.year &&
              d.month == today.month &&
              d.day == today.day;
          final items = byDay[key] ?? const [];
          final timed = items.where((it) => fmt.s(it['time']).isNotEmpty);

          final bandChildren = <Widget>[];
          for (final b in blocks) {
            final s = fmt.i(b['start'], fmt.i(b['START']));
            final e = fmt.i(b['end'], fmt.i(b['END']));
            final name = fmt.s(b['name'] ?? b['NAME'] ?? 'Block');
            final axis = fmt.s(b['axis'] ?? b['AXIS'] ?? 'work');
            final startClock =
                '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
            final endClock =
                '${(e ~/ 60).toString().padLeft(2, '0')}:${(e % 60).toString().padLeft(2, '0')}';
            for (final seg in _plannerSplit(s, e)) {
              final top = seg[0] / 60 * _kHourPx;
              final h = ((seg[1] - seg[0]) / 60 * _kHourPx).clamp(2.0, totalHeight);
              bandChildren.add(Positioned(
                top: top,
                left: 0,
                right: 0,
                height: h,
                child: GestureDetector(
                  onTap: () =>
                      _plannerBlockPopup(name, '$startClock – $endClock'),
                  child: Container(
                    decoration: BoxDecoration(
                      color: _plannerTone(axis).withValues(alpha: 0.35),
                      border: Border(
                          left: BorderSide(color: _plannerTone(axis), width: 2)),
                    ),
                  ),
                ),
              ));
            }
          }
          for (final it in timed) {
            final parts = fmt.s(it['time']).split(':');
            final h = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0;
            final m = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
            final top = _plannerRemap(h * 60 + m) / 60 * _kHourPx;
            bandChildren.add(Positioned(
              top: top,
              left: 1,
              right: 1,
              height: 16,
              child: GestureDetector(
                onTap: () => _plannerBlockPopup(
                    fmt.s(it['title']), fmt.s(it['time'])),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: C.green.withValues(alpha: 0.22),
                    border: const Border(left: BorderSide(color: C.green, width: 2)),
                  ),
                  child: Text(
                    fmt.s(it['title']),
                    style: T.monoSmall.copyWith(fontSize: 8),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ));
          }

          return SizedBox(
            width: colWidth,
            child: Column(
              children: [
                SizedBox(
                  height: 40,
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: C.panel,
                      border: Border.all(
                          color: isToday ? C.greenDim : C.border, width: isToday ? 1.5 : 1),
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(6)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('${dayNames[i]} ${d.day}',
                            style: T.monoSmall.copyWith(
                                color: isToday ? C.green : C.text,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _selected = d),
                  child: Container(
                    width: colWidth,
                    height: totalHeight,
                    decoration: BoxDecoration(
                      color: C.bg,
                      border: Border.all(color: C.border),
                    ),
                    child: Stack(children: bandChildren),
                  ),
                ),
              ],
            ),
          );
        });

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              gutter,
              const SizedBox(width: 4),
              ...columns,
            ],
          ),
        );
      },
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

  // BN26091024: mobile's half of the day-counter parity gap -- an in-app
  // add-date form. The mutation itself (`services.mutations.addDate()`,
  // POST /api/dates/add) already existed and was already wired to
  // `_store.dates` for refresh; the whole gap was having no UI to call it
  // from, same shape as _addEventSheet() above.
  Future<void> _addDateSheet(BuildContext context) {
    final title = TextEditingController();
    final date = TextEditingController();
    final who = TextEditingController();
    var kind = 'birthday';
    var recurs = true;
    final services = AppScope.of(context);

    return showFormSheet(
      context,
      title: 'Count a date',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Field(
                label: 'What is it',
                controller: title,
                hint: "Olive's birthday, first day at Viva",
                autofocus: true),
            Field(label: 'The original date', controller: date, hint: 'YYYY-MM-DD'),
            Segmented(
              label: 'Kind',
              options: const [
                'birthday', 'first graduation', 'first job', 'anniversary',
                'first', 'deadline',
              ],
              value: kind,
              onChanged: (v) => setSheet(() => kind = v),
            ),
            Field(label: 'Whose (optional)', controller: who, hint: 'leave blank for your own'),
            Row(
              children: [
                Expanded(
                  child: Text('Repeats every year', style: T.body2),
                ),
                Switch(
                    value: recurs,
                    onChanged: (v) => setSheet(() => recurs = v)),
              ],
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: () async {
                if (title.text.trim().isEmpty || date.text.trim().isEmpty) {
                  return;
                }
                Navigator.pop(ctx);
                final res = await services.mutations.addDate({
                  'title': title.text.trim(),
                  'date': date.text.trim(),
                  'kind': kind,
                  'recurs': recurs,
                  if (who.text.trim().isNotEmpty) 'who': who.text.trim(),
                });
                if (!context.mounted) return;
                if (!res.ok) {
                  toast(context, res.error!, error: true);
                } else if (res.queued) {
                  toast(context, 'Date queued - will sync');
                }
              },
              child: const Text('Count this date'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Upcoming key dates (birthdays, renewals, milestones).
///
/// BN26091024: closed the parity gap with the web's day-counter cards
/// (`renderDatesPanel()`) -- per-kind color coding and a real add-date form.
/// `upcoming` (the milestone list this already read) carries no KIND of its
/// own (pulse's `listDates()` only copies `title`/`id` onto each milestone),
/// but it does carry the parent date's `id` -- so `_kindColor` below joins
/// back against the full `dates` list (also returned by the same snapshot)
/// to find each milestone's KIND, same information web's server-composed
/// card already has for free.
class _KeyDates extends StatelessWidget {
  const _KeyDates({required this.onAdd});

  final VoidCallback onAdd;

  // Ported from the web's kindColor map (app.js ~1767).
  static const Map<String, Color> _kindColors = {
    'birthday': C.violet,
    'anniversary': C.green,
    'graduation': C.green,
    'first graduation': C.green,
    'first job': C.cyan,
    'first': C.cyan,
    'deadline': C.amber,
  };

  Color _kindColor(String kind) => _kindColors[kind.toLowerCase()] ?? C.text3;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return ListenableBuilder(
      listenable: services.store.dates,
      builder: (context, _) {
        final value = fmt.m(services.store.dates.value);
        final upcoming = fmt.lm(value['upcoming']);
        final dates = fmt.lm(value['dates']);
        final kindById = {
          for (final d in dates) fmt.s(d['ID']): fmt.s(d['KIND']),
        };

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(child: SectionLabel('Key dates')),
                TextButton(
                  onPressed: onAdd,
                  child: const Text('Add a date'),
                ),
              ],
            ),
            if (upcoming.isEmpty)
              const Panel(
                child: Text(
                  'Nothing counted yet. Add the dates a life gets measured '
                  'against - birthdays, anniversaries, the day something '
                  'started - and the counters take it from there.',
                ),
              )
            else
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
                            Container(
                              width: 3,
                              height: 30,
                              decoration: BoxDecoration(
                                color: _kindColor(
                                    kindById[fmt.s(upcoming[idx]['id'])] ?? ''),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 8),
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
