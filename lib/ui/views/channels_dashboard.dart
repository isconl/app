import 'package:flutter/material.dart';

import '../../theme.dart';
import '../widgets/dashboard/dashboard.dart';
import 'channels_dash_model.dart';

/// BI26100128: the Channels landing as a dashboard. Four stat tiles, unread
/// by source for seven days, the Kanban split and Buffer's next posts. Each
/// tile opens the sub-tab that owns its data via [onOpenView] (a nav view:
/// jira, social). Figures the app cannot compute yet show the empty
/// state rather than a guess.
class ChannelsDashboard extends StatelessWidget {
  const ChannelsDashboard({super.key, required this.dash, this.onOpenView, this.updatedAt});
  final ChannelsDash dash;
  final void Function(String view)? onOpenView;
  final DateTime? updatedAt;

  static const _colors = {
    'Mail': C.cyan,
    'Teams': C.violet,
    'Jira': C.amber,
    'Buffer': C.green,
    'SMS': C.callQuote,
    'Other': C.text3,
  };

  void Function()? _open(String view) => onOpenView == null ? null : () => onOpenView!(view);

  @override
  Widget build(BuildContext context) {
    final age = dash.oldestUnanswered;
    final now = DateTime.now();
    final days = [for (var i = 6; i >= 0; i--) now.subtract(Duration(days: i))];
    const wd = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return DashboardGrid(items: [
      DashItem(StatTile(
        label: 'Unread',
        value: '${dash.unread}',
        delta: dash.unreadDelta,
        deltaGoodWhenUp: false,
        updatedAt: updatedAt,
      )),
      DashItem(StatTile(
        label: 'Oldest unanswered',
        value: age == null ? '–' : ChannelsDash.ageLabel(age),
        unit: age == null ? null : ChannelsDash.ageUnit(age),
        updatedAt: updatedAt,
      )),
      const DashItem(StatTile(label: 'Teams mentions', value: null)),
      DashItem(StatTile(
        label: 'In progress',
        value: '${dash.inProgress}',
        onTap: _open('jira'),
      )),
      DashItem(
        DashTile(
          label: 'New by source, 7 days',
          updatedAt: updatedAt,
          child: StackedBars(
            series: [for (final s in ChannelsDash.sources) BarSeries(s, _colors[s]!)],
            days: [
              for (final d in dash.perDay) [for (final s in ChannelsDash.sources) (d[s] ?? 0).toDouble()],
            ],
            dayLabels: [for (final d in days) wd[d.weekday - 1]],
          ),
        ),
        span: 2,
      ),
      DashItem(
        DashTile(
          label: 'Kanban',
          onTap: _open('jira'),
          child: BarStrip(segments: [
            BarSegment('To do', dash.kanban['To do']!.toDouble(), C.amber),
            BarSegment('Doing', dash.kanban['In progress']!.toDouble(), C.cyan),
            BarSegment('Review', dash.kanban['Review']!.toDouble(), C.violet),
            BarSegment('Done', dash.kanban['Done']!.toDouble(), C.green),
          ]),
        ),
        span: 2,
      ),
      DashItem(
        DashTile(
          label: 'Buffer, next up',
          onTap: _open('social'),
          child: MiniList(
            empty: 'Nothing scheduled',
            items: [for (final p in dash.bufferNext) MiniItem(p.title, p.when)],
          ),
        ),
        span: 2,
      ),
    ]);
  }
}

/// The one-line summary pinned over the list once the dashboard has scrolled away.
class ChannelsSummaryBar extends StatelessWidget {
  const ChannelsSummaryBar({super.key, required this.dash, required this.visible});
  final ChannelsDash dash;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final age = dash.oldestUnanswered;
    final parts = [
      '${dash.unread} unread',
      if (age != null) 'oldest ${ChannelsDash.ageLabel(age)} ${ChannelsDash.ageUnit(age)}',
      '${dash.inProgress} in progress',
    ];
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 160),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: const BoxDecoration(color: C.panel, border: Border(bottom: BorderSide(color: C.border))),
          child: Text(parts.join('  ·  '), style: T.small.copyWith(color: C.text), maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }
}
