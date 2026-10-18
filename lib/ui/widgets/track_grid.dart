import 'package:flutter/material.dart';

import '../views/learning.dart';

/// BI26101803: the Tracks tab as a deliberate rhythm. In track order: a full-width tile, then two square tiles side by
/// side, then a full-width tile, and so on. A square left on its own at the end stretches to full width.
///
/// Returns each tile's span: 2 is full width, 1 is a half-width square.
List<int> trackSpans(int n) {
  final out = <int>[];
  for (var i = 0; i < n; i++) {
    final pos = i % 3;
    if (pos == 0) {
      out.add(2);
    } else if (pos == 1 && i == n - 1) {
      out.add(2); // a lone square would leave a hole beside it
    } else {
      out.add(1);
    }
  }
  return out;
}

class TrackGrid extends StatelessWidget {
  const TrackGrid({super.key, required this.groups, required this.coursesFor});

  final List<LearningGroup> groups;
  final List<Map<String, dynamic>> Function(LearningGroup) coursesFor;

  static const double gap = 8;

  @override
  Widget build(BuildContext context) {
    final spans = trackSpans(groups.length);
    return LayoutBuilder(builder: (context, c) {
      final full = c.maxWidth;
      final half = (full - gap) / 2;
      // A square is about 1:1 and a wide tile about 2.2:1. These are minimums: a tile with more to say grows, and the
      // two squares in a row grow together.
      final squareMin = half;
      final wideMin = full / 2.2;
      Widget tile(int i, {required bool wide}) => KeyedSubtree(
            key: Key('track-tile-$i'),
            child: TrackCard(group: groups[i], courses: coursesFor(groups[i]), wide: wide),
          );

      final rows = <Widget>[];
      var i = 0;
      while (i < groups.length) {
        if (spans[i] == 2) {
          rows.add(ConstrainedBox(constraints: BoxConstraints(minHeight: wideMin), child: tile(i, wide: true)));
          i += 1;
        } else {
          rows.add(ConstrainedBox(
            constraints: BoxConstraints(minHeight: squareMin),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: tile(i, wide: false)),
                  const SizedBox(width: gap),
                  Expanded(child: i + 1 < groups.length ? tile(i + 1, wide: false) : const SizedBox.shrink()),
                ],
              ),
            ),
          ));
          i += 2;
        }
        if (i < groups.length) rows.add(const SizedBox(height: gap));
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
    });
  }
}
