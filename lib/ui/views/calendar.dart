import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/day_blocks.dart';
import '../../util/cycle_theme_bus.dart';
import '../../util/equicycle.dart';
import 'equicycle_grid_view.dart';
import '../../util/fmt.dart' as fmt;
import '../widgets/common.dart';
import '../widgets/parity3b_widgets.dart';
import '../widgets/month_grid.dart';
import '../widgets/sub_tabs.dart';
import '../../util/tab_memory.dart';
import 'learning_export_stub.dart'
    if (dart.library.io) 'learning_export_native.dart' as export_impl;

/// BN26082504: which grid this view renders. Gregorian is the existing
/// month grid (unchanged); Equicycle is Architect's own 28-day cycle, ported
/// from the web's renderEqCalendar(). BN26091024: Planner (the web's
/// week/hour grid, renderPlannerCalendar()) is now built here too, following
/// BT26091023's 5am-first / merged-Rest-row structure from the start.
enum _CalMode { gregorian, equicycle, planner }

/// BI26101519: the tab order, Equicycle first. A fresh install opens on it.
const _calModes = [_CalMode.equicycle, _CalMode.gregorian, _CalMode.planner];
String _calModeLabel(_CalMode m) => switch (m) {
      _CalMode.equicycle => 'Equicycle',
      _CalMode.gregorian => 'Gregorian',
      _CalMode.planner => 'Planner',
    };

/// BI26100205 (Equicycle 2): the position comes from the cached year table
/// (util/equicycle.dart), never from arithmetic here. When no table covers
/// today, [unavailable] is true and the view says so instead of guessing.
class _EqContext {
  _EqContext(DateTime today) : pos = EquicycleYears.instance.positionFor(today);
  final EqPosition? pos;
  bool get unavailable => pos == null;
  DateTime get cycleStart => pos!.cycleStart;
  int get dayInCycle => pos!.day;
  int get cycleNum => pos!.cycle;
  int get eqYear => pos!.year;
  bool get stillweek => pos!.stillweek;
  static const _themes = [
    'Plant', 'Push', 'Climb', 'Reap', 'Dig', 'Weave', 'Mend', 'Scout',
    'Scale', 'Make', 'Run', 'Stock', 'Audit',
  ];
  /// Local fallback only -- BN26091025: the real source of truth is now
  /// GET /api/cycle-theme, which can override a cycle's theme.
  /// _CalendarViewState._loadServerTheme fetches it and falls back to this
  /// array when the server has no override for the cycle (theme: null).
  String get theme => _themes[(cycleNum - 1).clamp(0, 12)];

  /// Key the server's cycle themes are keyed on: `eq2:26-C04`. vault and
  /// scope accept the old `26-4` form too, so this can ship before or after
  /// their migration.
  String get cycleKey => pos!.cycleKey;
}

/// Month grid + upcoming key dates. Events merge local + M365 server-side.
class CalendarView extends StatefulWidget {
  const CalendarView({super.key});

  @override
  State<CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends State<CalendarView> with WidgetsBindingObserver {
  late DateTime _month;
  DateTime? _selected;
  _CalMode _mode = _CalMode.equicycle;
  bool _busy = false;

  // BN26091025: server-driven cycle theme (GET /api/cycle-theme), keyed by
  // the cycle it was fetched for so a new cycle triggers a fresh fetch
  // rather than showing a stale one. Null theme = no override, fall back to
  // _EqContext's local 13-name array.
  String? _serverThemeKey;
  String? _serverTheme;

  void _maybeLoadServerTheme(String cycleKey, {bool force = false}) {
    if (!force && _serverThemeKey == cycleKey) return;
    _serverThemeKey = cycleKey;
    final services = AppScope.of(context);
    services.api.getJson('/api/cycle-theme?cycleKey=$cycleKey').then((res) {
      if (!mounted || _serverThemeKey != cycleKey) return;
      final theme = res is Map ? res['theme'] : null;
      setState(() => _serverTheme = theme is String && theme.isNotEmpty ? theme : null);
    }).catchError((_) {
      // Offline or server error: silently keep the local fallback theme.
    });
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _selected = DateTime(now.year, now.month, now.day);
    EquicycleYears.instance.addListener(_onYears);
    CycleThemeBus.instance.addListener(_onThemeChanged);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final services = AppScope.of(context);
      services.sync.touch(services.store.dates);
      EquicycleYears.instance.ensureLoaded(services.api, services.db);
      // The last mode chosen on this device wins; a fresh install keeps Equicycle.
      readTabIndex(services.db, 'calendar', _calModes.length).then((i) {
        if (mounted && i != null) setState(() => _mode = _calModes[i]);
      });
    });
  }

  void _onYears() {
    if (mounted) setState(() {});
  }

  /// BI26101811: compass saved a theme, or the app came back to the foreground: read the theme again.
  void _onThemeChanged() {
    final k = _serverThemeKey;
    if (mounted && k != null) _maybeLoadServerTheme(k, force: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _onThemeChanged();
  }

  @override
  void dispose() {
    EquicycleYears.instance.removeListener(_onYears);
    CycleThemeBus.instance.removeListener(_onThemeChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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
                if (_mode == _CalMode.gregorian)
                  Panel(
                    padding: const EdgeInsets.all(8),
                    child: GregorianMonthGrid(
                      month: _month,
                      today: DateTime.now(),
                      selected: _selected,
                      eventDays: byDay.keys.toSet(),
                      onSelect: (d) => setState(() {
                        _selected = d;
                        if (d.month != _month.month) _month = DateTime(d.year, d.month);
                      }),
                      onMonth: (delta) => setState(() => _month = DateTime(_month.year, _month.month + delta)),
                      onToday: () {
                        final now = DateTime.now();
                        setState(() {
                          _month = DateTime(now.year, now.month);
                          _selected = DateTime(now.year, now.month, now.day);
                        });
                      },
                    ),
                  )
                else if (_mode == _CalMode.equicycle)
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
        ViewFab(
          key: const Key('calendar-import-export'),
          tooltip: 'Import or export',
          icon: Icons.import_export_rounded,
          slot: 1,
          busy: _busy,
          onPressed: _importExportMenu,
        ),
        ViewFab(
          tooltip: 'Add an event',
          icon: Icons.add_rounded,
          onPressed: () => _addEventSheet(context),
        ),
      ],
    );
  }

  /// BI26101810: the tab bar holds the three tabs and nothing else. Import and export live in the secondary FAB.
  Widget _modeAndActionsRow() {
    return SubTabsBar(
      keyPrefix: 'calendar',
      labels: [for (final m in _calModes) _calModeLabel(m)],
      index: _calModes.indexOf(_mode),
      onSelect: (i) {
        setState(() => _mode = _calModes[i]);
        writeTabIndex(AppScope.of(context).db, 'calendar', i);
      },
    );
  }

  /// One secondary FAB above Add: a small menu with Import and Export.
  Future<void> _importExportMenu() async {
    final pick = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: C.panel,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            key: const Key('calendar-import'),
            leading: const Icon(Icons.file_upload_outlined, color: NavTint.fg),
            title: const Text('Import .ics'),
            subtitle: const Text('Add the events in a calendar file'),
            onTap: () => Navigator.pop(ctx, 'import'),
          ),
          ListTile(
            key: const Key('calendar-export'),
            leading: const Icon(Icons.file_download_outlined, color: NavTint.fg),
            title: const Text('Export .ics'),
            subtitle: const Text('Save every event as a calendar file'),
            onTap: () => Navigator.pop(ctx, 'export'),
          ),
        ]),
      ),
    );
    if (pick == 'import') await _importIcs();
    if (pick == 'export') await _exportIcs();
  }

  Widget _equicycleGrid(Map<String, List<Map<String, dynamic>>> byDay) {
    final today = DateTime.now();
    final ctx = _EqContext(today);
    if (ctx.unavailable) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text('Calendar unavailable', style: T.title)),
      );
    }
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _maybeLoadServerTheme(ctx.cycleKey));
    final displayTheme = _serverThemeKey == ctx.cycleKey && _serverTheme != null
        ? _serverTheme!
        : ctx.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
              ctx.stillweek
                  ? 'Stillweek · Day ${ctx.pos!.stillweekDay} · $displayTheme'
                  : 'Cycle ${ctx.cycleNum} · Day ${ctx.dayInCycle} · $displayTheme',
              style: T.title),
        ),
        // BI26100135: the grid itself (cycle and year views, season bands, Stillweek, sun events, moon and rains) is the
        // calendar service's grid, drawn by EquicycleGridView.
        EquicycleGridView(
          byDay: byDay,
          selected: _selected,
          onSelect: (d) => setState(() => _selected = d),
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
                      _plannerBlockPopup(name, '$startClock to $endClock'),
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

  /// Ported from the web's kindColor map (app.js renderDatesPanel).
  static const Map<String, Color> _kindColors = {
    'birthday': C.violet,
    'anniversary': C.green,
    'graduation': C.green,
    'first graduation': C.green,
    'first job': C.blue,
    'first': C.blue,
    'deadline': C.amber,
  };

  /// An explicit `#rrggbb` COLOR wins; otherwise the kind chooses one.
  static Color colorFor(Map<String, dynamic> d) {
    final explicit = fmt.s(d['COLOR']);
    if (RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(explicit)) return Color(int.parse('FF${explicit.substring(1)}', radix: 16));
    return _kindColors[fmt.s(d['KIND']).toLowerCase()] ?? C.text3;
  }

  /// The label shown for a kind (storage keeps the original word).
  static String kindLabel(Map<String, dynamic> d) {
    final k = fmt.s(d['KIND']);
    return k.toLowerCase() == 'first graduation' ? 'Bachelors Graduation' : k;
  }

  static String bigNumber(Map<String, dynamic> d) {
    final since = d['daysSince'] != null;
    final n = fmt.i(since ? d['daysSince'] : d['daysUntil']);
    final s = n.abs().toString();
    final out = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
      out.write(s[i]);
    }
    return '${n < 0 ? '-' : ''}$out';
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return ListenableBuilder(
      listenable: services.store.dates,
      builder: (context, _) {
        final value = fmt.m(services.store.dates.value);
        final upcoming = fmt.lm(value['upcoming']);
        final dates = fmt.lm(value['dates']);

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
            // The soonest three, hot (amber, a real heads-up) inside a week.
            if (upcoming.isNotEmpty)
              Padding(
                key: const Key('key-dates-soon'),
                padding: const EdgeInsets.only(bottom: 10),
                child: Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final u in upcoming.take(3))
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        border: Border.all(color: fmt.i(u['days'], 99) <= 7 ? C.amber.withValues(alpha: 0.5) : C.border),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        '${fmt.s(u['title'])} · ${fmt.s(u['label'])} ${_daysBadge(fmt.i(u['days'], -1))}',
                        style: T.tiny.copyWith(color: fmt.i(u['days'], 99) <= 7 ? C.amber : C.text2),
                      ),
                    ),
                ]),
              ),
            if (dates.isEmpty)
              const Panel(
                child: Text(
                  'Nothing counted yet. Add the dates a life gets measured '
                  'against - birthdays, anniversaries, the day something '
                  'started - and the counters take it from there.',
                ),
              )
            else
              LayoutBuilder(builder: (context, box) {
                const gap = 8.0;
                final w = (box.maxWidth - gap) / 2;
                return Wrap(spacing: gap, runSpacing: gap, children: [
                  for (final d in dates) SizedBox(width: w, child: _card(context, d, services)),
                ]);
              }),
          ],
        );
      },
    );
  }

  /// One counter, as on the web console: tinted by its colour, the kind, the big number, "days since or until", the
  /// title, the date, and the next milestone under a thin rule.
  Widget _card(BuildContext context, Map<String, dynamic> d, AppServices services) {
    final c = colorFor(d);
    final since = d['daysSince'] != null;
    final ms = fmt.lm(d['milestones']);
    final next = ms.isEmpty ? null : ms.first;
    final turns = fmt.i(d['yearsTurning']);
    final id = fmt.s(d['ID']);
    final title = fmt.s(d['TITLE']);
    return Container(
      key: Key('key-date-card-$id'),
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 10),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        border: Border.all(color: c.withValues(alpha: 0.33)),
        borderRadius: BorderRadius.circular(Sz.rMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(kindLabel(d).toUpperCase(),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: T.label.copyWith(color: c, fontSize: 9.5)),
            ),
            InkWell(
              key: Key('delete-date-$id'),
              borderRadius: BorderRadius.circular(12),
              onTap: () async {
                final ok = await confirmDeleteDate(context, id, title);
                if (ok) services.store.dates.refresh();
              },
              child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.close_rounded, size: 14, color: C.text3)),
            ),
          ]),
          Text(bigNumber(d), key: Key('key-date-number-$id'), style: T.headline.copyWith(fontSize: 26, fontWeight: FontWeight.w700, color: C.text)),
          Text('days ${since ? 'since' : 'until'}', style: T.tiny.copyWith(color: C.text3)),
          const SizedBox(height: 6),
          Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: T.w600(T.small)),
          const SizedBox(height: 2),
          Text.rich(TextSpan(children: [
            TextSpan(text: fmt.s(d['DATE']), style: T.monoSmall.copyWith(color: C.text3)),
            if (turns > 0)
              TextSpan(text: ' · turns $turns in ${fmt.i(d['daysToNext'])}d', style: T.monoSmall.copyWith(color: c)),
          ])),
          if (next != null) ...[
            const SizedBox(height: 6),
            Container(height: 1, color: c.withValues(alpha: 0.27)),
            const SizedBox(height: 5),
            Text.rich(
              TextSpan(children: [
                TextSpan(text: fmt.s(next['label']), style: T.tiny.copyWith(color: c)),
                TextSpan(
                  text: ' · ${fmt.i(next['days']) == 0 ? 'today' : '${fmt.i(next['days'])}d'} · ${fmt.s(next['date'])}',
                  style: T.tiny.copyWith(color: C.text3),
                ),
              ]),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  String _daysBadge(int days) {
    if (days < 0) return '-';
    if (days == 0) return 'today';
    return 'in ${days}d';
  }
}
