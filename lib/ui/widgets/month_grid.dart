import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme.dart';
import '../../util/fmt.dart' as fmt;

/// The ISO 8601 week number of [d] (weeks start on Monday; week 1 holds the first Thursday).
int isoWeek(DateTime d) {
  final day = DateTime.utc(d.year, d.month, d.day);
  final thursday = day.add(Duration(days: 4 - (day.weekday == DateTime.sunday ? 7 : day.weekday)));
  final jan1 = DateTime.utc(thursday.year, 1, 1);
  return (thursday.difference(jan1).inDays ~/ 7) + 1;
}

/// The six Sunday-first weeks that cover [month], as seven dates each.
List<List<DateTime>> monthWeeks(DateTime month) {
  final first = DateTime(month.year, month.month, 1);
  final start = DateTime(first.year, first.month, 1 - (first.weekday % 7));
  return [
    for (var w = 0; w < 6; w++) [for (var d = 0; d < 7; d++) DateTime(start.year, start.month, start.day + w * 7 + d)],
  ];
}

/// BI26092632: the Gregorian month in the web Hub calendar's style. A header with
/// the selected weekday and full date, a `‹ Month ›` row, then eight columns: an
/// ISO week chip and Sunday to Saturday. Today is a filled green circle; days
/// from the neighbouring months are muted; event days carry a small dot.
/// Swiping the grid changes the month (the grid takes the horizontal gesture
/// before the sub-tab swipe does).
class GregorianMonthGrid extends StatelessWidget {
  const GregorianMonthGrid({
    super.key,
    required this.month,
    required this.today,
    required this.selected,
    required this.eventDays,
    required this.onSelect,
    required this.onMonth,
    required this.onToday,
  });

  final DateTime month;
  final DateTime today;
  final DateTime? selected;

  /// ISO dates (YYYY-MM-DD) that have at least one event.
  final Set<String> eventDays;
  final void Function(DateTime day) onSelect;

  /// +1 or -1.
  final void Function(int delta) onMonth;
  final VoidCallback onToday;

  bool _same(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final head = selected ?? today;
    final weeks = monthWeeks(month);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      GestureDetector(
        key: const Key('cal-head'),
        behavior: HitTestBehavior.opaque,
        onTap: onToday,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(fmt.weekdaysFull[head.weekday - 1], style: T.small.copyWith(color: C.text3)),
            Text('${fmt.monthsFull[head.month - 1]} ${head.day} ${head.year}',
                style: T.headline.copyWith(color: C.text2, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
      Row(children: [
        IconButton(
          key: const Key('cal-prev'),
          icon: const Icon(Icons.chevron_left_rounded, color: C.text2),
          onPressed: () => onMonth(-1),
        ),
        Expanded(child: Center(child: Text(fmt.monthsFull[month.month - 1], style: T.title))),
        IconButton(
          key: const Key('cal-next'),
          icon: const Icon(Icons.chevron_right_rounded, color: C.text2),
          onPressed: () => onMonth(1),
        ),
      ]),
      GestureDetector(
        key: const Key('cal-grid'),
        behavior: HitTestBehavior.opaque,
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v <= -200) {
            HapticFeedback.selectionClick();
            onMonth(1);
          } else if (v >= 200) {
            HapticFeedback.selectionClick();
            onMonth(-1);
          }
        },
        child: Column(children: [
          Row(children: [
            const Expanded(child: SizedBox.shrink()),
            for (final (i, wd) in ['S', 'M', 'T', 'W', 'T', 'F', 'S'].indexed)
              Expanded(child: Center(child: Text(wd, style: T.monoSmall.copyWith(color: i == 0 || i == 6 ? C.text2 : C.text3)))),
          ]),
          const SizedBox(height: 4),
          for (final week in weeks)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                Expanded(
                  child: Center(
                    child: Container(
                      key: Key('wk-${isoWeek(week[1])}'),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(Sz.rSm)),
                      child: Text('${isoWeek(week[1])}', style: T.monoSmall.copyWith(color: C.text3)),
                    ),
                  ),
                ),
                for (final day in week) Expanded(child: _cell(day)),
              ]),
            ),
        ]),
      ),
    ]);
  }

  Widget _cell(DateTime day) {
    final inMonth = day.month == month.month;
    final isToday = _same(day, today);
    final isSel = selected != null && _same(day, selected!);
    final weekend = day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;
    final color = isToday
        ? C.text
        : !inMonth
            ? C.text3
            : weekend
                ? C.text2
                : C.text;
    return GestureDetector(
      onTap: () => onSelect(day),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 40,
        child: Center(
          child: Stack(alignment: Alignment.center, children: [
            Container(
              key: isToday ? const Key('cal-today') : null,
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isToday ? C.green : null,
                shape: BoxShape.circle,
                border: isSel && !isToday ? Border.all(color: C.green) : null,
              ),
              child: Text(
                day.day.toString().padLeft(2, '0'),
                style: T.small.copyWith(color: color, fontWeight: inMonth ? FontWeight.w600 : FontWeight.w400, fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ),
            if (eventDays.contains(fmt.isoDate(day)))
              Positioned(bottom: 0, child: Container(width: 4, height: 4, decoration: BoxDecoration(color: isToday ? C.text : C.green, shape: BoxShape.circle))),
          ]),
        ),
      ),
    );
  }
}
