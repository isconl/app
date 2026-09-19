import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../widgets/common.dart';

/// Channels: dashboard landing screen for flow and coordination.
/// Links to Teams, Inbox, and Kanban. (Buffer dropped from this tab,
/// BN26090606 -- still reachable via the hamburger menu.)
///
/// BN26090613: masonry tile grid, same pattern/mechanics as Academia's
/// track grid (learning.dart, BN26090604(b)) -- tile footprint is a
/// deterministic function of real data (badge counts), never literal
/// randomness. A tile carrying a live count (Inbox's inboxCount, Kanban's
/// live Jira-issue count -- already wired via services.store.jira, unlike
/// the row's assumption it wasn't) grows to a wider tier; everything else
/// stays 1x1. No information is ever dropped, only the treatment changes.
class ChannelsHomeView extends StatelessWidget {
  const ChannelsHomeView({super.key, this.onNavigate});
  final void Function(int subIndex)? onNavigate;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return SnapshotView(
      snapshot: services.store.state,
      builder: (context, data) {
        final state = fmt.m(data);
        final inboxCount = fmt.i(state['inbox_count']);
        final jiraIssues = fmt.lm(fmt.m(services.store.jira.value)['issues']);

        final tiles = [
          _ChannelTile(
            icon: Icons.groups_rounded,
            title: 'Teams',
            subtitle: 'Internal teams, channels, and org coordination',
            onTap: () => onNavigate?.call(1),
          ),
          _ChannelTile(
            icon: Icons.inbox_rounded,
            title: 'Inbox',
            subtitle: 'Unified communication streams & inbound triage',
            badge: inboxCount > 0 ? '$inboxCount' : null,
            wide: inboxCount > 0,
            onTap: () => onNavigate?.call(2),
          ),
          _ChannelTile(
            icon: Icons.view_kanban_rounded,
            title: 'Kanban',
            subtitle: 'Board tasks, workflow transitions, and sprint tracking',
            badge: jiraIssues.isNotEmpty ? '${jiraIssues.length}' : null,
            wide: jiraIssues.isNotEmpty,
            onTap: () => onNavigate?.call(3),
          ),
        ];

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 96),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionLabel('Channels & Flow'),
              // Same MasonryGridView.count + StaggeredGridTile.fit call as
              // learning.dart's track grid -- kept consistent rather than
              // hand-rolling a second grid implementation. Fixed 2-column:
              // this Shell only ever runs at phone width (native, or the
              // narrow-web branch of AdaptiveShell) -- see
              // adaptive_shell.dart's own note that no width breakpoint
              // exists anywhere in this app, matching learning.dart's own
              // precedent of not adding one either.
              MasonryGridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: tiles.length,
                itemBuilder: (context, i) => StaggeredGridTile.fit(
                  crossAxisCellCount: tiles[i].wide ? 2 : 1,
                  child: tiles[i],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
    this.wide = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String? badge;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Panel(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: C.surface,
              borderRadius: BorderRadius.circular(Sz.rMd),
            ),
            child: Icon(icon, color: C.greenBright, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(title,
                          style: T.w600(T.body),
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 8),
                      Badge2(badge!, color: C.greenBg, textColor: C.greenBright),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                // Every tile keeps its subtitle at every tier -- info is
                // never dropped for a smaller footprint, per the masonry
                // canon (design-system.md sec. 8): only truncation, never
                // omission.
                Text(subtitle,
                    style: T.small,
                    maxLines: wide ? 2 : 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: C.text3, size: 18),
        ],
      ),
    );
  }
}
