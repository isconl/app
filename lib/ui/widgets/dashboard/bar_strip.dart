import 'package:flutter/material.dart';

import '../../../theme.dart';
import 'dash_tile.dart';

class BarSegment {
  const BarSegment(this.label, this.value, this.color);
  final String label;
  final double value;
  final Color color;
}

/// A horizontal bar showing proportions, with a legend underneath. Zero or
/// negative segments are skipped; no positive segment shows the empty state.
class BarStrip extends StatelessWidget {
  const BarStrip({
    super.key,
    required this.segments,
    this.height = 10,
    this.legend = true,
  });
  final List<BarSegment> segments;
  final double height;
  final bool legend;

  @override
  Widget build(BuildContext context) {
    final live = segments.where((s) => s.value > 0).toList();
    if (live.isEmpty) return const DashEmpty();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(height / 2),
          child: SizedBox(
            height: height,
            child: Row(
              children: [
                for (final s in live)
                  Flexible(
                    flex: (s.value * 1000).round().clamp(1, 1 << 30),
                    child: Container(
                      color: s.color,
                      margin: const EdgeInsets.only(right: 1),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (legend) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 2,
            children: [
              for (final s in live)
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
                    Text(
                      '${s.label} ${_fmt(s.value)}',
                      style: T.tiny.copyWith(fontFeatures: kTabular),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ],
    );
  }
}

String _fmt(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
