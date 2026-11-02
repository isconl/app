import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../theme.dart';
import 'dash_tile.dart';

/// One category's colour and name in a [StackedBars] chart.
class BarSeries {
  const BarSeries(this.name, this.color);
  final String name;
  final Color color;
}

/// Bars by day (7 or 30), each stacked by category. [days] holds one list per
/// day, one value per series, in series order. All-zero data shows the empty
/// state.
class StackedBars extends StatelessWidget {
  const StackedBars({
    super.key,
    required this.series,
    required this.days,
    this.dayLabels,
    this.height = 70,
  });
  final List<BarSeries> series;
  final List<List<double>> days;
  final List<String>? dayLabels;
  final double height;

  @override
  Widget build(BuildContext context) {
    double totalOf(List<double> d) =>
        d.fold<double>(0, (a, b) => a + (b > 0 ? b : 0));
    final top = days.isEmpty
        ? 0.0
        : days.map(totalOf).reduce((a, b) => a > b ? a : b);
    if (top <= 0) return const DashEmpty();
    final thin = days.length > 14;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: height,
          child: BarChart(
            BarChartData(
              maxY: top * 1.05,
              alignment: BarChartAlignment.spaceBetween,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: const FlTitlesData(show: false),
              barTouchData: BarTouchData(enabled: false),
              barGroups: [
                for (var i = 0; i < days.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: totalOf(days[i]),
                        width: thin ? 5 : 14,
                        borderRadius: BorderRadius.circular(2),
                        rodStackItems: _stack(days[i]),
                      ),
                    ],
                  ),
              ],
            ),
            duration: Duration.zero,
          ),
        ),
        if (dayLabels != null && dayLabels!.length == days.length && !thin) ...[
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final l in dayLabels!)
                Text(l, style: T.tiny.copyWith(fontSize: 9)),
            ],
          ),
        ],
        const SizedBox(height: 4),
        Wrap(
          spacing: 10,
          children: [
            for (final s in series)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: s.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(s.name, style: T.tiny),
                ],
              ),
          ],
        ),
      ],
    );
  }

  List<BarChartRodStackItem> _stack(List<double> d) {
    final out = <BarChartRodStackItem>[];
    var from = 0.0;
    for (var i = 0; i < series.length && i < d.length; i++) {
      final v = d[i] > 0 ? d[i] : 0.0;
      if (v == 0) continue;
      out.add(BarChartRodStackItem(from, from + v, series[i].color));
      from += v;
    }
    return out;
  }
}
