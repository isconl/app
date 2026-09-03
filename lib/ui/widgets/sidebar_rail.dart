import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_scope.dart';
import '../../main.dart' show BrandMark;
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../views/articles.dart';
import '../views/audit.dart';
import '../views/buffer.dart';
import '../views/calendar.dart';
import '../views/circle.dart';
import '../views/corporate.dart';
import '../views/decisions.dart';
import '../views/files.dart';
import '../views/finance.dart';
import '../views/github.dart';
import '../views/hosted_services.dart';
import '../views/hub.dart';
import '../views/ideas.dart';
import '../views/inbox.dart';
import '../views/jira.dart';
import '../views/journal.dart';
import '../views/learning.dart';
import '../views/media_view.dart';
import '../views/notifications.dart';
import '../views/outbox_view.dart';
import '../views/planning.dart';
import '../views/projects.dart';
import '../views/rhythm.dart';
import '../views/settings.dart';
import '../views/spaces.dart';
import '../views/tasks.dart';
import '../views/teams.dart';
import 'common.dart';
import 'system_status.dart';

class NavItem {
  const NavItem(this.id, this.icon, this.label, this.builder);
  final String id;
  final IconData icon;
  final String label;
  final Widget Function() builder;
}

class NavGroup {
  const NavGroup(this.label, this.items);
  final String label;
  final List<NavItem> items;
}

/// Same taxonomy as shell.dart's [MenuSheet], deliberately duplicated for
/// Phase A (see the hub refactor canvas) rather than shared, so building the
/// desktop chrome can't regress the shipped mobile menu. Hub/Tasks/Alerts
/// are added here (mobile reaches those via its bottom tab bar instead).
final List<NavGroup> navGroups = [
  NavGroup('Hub', [
    NavItem('hub', Icons.bolt_rounded, 'Hub', () => const HubView()),
    NavItem('tasks', Icons.task_alt_rounded, 'Tasks', () => const TasksView()),
    NavItem('planning', Icons.flag_rounded, 'Planning', () => const PlanningView()),
    NavItem('calendar', Icons.calendar_month_rounded, 'Calendar', () => const CalendarView()),
    NavItem('ideas', Icons.lightbulb_rounded, 'Ideas', () => const IdeasView()),
    NavItem('notifications', Icons.notifications_rounded, 'Alerts', () => const NotificationsView()),
  ]),
  NavGroup('Channels', [
    NavItem('inbox', Icons.inbox_rounded, 'Inbox', () => const InboxView()),
    NavItem('jira', Icons.view_kanban_rounded, 'Kanban', () => const JiraView()),
    NavItem('teams', Icons.groups_rounded, 'Teams', () => const TeamsView()),
    NavItem('github', Icons.code_rounded, 'GitHub', () => const GithubView()),
    NavItem('buffer', Icons.share_rounded, 'Buffer',
        () => const BufferView(compose: true)),
  ]),
  NavGroup('Personal', [
    NavItem('finance', Icons.account_balance_wallet_rounded, 'Finance', () => const FinanceView()),
    NavItem('rhythm', Icons.local_fire_department_rounded, 'Rhythm', () => const RhythmView()),
    NavItem('journal', Icons.auto_stories_rounded, 'Journal', () => const JournalView()),
    NavItem('learning', Icons.school_rounded, 'Academia', () => const LearningView()),
  ]),
  NavGroup('Circle', [
    NavItem('family', Icons.favorite_rounded, 'Family', () => const CircleView(ring: 'family')),
    NavItem('professional', Icons.work_rounded, 'Professional', () => const CircleView(ring: 'professional')),
    NavItem('social', Icons.celebration_rounded, 'Social', () => const CircleView(ring: 'social')),
  ]),
  NavGroup('Projects & Spaces', [
    NavItem('projects', Icons.folder_rounded, 'Projects', () => const ProjectsView()),
    NavItem('corporate', Icons.apartment_rounded, 'Corporate', () => const CorporateView()),
    NavItem('spaces', Icons.hub_rounded, 'Spaces', () => const SpacesView()),
    NavItem('files', Icons.folder_rounded, 'Files', () => const FilesView()),
    NavItem('articles', Icons.article_rounded, 'Articles', () => const ArticlesView()),
    NavItem('decisions', Icons.gavel_rounded, 'Decisions & Risks', () => const DecisionsView()),
    NavItem('hosted-services', Icons.dns_rounded, 'Services', () => const HostedServicesView()),
  ]),
  NavGroup('System', [
    NavItem('media', Icons.play_circle_filled_rounded, 'Media', () => const MediaView()),
    NavItem('audit', Icons.link_rounded, 'Audit Chain', () => const AuditView()),
    NavItem('outbox', Icons.outbox_rounded, 'Outbox', () => const OutboxView()),
    NavItem('settings', Icons.settings_rounded, 'Settings',
        () => const SettingsView(showIntegrations: true)),
  ]),
];

NavItem findNavItem(String id) =>
    navGroups.expand((g) => g.items).firstWhere((i) => i.id == id);

/// Persistent left rail for the desktop web console - the sidebar the
/// legacy dashboard has and the mobile app doesn't need (it uses a bottom
/// tab bar + [MenuSheet] instead). Pinned brand header, scrollable nav
/// groups, pinned settings/search/status footer - same three-zone shape as
/// dashboard/style.css's `.sidebar`.
/// Which group holds the nav item for a view.
String? _navGroupForView(String id) {
  for (final g in navGroups) {
    if (g.items.any((i) => i.id == id)) return g.label;
  }
  return null;
}

class SidebarRail extends StatefulWidget {
  const SidebarRail({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.onCommandPalette,
  });

  final String selected;
  final void Function(NavItem) onSelect;
  final VoidCallback onCommandPalette;

  @override
  State<SidebarRail> createState() => _SidebarRailState();
}

/// One group open, ever - whichever holds the active view. Ported from the
/// web console's sidebar (see webconsole/static/app.js's navOpenOnly): no
/// group is pinned, so the rail never shows more than the single group
/// holding the view currently on screen.
class _SidebarRailState extends State<SidebarRail> {
  late String? _openGroup = _navGroupForView(widget.selected);

  @override
  void didUpdateWidget(SidebarRail old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected) {
      final g = _navGroupForView(widget.selected);
      if (g != null && g != _openGroup) setState(() => _openGroup = g);
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return Container(
      width: 230,
      decoration: const BoxDecoration(
        color: C.bgRaised,
        border: Border(right: BorderSide(color: C.border)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
            child: Row(
              children: [
                const BrandMark(size: 30),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: 'i',
                          style: T.headline.copyWith(
                              fontSize: 17, letterSpacing: -0.3,
                              fontWeight: FontWeight.w700)),
                      TextSpan(text: 'Architect',
                          style: T.headline.copyWith(
                              fontSize: 17, letterSpacing: -0.3,
                              fontWeight: FontWeight.w300, color: C.green)),
                      TextSpan(text: 'hub',
                          style: T.headline.copyWith(
                              fontSize: 17, letterSpacing: -0.3,
                              fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListenableBuilder(
              listenable: Listenable.merge(
                  [services.store.state, services.outbox, services.sync]),
              builder: (context, _) {
                final state = fmt.m(services.store.state.value);
                final inboxCount = fmt.i(state['inbox_count']);
                final ideasCount = fmt.i(state['ideas_count']);
                final alertsCount = services.sync.newAlerts;
                final outboxCount = services.outbox.pending;
                String? badgeFor(String id) => switch (id) {
                      'inbox' => inboxCount > 0 ? '$inboxCount' : null,
                      'ideas' => ideasCount > 0 ? '$ideasCount' : null,
                      'notifications' =>
                        alertsCount > 0 ? '$alertsCount' : null,
                      'outbox' => outboxCount > 0 ? '$outboxCount' : null,
                      _ => null,
                    };
                return ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  children: [
                    for (final group in navGroups) ...[
                      InkWell(
                        onTap: () => setState(() =>
                            _openGroup = _openGroup == group.label ? null : group.label),
                        child: SectionLabel(group.label,
                            padding: const EdgeInsets.fromLTRB(6, 14, 6, 6)),
                      ),
                      if (_openGroup == group.label)
                        for (final item in group.items)
                          _RailItem(
                            item: item,
                            selected: item.id == widget.selected,
                            badge: badgeFor(item.id),
                            onTap: () => widget.onSelect(item),
                          ),
                    ],
                  ],
                );
              },
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Enter the Architect...', style: T.small),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => widget.onSelect(findNavItem('settings')),
                    icon: const Icon(Icons.settings_rounded, size: 15),
                    label: const Text('Settings'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Command palette (Ctrl+K)',
                  onPressed: widget.onCommandPalette,
                  icon: const Icon(Icons.search_rounded, size: 18),
                  style: IconButton.styleFrom(
                    side: const BorderSide(color: C.border),
                    shape: const CircleBorder(),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
            child: SystemStatusLines(services: services),
          ),
        ],
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem(
      {required this.item,
      required this.selected,
      required this.onTap,
      this.badge});
  final NavItem item;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? C.greenBg : Colors.transparent,
        borderRadius: BorderRadius.circular(Sz.rMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(Sz.rMd),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                Icon(item.icon,
                    size: 16, color: selected ? C.greenBright : C.text2),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(item.label,
                      style: T.small.copyWith(
                        color: selected ? C.greenBright : C.text2,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400,
                      ),
                      overflow: TextOverflow.ellipsis),
                ),
                if (badge != null)
                  Badge2(badge!, color: C.greenDim, textColor: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
