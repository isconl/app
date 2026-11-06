import 'package:flutter/material.dart';

import '../../../theme.dart';

/// One cell of a [DashboardGrid]: the tile and how many columns it spans.
class DashItem {
  const DashItem(this.child, {this.span = 1});
  final Widget child;
  final int span;
}

/// Two columns on a phone, four from [wideFrom] up. A tile spans one or two
/// columns (never more than the grid has). Rows are as tall as their tallest
/// tile, so tiles in a row line up.
class DashboardGrid extends StatelessWidget {
  const DashboardGrid({super.key, required this.items, this.wideFrom = 600});
  final List<DashItem> items;
  final double wideFrom;

  static int columnsFor(double width, {double wideFrom = 600}) =>
      width >= wideFrom ? 4 : 2;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = columnsFor(c.maxWidth, wideFrom: wideFrom);
        const gap = Sz.gap;
        final cell = (c.maxWidth - gap * (cols - 1)) / cols;
        final rows = <List<DashItem>>[];
        var row = <DashItem>[];
        var used = 0;
        for (final it in items) {
          final span = it.span.clamp(1, 2).clamp(1, cols);
          if (used + span > cols) {
            rows.add(row);
            row = [];
            used = 0;
          }
          row.add(DashItem(it.child, span: span));
          used += span;
        }
        if (row.isNotEmpty) rows.add(row);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var r = 0; r < rows.length; r++) ...[
              if (r > 0) const SizedBox(height: gap),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < rows[r].length; i++) ...[
                      if (i > 0) const SizedBox(width: gap),
                      SizedBox(
                        width:
                            cell * rows[r][i].span +
                            gap * (rows[r][i].span - 1),
                        child: rows[r][i].child,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
