import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/day_blocks.dart';
import '../../util/cycle_theme_bus.dart';
import '../../util/equicycle.dart';
import 'equicycle_grid_view.dart';
import '../../util/key_dates.dart';
import '../../util/equicycle_grid.dart';
import '../../util/fmt.dart' as fmt;
import '../widgets/common.dart';
import '../widgets/parity3b_widgets.dart';
import '../widgets/month_grid.dart';
import '../widgets/space_header.dart';
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
    return ValueListenableBuilder<SpaceNav>(
      valueListenable: SpaceNavMode.mode,
      builder: (context, navMode, _) {
        return Stack(
          children: [
            // BI26102890 (Sconl, 30 Oct 2026: "the calendar space, i also want it using the rail"): the three modes are the
            // rail's destinations (Equicycle, Month, Planner), Overview is the agenda, Activity is laid on by the manifest.
            if (navMode == SpaceNav.rail)
              SpaceView(
                space: 'calendar',
                showSearch: false,
                tabs: [
                  SpaceTab('Overview', _calendarBody(context, null)),
                  SpaceTab('Equicycle', _calendarBody(context, _CalMode.equicycle)),
                  SpaceTab('Gregorian', _calendarBody(context, _CalMode.gregorian)),
                  SpaceTab('Planner', _calendarBody(context, _CalMode.planner)),
                ],
              )
            else
              SnapshotView(
                snapshot: services.store.calendar,
                builder: (context, data) {
                  final events = fmt.lm(fmt.m(data)['events']);
                  final byDay = <String, List<Map<String, dynamic>>>{};
                  for (final e in events) {
                    final day = fmt.s(e['date']);
                    if (day.isNotEmpty) byDay.putIfAbsent(day, () => []).add(e);
                  }
                  _addKeyDates(context, byDay);
                  return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _modeAndActionsRow(),
                        const SizedBox(height: 8),
                        _calendarGridAndDetails(context, _mode, byDay),
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
      },
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

  /// BI26111595: every key date is in the calendar as an event (a year back to a year ahead), worked out on the phone,
  /// so the grids show its dot and the day list shows it, offline too.
  void _addKeyDates(BuildContext context, Map<String, List<Map<String, dynamic>>> byDay) {
    final dates = fmt.lm(fmt.m(AppScope.of(context).store.dates.value)['dates']);
    if (dates.isEmpty) return;
    final now = DateTime.now();
    final kd = keyDateEvents(dates, DateTime(now.year - 1, now.month, 1), DateTime(now.year + 1, now.month + 1, 0));
    kd.forEach((day, list) => byDay.putIfAbsent(day, () => []).addAll(list));
  }

  /// BI26111593: the Equicycle marks on a Gregorian day, from whichever Equicycle year holds it (a year can start in the
  /// previous Gregorian year). Empty while the grid is not loaded.
  List<EqDayMark> _marksOn(String iso) {
    final y = int.tryParse(iso.substring(0, 4)) ?? DateTime.now().year;
    for (final year in [y, y - 1, y + 1]) {
      final g = EquicycleGrids.instance.gridFor(year);
      if (g != null && g.cellFor(iso) != null) return g.marksFor(iso);
    }
    return const [];
  }

  /// BI26111592: no scroll view of its own here. [SnapshotView] already scrolls with the page gutter (14 px); a second
  /// padded scroll view inside it doubled the gutter to 28 px, so the calendar cards were narrower than every other view.
  /// One calendar destination: a mode's grid with the selected day's events and the key dates, or (mode null) the
  /// agenda of the coming two weeks.
  Widget _calendarBody(BuildContext context, _CalMode? mode) {
    final services = AppScope.of(context);
    return SnapshotView(
      snapshot: services.store.calendar,
      builder: (context, data) {
        final events = fmt.lm(fmt.m(data)['events']);
        final byDay = <String, List<Map<String, dynamic>>>{};
        for (final e in events) {
          final day = fmt.s(e['date']);
          if (day.isNotEmpty) byDay.putIfAbsent(day, () => []).add(e);
        }
        _addKeyDates(context, byDay);
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (mode == null) _agenda(byDay) else _calendarGridAndDetails(context, mode, byDay),
            ],
          );
      },
    );
  }

  Widget _calendarGridAndDetails(
      BuildContext context, _CalMode mode, Map<String, List<Map<String, dynamic>>> byDay) {
    final selKey = _selected == null ? '' : fmt.isoDate(_selected!);
    final dayEvents = byDay[selKey] ?? const [];
    final dayMarks = _selected == null ? const <EqDayMark>[] : _marksOn(selKey);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (mode == _CalMode.gregorian)
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
        else if (mode == _CalMode.equicycle)
          Panel(
            padding: const EdgeInsets.all(8),
            child: _equicycleGrid(byDay),
          )
        else
          Panel(
            padding: const EdgeInsets.all(4),
            child: _plannerGrid(byDay),
          ),
        if (mode != _CalMode.planner) ...[
          SectionLabel(_selected == null
              ? 'Events'
              : fmt.weekdayDate(_selected!)),
          // BI26111593: the day's marks (the rains, a solstice or equinox, the moon) are listed with its events, each with
          // the dot colour it wears in the grid.
          for (final m in dayMarks)
            Padding(
              key: Key('day-mark-${m.kind}'),
              padding: const EdgeInsets.only(bottom: 8),
              child: Panel(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(children: [
                  StatusDot(eqMarkColor(m.kind), size: 8),
                  const SizedBox(width: 10),
                  Expanded(child: Text(m.label, style: T.body2)),
                ]),
              ),
            ),
          if (dayEvents.isEmpty && dayMarks.isEmpty)
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
                            color: fmt.s(e['source']) == 'keydate'
                                ? keyDateColor(fmt.s(e['kind']))
                                : fmt.s(e['source']) == 'microsoft'
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
  }

  /// The Overview: every event from today through the next fourteen days, by day.
  Widget _agenda(Map<String, List<Map<String, dynamic>>> byDay) {
    final today = DateTime.now();
    final days = [for (var i = 0; i < 15; i++) DateTime(today.year, today.month, today.day + i)];
    final rows = <Widget>[];
    for (final d in days) {
      final list = byDay[fmt.isoDate(d)] ?? const [];
      if (list.isEmpty) continue;
      rows.add(SectionLabel(fmt.weekdayDate(d)));
      for (final e in list) {
        rows.add(Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Panel(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Text([fmt.s(e['time']), fmt.s(e['title'])].where((x) => x.isNotEmpty).join('  '), style: T.body2),
          ),
        ));
      }
    }
    if (rows.isEmpty) {
      return const Panel(key: Key('calendar-agenda-empty'), child: Text('Nothing in the next two weeks. Tap + to add an event.'));
    }
    return Column(key: const Key('calendar-agenda'), crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
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
  /// BI26111595: adding a date is a picker, not typing YYYY-MM-DD; a birthday can be saved without its year; and the
  /// sheet says when the date next falls before it is saved.
  Future<void> _addDateSheet(BuildContext context) {
    final title = TextEditingController();
    final who = TextEditingController();
    var kind = 'birthday';
    var recurs = true;
    var noYear = false;
    DateTime? picked;
    final services = AppScope.of(context);
    var listening = false;
    const kinds = ['birthday', 'anniversary', 'first job', 'first graduation', 'first', 'deadline'];

    return showFormSheet(
      context,
      title: 'Count a date',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          if (!listening) {
            listening = true;
            title.addListener(() => setSheet(() {}));
          }
          // A birthday without a known year is stored in 2000, which the app never shows as a year.
          final stored = picked == null ? null : (noYear && kind == 'birthday' ? DateTime(2000, picked!.month, picked!.day) : picked!);
          final preview = stored == null
              ? null
              : keyDateFrom({
                  'ID': 'new', 'TITLE': title.text, 'KIND': kind, 'RECURS': recurs ? 'yearly' : '-',
                  'DATE': fmt.isoDate(stored),
                }, DateTime.now());
          final ready = title.text.trim().isNotEmpty && stored != null;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Field(
                  label: 'What is it',
                  controller: title,
                  hint: "Olive's birthday, first day at Viva",
                  autofocus: true,
                  ),
              const SizedBox(height: 6),
              Text('Kind', style: T.small.copyWith(color: C.text3)),
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final k in kinds)
                  ChoiceChip(
                    key: Key('date-kind-$k'),
                    label: Text(k == 'first graduation' ? 'graduation' : k),
                    selected: kind == k,
                    selectedColor: keyDateColor(k).withValues(alpha: 0.25),
                    side: BorderSide(color: keyDateColor(k).withValues(alpha: 0.6)),
                    onSelected: (_) => setSheet(() {
                      kind = k;
                      recurs = k == 'birthday' || k == 'anniversary' ? true : recurs;
                    }),
                  ),
              ]),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                key: const Key('date-pick'),
                icon: const Icon(Icons.event_rounded, size: 18),
                label: Text(picked == null
                    ? 'Pick the date'
                    : (noYear && kind == 'birthday'
                        ? '${picked!.day} ${fmt.monthsFull[picked!.month - 1]}'
                        : '${picked!.day} ${fmt.monthsFull[picked!.month - 1]} ${picked!.year}')),
                onPressed: () async {
                  final now = DateTime.now();
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: picked ?? now,
                    firstDate: DateTime(1900),
                    lastDate: DateTime(now.year + 30),
                  );
                  if (d != null) setSheet(() => picked = d);
                },
              ),
              if (kind == 'birthday')
                Row(children: [
                  Expanded(child: Text("I don't know the year", style: T.body2)),
                  Switch(key: const Key('date-no-year'), value: noYear, onChanged: (v) => setSheet(() => noYear = v)),
                ]),
              Field(label: 'Whose (optional)', controller: who, hint: 'leave blank for your own'),
              if (kind != 'birthday' && kind != 'anniversary')
                Row(children: [
                  Expanded(child: Text('Repeats every year', style: T.body2)),
                  Switch(value: recurs, onChanged: (v) => setSheet(() => recurs = v)),
                ]),
              if (preview != null)
                Padding(
                  key: const Key('date-preview'),
                  padding: const EdgeInsets.only(top: 6, bottom: 4),
                  child: Text(
                    preview.daysSince != null
                        ? '${_thousandsWord(preview.daysSince!)} days since. Next: ${preview.what} ${daysAwayWords(preview.daysAway)}.'
                        : 'Next: ${preview.next.day} ${fmt.monthsFull[preview.next.month - 1]}, ${daysAwayWords(preview.daysAway)}'
                            '${preview.what.startsWith('turns') ? ' (${preview.what})' : ''}.',
                    style: T.small.copyWith(color: keyDateColor(kind), fontWeight: FontWeight.w600),
                  ),
                ),
              const SizedBox(height: 10),
              FilledButton(
                key: const Key('date-save'),
                onPressed: !ready
                    ? null
                    : () async {
                        Navigator.pop(ctx);
                        final res = await services.mutations.addDate({
                          'title': title.text.trim(),
                          'date': fmt.isoDate(stored),
                          'kind': kind,
                          'recurs': recurs,
                          if (who.text.trim().isNotEmpty) 'who': who.text.trim(),
                        });
                        if (!context.mounted) return;
                        if (!res.ok) {
                          toast(context, res.error!, error: true);
                        } else {
                          toast(context, res.queued ? 'Saved on the phone; it syncs when the server answers' : 'Counting ${title.text.trim()}');
                          services.store.dates.refresh();
                        }
                      },
                child: const Text('Count this date'),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _thousandsWord(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
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

  /// An explicit `#rrggbb` COLOR wins; otherwise the kind chooses one.
  static Color colorFor(Map<String, dynamic> d) {
    final explicit = fmt.s(d['COLOR']);
    if (RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(explicit)) return Color(int.parse('FF${explicit.substring(1)}', radix: 16));
    return keyDateColor(fmt.s(d['KIND']));
  }

  /// The label shown for a kind (storage keeps the original word).
  static String kindLabel(Map<String, dynamic> d) {
    final k = fmt.s(d['KIND']);
    return k.toLowerCase() == 'first graduation' ? 'Bachelors Graduation' : k;
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return ListenableBuilder(
      listenable: services.store.dates,
      builder: (context, _) {
        final value = fmt.m(services.store.dates.value);
        final dates = fmt.lm(value['dates']);
        // BI26111595: three, chosen on the phone each day (works offline): the most relevant wide, two side by side.
        final picked = pickKeyDates(dates, DateTime.now());

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(child: SectionLabel('Key dates')),
                if (dates.length > picked.length)
                  TextButton(
                    key: const Key('key-dates-all'),
                    onPressed: () => _allDatesSheet(context, dates, services),
                    child: Text('All ${dates.length}'),
                  ),
                TextButton(
                  onPressed: onAdd,
                  child: const Text('Add a date'),
                ),
              ],
            ),
            if (dates.isEmpty)
              const Panel(
                child: Text(
                  'Nothing counted yet. Add the dates a life gets measured '
                  'against: birthdays, anniversaries, the day something '
                  'started. The counters take it from there.',
                ),
              )
            else ...[
              _card(context, picked.first, services, wide: true),
              if (picked.length > 1) ...[
                const SizedBox(height: 8),
                IntrinsicHeight(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(child: _card(context, picked[1], services)),
                    const SizedBox(width: 8),
                    Expanded(child: picked.length > 2 ? _card(context, picked[2], services) : const SizedBox()),
                  ]),
                ),
              ],
            ],
          ],
        );
      },
    );
  }

  /// Every counted date, soonest first, each with Stop counting.
  void _allDatesSheet(BuildContext context, List<Map<String, dynamic>> dates, AppServices services) {
    final all = pickKeyDates(dates, DateTime.now(), count: dates.length);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.bgRaised,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
            children: [
              Text('All key dates', style: T.title),
              const SizedBox(height: 8),
              for (final k in all)
                ListTile(
                  key: Key('all-dates-${k.id}'),
                  contentPadding: EdgeInsets.zero,
                  leading: StatusDot(colorFor(k.raw), size: 10),
                  title: Text(k.title, style: T.w600(T.body2)),
                  subtitle: Text('${kindLabel(k.raw)} · ${k.dayMonth(withYear: true)} · ${k.what} ${daysAwayWords(k.daysAway)}',
                      style: T.small.copyWith(color: C.text3)),
                  trailing: TextButton(
                    key: Key('stop-counting-${k.id}'),
                    onPressed: () async {
                      final ok = await confirmDeleteDate(ctx, k.id, k.title);
                      if (ok) {
                        services.store.dates.refresh();
                        if (ctx.mounted) Navigator.pop(ctx);
                      }
                    },
                    child: const Text('Stop counting'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// One counter, tinted by its kind's colour. The big number is days to the next occurrence (or days since a
  /// one-off that has passed), with its label set large enough to read at a glance (Sconl, 15 Nov 2026).
  Widget _card(BuildContext context, KeyDate k, AppServices services, {bool wide = false}) {
    final d = k.raw;
    final c = colorFor(d);
    final id = k.id;
    final today = k.daysAway == 0;
    final since = k.daysSince != null;
    final number = today ? 'Today' : _thousandsOf(since ? k.daysSince! : k.daysAway);
    final unit = today ? '' : since ? 'days since' : (k.daysAway == 1 ? 'day to' : 'days to');
    final target = since ? '' : (k.isBirthday ? (k.what == 'birthday' ? 'birthday' : k.what) : k.what);
    final numberBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(number,
            key: Key('key-date-number-$id'),
            style: T.headline.copyWith(fontSize: wide ? 36 : 28, fontWeight: FontWeight.w700, color: C.text, height: 1.05)),
        if (unit.isNotEmpty)
          Text('$unit${target.isEmpty || target == k.title ? '' : ' $target'}'.toUpperCase(),
              key: Key('key-date-unit-$id'),
              style: T.label.copyWith(color: c, fontSize: wide ? 12.5 : 11, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
      ],
    );
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(k.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: T.w600(wide ? T.body2 : T.small)),
        const SizedBox(height: 2),
        Text(
          since
              ? '${k.dayMonth(withYear: true)} · ${k.what} ${daysAwayWords(k.daysAway)}'
              : '${k.dayMonth(withYear: k.isBirthday ? false : true)}${k.isBirthday && k.yearKnown ? ' · born ${k.origin.year}' : ''}',
          style: T.monoSmall.copyWith(color: C.text3),
        ),
      ],
    );
    return Container(
      key: Key('key-date-card-$id'),
      padding: EdgeInsets.fromLTRB(12, 8, 6, wide ? 12 : 10),
      decoration: BoxDecoration(
        color: c.withValues(alpha: today ? 0.16 : 0.08),
        border: Border.all(color: c.withValues(alpha: today ? 0.7 : 0.33), width: today ? 1.5 : 1),
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
                final ok = await confirmDeleteDate(context, id, k.title);
                if (ok) services.store.dates.refresh();
              },
              child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.close_rounded, size: 14, color: C.text3)),
            ),
          ]),
          if (wide)
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              numberBlock,
              const SizedBox(width: 14),
              Expanded(child: details),
            ])
          else ...[
            numberBlock,
            const SizedBox(height: 6),
            details,
          ],
        ],
      ),
    );
  }

  static String _thousandsOf(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

}
