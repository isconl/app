import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../theme.dart';
import 'dash_tile.dart';

/// One coloured share of a ring.
class RingArc {
  const RingArc(this.value, this.color);
  final double value;
  final Color color;
}

/// Progress as a ring: up to three coloured arcs against a [total], with text
/// in the centre. Anything past three arcs is ignored; a zero total draws an
/// empty track.
class RingGauge extends StatelessWidget {
  const RingGauge({
    super.key,
    required this.arcs,
    required this.total,
    this.center,
    this.caption,
    this.size = 84,
  });
  final List<RingArc> arcs;
  final double total;
  final String? center;
  final String? caption;
  final double size;

  @override
  Widget build(BuildContext context) {
    final used = arcs.take(3).toList();
    final sum = used.fold<double>(
      0,
      (a, b) => a + b.value.clamp(0, double.infinity),
    );
    final rest = (total - sum).clamp(0, double.infinity).toDouble();
    final sections = [
      for (final a in used)
        if (a.value > 0)
          PieChartSectionData(
            value: a.value,
            color: a.color,
            radius: 8,
            showTitle: false,
          ),
      PieChartSectionData(
        value: (sum == 0 && rest == 0) ? 1 : rest,
        color: C.surface,
        radius: 8,
        showTitle: false,
      ),
    ];
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              sectionsSpace: 1.5,
              centerSpaceRadius: size / 2 - 8,
              startDegreeOffset: -90,
              sections: sections,
              pieTouchData: PieTouchData(enabled: false),
            ),
            duration: Duration.zero,
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (center != null)
                Text(center!, style: T.title.copyWith(fontFeatures: kTabular)),
              if (caption != null) Text(caption!, style: T.tiny),
            ],
          ),
        ],
      ),
    );
  }
}
