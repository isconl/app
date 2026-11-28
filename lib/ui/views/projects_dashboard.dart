import 'package:flutter/material.dart';

import '../../theme.dart';
import '../widgets/dashboard/dashboard.dart';
import 'projects_dash_model.dart';

/// BI26100129: the Projects landing as a dashboard. Tiles with no live
/// source yet say so; none shows an invented number. [onOpenSub] opens the
/// sibling sub-tab (Corporate 1, Products 2, Platforms 3).
class ProjectsDashboard extends StatelessWidget {
  const ProjectsDashboard({super.key, required this.dash, this.onOpenSub, this.updatedAt});
  final ProjectsDash dash;
  final void Function(int sub)? onOpenSub;
  final DateTime? updatedAt;

  static const _colors = {
    'Practice': C.green,
    'Corporate': C.cyan,
    'Product': C.amber,
    'Platform': C.violet,
    'Other': C.text3,
  };

  @override
  Widget build(BuildContext context) {
    return DashboardGrid(items: [
      const DashItem(StatTile(label: 'Diagnostic bookings, this week', value: '0', caption: 'booking not live yet')),
      const DashItem(StatTile(label: 'Open leads', value: null)),
      DashItem(StatTile(
        label: 'Projects',
        value: '${dash.total}',
        updatedAt: updatedAt,
        onTap: onOpenSub == null ? null : () => onOpenSub!(2),
      )),
      const DashItem(StatTile(label: 'Practice pages live', value: null)),
      DashItem(
        DashTile(
          label: 'Portfolio by category',
          updatedAt: updatedAt,
          child: BarStrip(segments: [
            for (final e in dash.byCategory.entries)
              BarSegment(e.key, e.value.toDouble(), _colors[e.key] ?? C.text3),
          ]),
        ),
        span: 2,
      ),
      DashItem(
        DashTile(
          label: 'Practice funnel, this month',
          child: const DashEmpty(text: 'Needs the booking metrics'),
        ),
        span: 2,
      ),
      DashItem(
        DashTile(
          label: 'Slate rows closed, 4 weeks',
          child: const DashEmpty(text: 'Needs the Slate counts'),
        ),
        span: 2,
      ),
      DashItem(
        DashTile(
          label: 'Most active this week',
          child: const DashEmpty(text: 'Needs the Slate counts'),
        ),
        span: 2,
      ),
    ]);
  }
}
