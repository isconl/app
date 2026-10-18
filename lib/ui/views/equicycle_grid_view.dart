import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/equicycle.dart';
import '../../util/equicycle_grid.dart';
import '../../util/fmt.dart' as fmt;
import '../widgets/common.dart';

/// Calendar > Equicycle on the phone (BI26100135): a cycle as 4 rows of 7 (D01 always a Sunday), sprint A and B shaded, today
/// lit, the Gregorian date small in every cell; a season band; the Stillweek as its own band in a long year; sun events on their
/// day; moon and rains overlays that can be switched off; and a year view with all 13 cycles in a scrolling column. Everything
/// comes from the calendar service through [EquicycleGrids]; nothing here does calendar arithmetic.
class EquicycleGridView extends StatefulWidget {
  const EquicycleGridView({super.key, required this.byDay, required this.selected, required this.onSelect, this.grids, this.startYear, this.startPage});

  /// Events by `YYYY-MM-DD`, for the dot on a day that has any.
  final Map<String, List<Map<String, dynamic>>> byDay;
  final DateTime? selected;
  final ValueChanged<DateTime> onSelect;

  /// A grid store to read (tests pass their own); the app's shared one by default.
  final EquicycleGrids? grids;

  /// Where to open instead of today's cycle (tests, deep links).
  final int? startYear;
  final int? startPage;

  @override
  State<EquicycleGridView> createState() => _EquicycleGridViewState();
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String _short(String iso) => '${int.parse(iso.substring(8, 10))} ${_months[int.parse(iso.substring(5, 7)) - 1]}';

class _EquicycleGridViewState extends State<EquicycleGridView> {
  int? _year;
  int _page = 1;
  bool _yearView = false;
  bool _moon = true;
  bool _rains = true;

  EquicycleGrids get _store => widget.grids ?? EquicycleGrids.instance;

  @override
  void initState() {
    super.initState();
    _store.addListener(_changed);
  }

  @override
  void dispose() {
    _store.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _initPosition() {
    if (_year != null) return;
    if (widget.startYear != null) {
      _year = widget.startYear;
      _page = widget.startPage ?? 1;
      return;
    }
    final pos = EquicycleYears.instance.positionFor(DateTime.now());
    _year = pos?.year ?? DateTime.now().year;
    _page = pos == null ? 1 : (pos.stillweek ? 14 : pos.cycle);
  }

  void _step(int delta) {
    final next = eqPageStep(_year!, _page, delta, (y) => _store.gridFor(y)?.pages ?? 0);
    setState(() {
      _year = next.year;
      _page = next.page;
    });
  }

  @override
  Widget build(BuildContext context) {
    _initPosition();
    final services = AppScope.of(context);
    final grid = _store.gridFor(_year!);
    // Ask for the year (once; the store ignores a repeat while one is in flight). A year already shown is refreshed too.
    WidgetsBinding.instance.addPostFrameCallback((_) => _store.ensure(services.api, services.db, _year!));
    if (grid == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: _store.failed(_year!)
              ? Text('The calendar service did not answer, and there is no saved copy of this year yet.', style: T.small, textAlign: TextAlign.center)
              : const MiniSpinner(),
        ),
      );
    }
    final page = _page.clamp(1, grid.pages);
    final todayKey = fmt.isoDate(DateTime.now());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _controls(grid, page),
        const SizedBox(height: 6),
        _legend(),
        const SizedBox(height: 8),
        if (_yearView)
          for (var p = 1; p <= grid.pages; p++) _block(grid, p, todayKey, small: true)
        else ...[
          _weekdays(),
          _block(grid, page, todayKey),
        ],
      ],
    );
  }

  /// BI26101810: the Cycle, Year, Moon and Rains chips are selected in the nav's subtle green (NavTint), not the
  /// stronger chip green, so the strip matches the bottom navigation.
  Widget _controls(EqGrid grid, int page) {
    final base = Theme.of(context);
    return Theme(
      data: base.copyWith(
        chipTheme: base.chipTheme.copyWith(
          selectedColor: NavTint.bg,
          checkmarkColor: NavTint.fg,
          labelStyle: base.chipTheme.labelStyle,
          side: WidgetStateBorderSide.resolveWith(
              (states) => BorderSide(color: states.contains(WidgetState.selected) ? NavTint.border : C.border)),
        ),
      ),
      child: _controlsWrap(grid, page),
    );
  }

  Widget _controlsWrap(EqGrid grid, int page) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (!_yearView) ...[
          IconButton(key: const Key('eq-prev'), visualDensity: VisualDensity.compact, icon: const Icon(Icons.chevron_left_rounded), onPressed: () => _step(-1)),
          Text('${grid.year} · ${page == 14 ? 'Stillweek' : 'C${page.toString().padLeft(2, '0')}'} of ${grid.yearLabel}',
              key: const Key('eq-where'), style: T.w600(T.small)),
          IconButton(key: const Key('eq-next'), visualDensity: VisualDensity.compact, icon: const Icon(Icons.chevron_right_rounded), onPressed: () => _step(1)),
        ] else
          Text('Year ${grid.yearLabel}: ${_short(grid.start)} ${grid.start.substring(0, 4)} to ${_short(grid.end)} ${grid.end.substring(0, 4)}', style: T.w600(T.small)),
        TextButton(key: const Key('eq-today'), onPressed: () => setState(() => _year = null), child: const Text('Today')),
        ChoiceChip(key: const Key('eq-view-cycle'), label: const Text('Cycle'), selected: !_yearView, onSelected: (_) => setState(() => _yearView = false)),
        ChoiceChip(key: const Key('eq-view-year'), label: const Text('Year'), selected: _yearView, onSelected: (_) => setState(() => _yearView = true)),
        FilterChip(key: const Key('eq-moon'), label: const Text('Moon'), selected: _moon, onSelected: (v) => setState(() => _moon = v)),
        FilterChip(
          key: const Key('eq-rains'),
          label: Text(grid.rainsLocation.isEmpty ? 'Rains' : 'Rains (${grid.rainsLocation})'),
          selected: _rains,
          onSelected: (v) => setState(() => _rains = v),
        ),
      ],
    );
  }

  Widget _legend() {
    Widget item(Widget leading, String label) => Row(mainAxisSize: MainAxisSize.min, children: [leading, const SizedBox(width: 4), Text(label, style: T.tiny.copyWith(color: C.text3))]);
    Widget swatch(Color c) => Container(width: 10, height: 10, decoration: BoxDecoration(color: c, border: Border.all(color: C.border), borderRadius: BorderRadius.circular(2)));
    return Wrap(spacing: 12, runSpacing: 2, children: [
      item(swatch(C.surface), 'sprint A'),
      item(swatch(C.border.withValues(alpha: 0.5)), 'sprint B'),
      item(const Text('☀', style: TextStyle(fontSize: 11)), 'solstice'),
      item(const Text('◐', style: TextStyle(fontSize: 11)), 'equinox'),
      if (_moon) ...[item(const Text('●', style: TextStyle(fontSize: 11)), 'new moon'), item(const Text('○', style: TextStyle(fontSize: 11)), 'full moon')],
    ]);
  }

  Widget _weekdays() => Row(children: [
        for (final d in const ['S', 'M', 'T', 'W', 'T', 'F', 'S']) Expanded(child: Center(child: Text(d, style: T.monoSmall.copyWith(color: C.text3)))),
      ]);

  Color _seasonTint(String season) => switch (season) {
        '1' => C.greenBg,
        // BI26101810: no yellow in the strip; the second season wears the nav's subtle green like the first.
        '2' => NavTint.bg,
        '3' => const Color(0x22BC8CFF),
        '4' => const Color(0x2258A6FF),
        _ => C.surface,
      };

  Widget _block(EqGrid grid, int page, String todayKey, {bool small = false}) {
    final stillweek = page == 14;
    final cycle = stillweek ? null : grid.cycles[page - 1];
    final days = stillweek ? grid.stillweek! : cycle!.days;
    final season = cycle?.season ?? 'sw';
    final title = stillweek ? 'Stillweek' : 'C${cycle!.cycle.toString().padLeft(2, '0')} · ${cycle.theme}';
    final sub = stillweek
        ? 'belongs to no cycle: rest and review'
        : '${grid.seasonNames[season] ?? ''} · ${_short(cycle!.start)} to ${_short(cycle.end)}';
    final rows = <Widget>[];
    for (var w = 0; w * 7 < days.length; w++) {
      rows.add(Row(children: [
        for (final c in days.skip(w * 7).take(7)) Expanded(child: _cell(c, grid, todayKey, small)),
      ]));
    }
    return Container(
      key: Key(stillweek ? 'eq-band-sw' : 'eq-band-c${cycle!.cycle}'),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(border: Border.all(color: C.border), borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(color: _seasonTint(season), borderRadius: const BorderRadius.vertical(top: Radius.circular(7))),
          child: Row(children: [
            Text(title, style: T.w600(T.small)),
            if (!small) ...[const Spacer(), Flexible(child: Text(sub, style: T.tiny.copyWith(color: C.text3), overflow: TextOverflow.ellipsis))],
          ]),
        ),
        Padding(padding: const EdgeInsets.all(3), child: Column(children: rows)),
      ]),
    );
  }

  Widget _cell(EqCell c, EqGrid grid, String todayKey, bool small) {
    final isToday = c.date == todayKey;
    final isSel = widget.selected != null && fmt.isoDate(widget.selected!) == c.date;
    final items = widget.byDay[c.date] ?? const [];
    final rain = _rains && grid.inRains(c.date);
    final past = c.date.compareTo(todayKey) < 0;
    final date = DateTime.parse(c.date);
    return GestureDetector(
      key: Key('eq-cell-${c.date}'),
      onTap: () => widget.onSelect(date),
      child: Container(
        height: small ? 36 : 56,
        margin: const EdgeInsets.all(1.5),
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
        decoration: BoxDecoration(
          color: isSel ? C.greenBg : isToday ? C.greenBg : (c.sprint == 'B' ? C.border.withValues(alpha: 0.35) : C.surface),
          // A radius needs a uniform border, so the rains are a bar inside the cell, not a thicker bottom edge.
          border: Border.all(color: isToday || isSel ? C.green : C.border),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Opacity(
          opacity: past && !isToday ? 0.62 : 1,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(c.day.toString().padLeft(2, '0'), style: T.w600(small ? T.tiny : T.small).copyWith(color: isToday ? C.greenBright : C.text2)),
            Text(small ? '${date.day}' : '${date.day} ${_months[date.month - 1]}', style: T.monoSmall.copyWith(color: C.text3, fontSize: small ? 7 : 8)),
            if (rain) Container(key: Key('eq-rain-${c.date}'), height: 3, decoration: BoxDecoration(color: const Color(0xFF58A6FF), borderRadius: BorderRadius.circular(2))),
            if (!small)
              SizedBox(
                height: 12,
                child: Row(children: [
                  for (final m in c.markers) Text(m.kind == 'solstice' ? '☀' : '◐', style: const TextStyle(fontSize: 10, color: C.amber)),
                  if (_moon && c.moon != null) Text(c.moon == 'new' ? '●' : '○', style: TextStyle(fontSize: 10, color: c.moon == 'new' ? C.text3 : C.text2)),
                  if (items.isNotEmpty) const Padding(padding: EdgeInsets.only(left: 2), child: StatusDot(C.green, size: 4)),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}
