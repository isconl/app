import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../widgets/common.dart';
import 'github.dart';
import 'inbox.dart';
import 'jira.dart';
import 'social.dart';
import 'teams.dart';

/// Channels: dashboard landing screen for flow and coordination.
/// Links to Teams, Inbox, Social/Buffer, Jira/Kanban, and GitHub.
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

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 96),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionLabel('Channels & Flow'),
              _Tile(
                icon: Icons.groups_rounded,
                title: 'Teams',
                subtitle: 'Internal teams, channels, and org coordination',
                onTap: () => onNavigate?.call(1),
              ),
              const SizedBox(height: 8),
              _Tile(
                icon: Icons.inbox_rounded,
                title: 'Inbox',
                subtitle: 'Unified communication streams & inbound triage',
                badge: inboxCount > 0 ? '$inboxCount' : null,
                onTap: () => onNavigate?.call(2),
              ),
              const SizedBox(height: 8),
              _Tile(
                icon: Icons.share_rounded,
                title: 'Social & Buffer',
                subtitle: 'Social publishing channels, campaigns, and queue',
                onTap: () => onNavigate?.call(3),
              ),
              const SizedBox(height: 8),
              _Tile(
                icon: Icons.view_kanban_rounded,
                title: 'Jira / Kanban',
                subtitle: 'Board tasks, workflow transitions, and sprint tracking',
                badge: jiraIssues.isNotEmpty ? '${jiraIssues.length}' : null,
                onTap: () => onNavigate?.call(4),
              ),
              const SizedBox(height: 8),
              _Tile(
                icon: Icons.code_rounded,
                title: 'GitHub',
                subtitle: 'Repository fleet status, commits, PRs, and CI health',
                onTap: () => onNavigate?.call(5),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String? badge;

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
                    Text(title, style: T.w600(T.body)),
                    if (badge != null) ...[
                      const SizedBox(width: 8),
                      Badge2(badge!, color: C.greenBg, textColor: C.greenBright),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(subtitle, style: T.small),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: C.text3, size: 18),
        ],
      ),
    );
  }
}
