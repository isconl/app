import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_scope.dart';
import '../data/store.dart';
import '../theme.dart';
import '../util/fmt.dart' as fmt;
import 'shell.dart' show SecondaryScreen, openNavRoute;
import 'views/articles.dart';
import 'views/audit.dart';
import 'views/backlog.dart';
import 'views/calendar.dart';
import 'views/channels_home.dart';
import 'views/circle.dart';
import 'views/corporate.dart';
import 'views/decisions.dart';
import 'views/files.dart';
import 'views/finance.dart';
import 'views/github.dart';
import 'views/hosted_services.dart';
import 'views/hub.dart';
import 'views/ideas.dart';
import 'views/inbox.dart';
import 'views/jira.dart';
import 'views/journal.dart';
import 'views/learning.dart';
import 'views/media_view.dart';
import 'views/notifications.dart';
import 'views/ops.dart';
import 'views/outbox_view.dart';
import 'views/planning.dart';
import 'views/practice.dart';
import 'views/projects.dart';
import 'views/rhythm.dart';
import 'views/settings.dart';
import 'views/slate.dart';
import 'views/social.dart';
import 'views/teams.dart';
import 'widgets/command_palette.dart';
import 'widgets/common.dart';
import 'widgets/system_status.dart';

/// BI26092617: the navigation menu is a full-screen panel that slides in from the right, and its groups
/// and items come from `GET /api/nav` (hub's one navigation source), so web and mobile cannot drift. Only
/// the presentation lives here: an icon per view slug, and which mobile view a slug opens.

class NavItemDef {
  const NavItemDef({required this.view, required this.label, this.attrs = const {}, this.routed = true});
  final String view;
  final String label;

  /// The item's `data-*` hints from the web sidebar (`data-cat`, `data-ring`, `data-axis`).
  final Map<String, String> attrs;
  final bool routed;
}

class NavGroupDef {
  const NavGroupDef(this.key, this.label, this.items);
  final String key;
  final String label;
  final List<NavItemDef> items;
}

/// The groups of a `/api/nav` payload (`{groups: [{key, label, children: [...]}]}`), in the server's order.
/// Malformed entries are skipped rather than failing the menu.
List<NavGroupDef> parseNavGroups(dynamic json) {
  final out = <NavGroupDef>[];
  for (final g in fmt.lm(fmt.m(json)['groups'])) {
    final key = fmt.s(g['key']);
    final label = fmt.s(g['label']);
    if (key.isEmpty || label.isEmpty) continue;
    final items = <NavItemDef>[];
    for (final c in fmt.lm(g['children'])) {
      final view = fmt.s(c['view']);
      final itemLabel = fmt.s(c['label']);
      if (view.isEmpty || itemLabel.isEmpty) continue;
      final attrs = <String, String>{for (final e in fmt.m(c['attrs']).entries) e.key: fmt.s(e.value)};
      items.add(NavItemDef(view: view, label: itemLabel, attrs: attrs, routed: c['routed'] != false));
    }
    out.add(NavGroupDef(key, label, items));
  }
  return out;
}

/// The Material icon for a view slug. Presentation only: the web draws SVG, the app draws these.
IconData navIcon(String view) => switch (view) {
      'today' => Icons.bolt_rounded,
      'tasks' => Icons.task_alt_rounded,
      'planning' => Icons.explore_rounded,
      'calendar' => Icons.calendar_month_rounded,
      'notifications' => Icons.notifications_rounded,
      'inbox' => Icons.inbox_rounded,
      'teams' => Icons.groups_rounded,
      'jira' => Icons.view_kanban_rounded,
      'social' => Icons.share_rounded,
      'github' => Icons.code_rounded,
      'practice' => Icons.rocket_launch_rounded,
      'corporate' => Icons.apartment_rounded,
      'projects' => Icons.inventory_2_rounded,
      'rhythm' => Icons.local_fire_department_rounded,
      'identity' => Icons.badge_rounded,
      'finance' => Icons.account_balance_wallet_rounded,
      'learning' => Icons.school_rounded,
      'codex' => Icons.auto_stories_rounded,
      'circle' => Icons.favorite_rounded,
      'contacts' => Icons.contacts_rounded,
      'isconl' || 'xkeel' || 'qspace' => Icons.hub_rounded,
      'ops' => Icons.dns_rounded,
      'files' => Icons.folder_rounded,
      'media' => Icons.play_circle_filled_rounded,
      'backlog' => Icons.checklist_rounded,
      'audit' => Icons.link_rounded,
      _ => Icons.circle_outlined,
    };

/// The mobile view a nav item opens, or null when the app does not have one yet.
Widget? widgetForNavItem(NavItemDef i) => switch (i.view) {
      'today' => const HubView(),
      'tasks' => const SlateView(),
      'planning' => const PlanningView(),
      'calendar' => const CalendarView(),
      'notifications' => const NotificationsView(),
      'inbox' => const InboxView(),
      'teams' => const TeamsView(),
      'jira' => const JiraView(),
      'social' => const SocialView(),
      'github' => const GithubView(),
      'practice' => const PracticeView(),
      'corporate' => const CorporateView(),
      'projects' => ProjectsView(cat: i.attrs['data-cat'] == 'platform' ? 'platform' : 'product'),
      'rhythm' => const RhythmView(),
      'finance' => const FinanceView(),
      'learning' => const LearningView(),
      'circle' => i.attrs['data-ring'] == null ? null : CircleView(ring: i.attrs['data-ring']!),
      'contacts' => const ContactsView(),
      'ops' => const OpsView(),
      'files' => const FilesView(),
      'media' => const MediaView(),
      'backlog' => const BacklogView(),
      'audit' => const AuditView(),
      _ => null,
    };

/// What a nav item with no mobile view shows.
class NotOnMobileView extends StatelessWidget {
  const NotOnMobileView(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) =>
      EmptyState('$label is not on mobile yet', 'Open it on the web console for now.', icon: Icons.desktop_windows_rounded);
}

/// Features the app has and the web sidebar does not, kept reachable so renaming and mirroring the web
/// menu never loses one. This is the only list in the menu that is not served by hub.
const List<(String, IconData, String)> kMobileOnlyItems = [
  ('Channels', Icons.dashboard_rounded, 'channels'),
  ('Journal', Icons.auto_stories_rounded, 'journal'),
  ('Ideas', Icons.lightbulb_rounded, 'ideas'),
  ('Articles', Icons.article_rounded, 'articles'),
  ('Decisions & Risks', Icons.gavel_rounded, 'decisions'),
  ('Services', Icons.apps_rounded, 'services'),
  ('Outbox', Icons.outbox_rounded, 'outbox'),
];

Widget? _mobileOnlyView(String key) => switch (key) {
      'channels' => const ChannelsHomeView(),
      'journal' => const JournalView(),
      'ideas' => const IdeasView(),
      'articles' => const ArticlesView(),
      'decisions' => const DecisionsView(),
      'services' => const HostedServicesView(),
      'outbox' => const OutboxView(),
      _ => null,
    };

/// The cycle number and theme word from the server's `eqShort` ("Cycle 5  ·  Day 12  ·  Dig"), or null.
({int cycle, String theme})? parseEqShort(String eqShort) {
  final m = RegExp(r'^Cycle\s+(\d+)\s*[·|]\s*Day\s+\d+\s*[·|]\s*(.+?)\s*$').firstMatch(eqShort.trim());
  if (m == null) return null;
  return (cycle: int.parse(m.group(1)!), theme: m.group(2)!);
}

/// The theme line, `Reap: Harvest, don't hoard`: the word, then the cycle's tagline when it has one.
({String word, String? tagline})? cycleThemeLine(dynamic stateValue, dynamic cycleThemeValue) {
  final eq = parseEqShort(fmt.s(fmt.m(fmt.m(stateValue)['time'])['eqShort']));
  if (eq == null) return null;
  final override = fmt.s(fmt.m(cycleThemeValue)['theme']);
  final tagline = fmt.s(fmt.m(fmt.m(cycleThemeValue)['mix'])['tagline']);
  return (word: override.isNotEmpty ? override : eq.theme, tagline: tagline.isEmpty ? null : tagline);
}

/// Opens the menu: a route that slides in from the right (260 ms, easeOutCubic), not a bottom sheet.
void openNavMenu(BuildContext context) {
  HapticFeedback.selectionClick();
  Navigator.of(context).push(PageRouteBuilder<void>(
    opaque: true,
    transitionDuration: const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, __, ___) => const NavMenuScreen(),
    transitionsBuilder: (_, animation, __, child) => SlideTransition(
      position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
          .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic)),
      child: child,
    ),
  ));
}

class NavMenuScreen extends StatefulWidget {
  const NavMenuScreen({super.key});

  @override
  State<NavMenuScreen> createState() => _NavMenuScreenState();
}

class _NavMenuScreenState extends State<NavMenuScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _icon = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));

  @override
  void initState() {
    super.initState();
    // The hamburger the user just tapped turns into the X as the panel arrives.
    _icon.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final store = AppScope.of(context).store;
      store.nav.hydrate().then((_) {
        if (mounted) store.nav.refresh();
      });
    });
  }

  @override
  void dispose() {
    _icon.dispose();
    super.dispose();
  }

  void _close() {
    _icon.reverse();
    Navigator.of(context).maybePop();
  }

  void _open(Widget view, String title) {
    // Replace the menu with the destination, so back returns to where the menu was opened from.
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => SecondaryScreen(title: title, child: view)));
  }

  void _openItem(NavItemDef item) {
    final view = widgetForNavItem(item) ?? NotOnMobileView(item.label);
    _open(view, item.label);
  }

  Widget _row(IconData icon, String label, VoidCallback onTap, {String? badge, Key? key}) {
    return InkWell(
      key: key,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            Icon(icon, size: 17, color: C.text2),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: T.body2.copyWith(color: C.text))),
            if (badge != null) Badge2(badge, color: C.greenBg, textColor: C.greenBright),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final store = services.store;
    return Scaffold(
      backgroundColor: C.panel,
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          // Swipe right to close, as Android back does.
          onHorizontalDragEnd: (d) {
            if ((d.primaryVelocity ?? 0) > 300) _close();
          },
          child: ListenableBuilder(
            listenable: Listenable.merge([store.nav, store.state, store.cycleThemeFor(DateTime.now(), store.state.value)]),
            builder: (context, _) {
              final groups = parseNavGroups(store.nav.value);
              final state = fmt.m(store.state.value);
              final line = cycleThemeLine(state, store.cycleThemeFor(DateTime.now(), store.state.value).value);
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: line == null
                            ? const SizedBox.shrink()
                            : Text.rich(
                                key: const Key('nav-theme-line'),
                                TextSpan(
                                  style: T.body2.copyWith(color: C.text2),
                                  children: [
                                    TextSpan(text: line.word, style: const TextStyle(fontWeight: FontWeight.w700, color: C.text)),
                                    if (line.tagline != null) TextSpan(text: ': ${line.tagline}'),
                                  ],
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                      ),
                      IconButton(
                        key: const Key('nav-close'),
                        tooltip: 'Close menu',
                        onPressed: _close,
                        icon: AnimatedIcon(icon: AnimatedIcons.menu_close, progress: _icon),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: _row(Icons.settings_rounded, 'Settings', () => _open(const SettingsView(), 'Settings'),
                            key: const Key('nav-settings')),
                      ),
                      IconButton(
                        tooltip: 'Search',
                        icon: const Icon(Icons.search_rounded, size: 20, color: C.text2),
                        onPressed: () => showCommandPalette(context, (item) => _open(item.builder(), item.label)),
                      ),
                    ],
                  ),
                  if (groups.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text('The menu has not loaded yet. It is cached after the first time.', style: TextStyle(color: C.text3)),
                    ),
                  for (final g in groups) ...[
                    SectionLabel(g.label),
                    for (final i in g.items)
                      _row(
                        navIcon(i.view),
                        i.label,
                        () => _openItem(i),
                        key: Key('nav-item-${i.view}-${i.label}'),
                        badge: i.view == 'inbox' && fmt.i(state['inbox_count']) > 0 ? '${fmt.i(state['inbox_count'])}' : null,
                      ),
                  ],
                  const SectionLabel('On this device'),
                  for (final m in kMobileOnlyItems)
                    _row(m.$2, m.$1, () => _open(_mobileOnlyView(m.$3)!, m.$1), key: Key('nav-mobile-${m.$3}')),
                  const SizedBox(height: 18),
                  const Divider(),
                  const SizedBox(height: 10),
                  SystemStatusLines(services: services),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
