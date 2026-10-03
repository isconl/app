import 'package:flutter/material.dart';

import '../../../theme.dart';
import 'dash_tile.dart';
import 'sparkline.dart';

/// A big number, its label, a delta against the previous period (green when
/// good, amber when not) and an optional sparkline.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.delta,
    this.deltaGoodWhenUp = true,
    this.trend = const [],
    this.onTap,
    this.updatedAt,
    this.error,
  });

  final String label;

  /// Null shows the empty state.
  final String? value;
  final String? unit;

  /// Change since the previous period. Zero shows as flat.
  final num? delta;
  final bool deltaGoodWhenUp;
  final List<double> trend;
  final VoidCallback? onTap;
  final DateTime? updatedAt;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return DashTile(
      label: label,
      onTap: onTap,
      updatedAt: updatedAt,
      error: error,
      child: value == null
          ? const DashEmpty()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: Text(
                        value!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: T.headline.copyWith(
                          fontSize: 26,
                          fontFeatures: kTabular,
                        ),
                      ),
                    ),
                    if (unit != null) ...[
                      const SizedBox(width: 4),
                      Text(unit!, style: T.small.copyWith(color: C.text3)),
                    ],
                    const Spacer(),
                    if (delta != null) _Delta(delta!, deltaGoodWhenUp),
                  ],
                ),
                if (trend.length > 1) ...[
                  const SizedBox(height: 6),
                  Sparkline(
                    values: trend,
                    color: _deltaColor(delta, deltaGoodWhenUp),
                  ),
                ],
              ],
            ),
    );
  }
}

Color _deltaColor(num? d, bool goodWhenUp) {
  if (d == null || d == 0) return C.green;
  return (d > 0) == goodWhenUp ? C.green : C.amber;
}

class _Delta extends StatelessWidget {
  const _Delta(this.delta, this.goodWhenUp);
  final num delta;
  final bool goodWhenUp;
  @override
  Widget build(BuildContext context) {
    final color = delta == 0 ? C.text3 : _deltaColor(delta, goodWhenUp);
    final arrow = delta == 0 ? '→' : (delta > 0 ? '↑' : '↓');
    final n = delta.abs();
    final txt = n == n.roundToDouble()
        ? n.toInt().toString()
        : n.toStringAsFixed(1);
    return Text(
      '$arrow $txt',
      style: T.small.copyWith(
        color: color,
        fontFeatures: kTabular,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
