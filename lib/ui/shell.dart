import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_scope.dart';
import '../data/sync.dart' show SyncPhase;
import '../main.dart' show BrandMark;
import '../services/alerts.dart';
import '../theme.dart';
import '../util/fmt.dart' as fmt;
import 'views/articles.dart';
import 'views/audit.dart';
import 'views/calendar.dart';
import 'views/channels_home.dart';
import 'views/chat.dart';
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
import 'views/portfolio.dart';
import 'views/projects.dart';
import 'views/rhythm.dart';
import 'views/security.dart';
import 'views/settings.dart';
import 'views/social.dart';
import 'views/spaces.dart';
import 'views/tasks.dart';
import 'views/teams.dart';
import 'widgets/command_palette.dart';
import 'widgets/common.dart';
import 'widgets/nav_bar.dart';
import 'widgets/system_status.dart';


/// The shell: Command · Channels · Personal · Projects · Settings (5 true tabs).
/// FAB = chat. Hamburger in app bar opens the full navigation menu sheet.
/// Each tab has a horizontal sub-tab strip for inner views.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

// ─── Sub-tab label + view definitions ────────────────────────────────────────
class _SubTab {
  const _SubTab(this.label, this.view);
  final String label;
  final Widget view;
}

const _commandSubs = [
  _SubTab('Hub',       HubView()),
  _SubTab('Tasks',     TasksView()),
  _SubTab('Planning',  PlanningView()),
  _SubTab('Calendar',  CalendarView()),
];

// Channels & Personal subs are constructed dynamically (need onNavigate callback).
// They're wired inside _ShellState.

// BN26090606: Portfolio is now the hub-style sub (real PortfolioView --
// Sconl's curated CV/resume links, not the venture-category filter that
// used to sit here), reordered to Portfolio, Corporate, Products,
// Platforms per Sconl's explicit target order.
const _projectsSubs = [
  _SubTab('Portfolio', PortfolioView()),
  _SubTab('Corporate', CorporateView()),
  _SubTab('Products',  ProjectsView(cat: 'product')),
  _SubTab('Platforms', ProjectsView(cat: 'platform')),
];

// BN26090606: target confirmed by Sconl -- Settings, Files, Ops, Security.
// Media/Audit/Outbox drop from this bottom-nav row (still reachable via
// the hamburger menu, which keeps every tool regardless of this tab's
// 4-item limit).
const _settingsSubs = [
  _SubTab('Settings', SettingsView()),
  _SubTab('Files',    FilesView()),
  _SubTab('Ops',      OpsView()),
  _SubTab('Security', SecurityView()),
];

class _ShellState extends State<Shell> {
  int _tab = 0;          // 0=Command 1=Channels 2=Projects 3=Personal 4=Settings
  int _sub = 0;          // sub-tab index within current tab

  void _switchTab(int t) {
    if (_tab != t) setState(() { _tab = t; _sub = 0; });
  }

  void _switchSub(int s) {
    if (_sub != s) setState(() => _sub = s);
  }

  // BN26090606: Buffer dropped to hit the 4-sub-tab target -- still
  // reachable via the hamburger menu (Sconl's explicit call, 6 Sep 2026).
  List<_SubTab> get _channelSubs => [
    _SubTab('Channels', ChannelsHomeView(onNavigate: _switchSub)),
    const _SubTab('Teams',   TeamsView()),
    const _SubTab('Inbox',   InboxView()),
    const _SubTab('Kanban',  JiraView()),
  ];

  // BN26090606: hub-style sub swapped from PersonalHomeView to RhythmView
  // (was built but never wired into this tab) and relabeled Personal ->
  // Rhythm, matching the webconsole's own Personal-space nav exactly.
  // Ideas dropped to hit the 4-sub-tab target -- still reachable via the
  // hamburger menu (Sconl's explicit call, 6 Sep 2026).
  List<_SubTab> get _personalSubs => [
    const _SubTab('Rhythm',    RhythmView()),
    const _SubTab('Academia',  LearningView()),
    const _SubTab('Finance',   FinanceView()),
    const _SubTab('Journal',   JournalView()),
  ];

  List<_SubTab> _subsFor(int tab) => switch (tab) {
    0 => _commandSubs,
    1 => _channelSubs,
    2 => _projectsSubs,
    3 => _personalSubs,
    4 => _settingsSubs,
    _ => _commandSubs,
  };

  static const _tabLabels = ['Command', 'Channels', 'Projects', 'Personal', 'Settings'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final services = AppScope.of(context);
      services.sync.onNewAlerts =
          (fresh) => AlertService.instance.showAgentAlerts(fresh);
      services.sync.start();
      services.sync.fullSync(wake: true).then((_) async {
        await services.modules.check();
        await services.modules.prefetchAll();
        await services.sms.run();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final subs = _subsFor(_tab);
    final safeSubIndex = _sub.clamp(0, subs.length - 1);
    return PopScope(
      // Allow the system to pop only when we are already at the root position
      // (tab 0, sub 0). Otherwise step back within the app ourselves.
      canPop: _tab == 0 && _sub == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return; // system handled it (we're at root)
        if (_sub > 0) {
          setState(() => _sub = 0);
        } else if (_tab > 0) {
          setState(() { _tab = 0; _sub = 0; });
        }
      },
      child: Scaffold(
        appBar: ShellAppBar(
          title: _tabLabels[_tab],
          onMenu: () => _openMenu(context),
        ),
        body: Column(
          children: [
            OfflineBanner(services: services),
            _SubTabBar(
              subs: subs,
              index: safeSubIndex,
              onSelect: _switchSub,
            ),
            Expanded(
              child: IndexedStack(
                index: safeSubIndex,
                children: subs.map((s) => s.view).toList(),
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          heroTag: 'fab_chat',
          backgroundColor: C.green,
          foregroundColor: C.textInverse,
          shape: const CircleBorder(),
          child: const Icon(Icons.forum_rounded),
          onPressed: () => openChatSheet(context),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        bottomNavigationBar: _BottomBar(
          tab: _tab,
          onTab: _switchTab,
          services: services,
        ),
      ),
    );
  }

  void _openMenu(BuildContext context) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: C.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Sz.rXl)),
        side: BorderSide(color: C.border),
      ),
      builder: (ctx) => const MenuSheet(),
    );
  }
}

// ─── Sub-tab horizontal strip ─────────────────────────────────────────────────
class _SubTabBar extends StatelessWidget {
  const _SubTabBar({
    required this.subs,
    required this.index,
    required this.onSelect,
  });
  final List<_SubTab> subs;
  final int index;
  final void Function(int) onSelect;

  @override
  Widget build(BuildContext context) {
    if (subs.length <= 1) return const SizedBox.shrink();
    return Container(
      height: 36,
      decoration: const BoxDecoration(
        color: C.bg,
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        itemCount: subs.length,
        itemBuilder: (context, i) {
          final selected = i == index;
          return GestureDetector(
            onTap: () => onSelect(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: selected ? C.greenBg : Colors.transparent,
                // BN26090606: rounded-rectangle, matching the webconsole's
                // own standard small-button radius (--r-sm: 5px == Sz.rSm)
                // -- was a fully-rounded pill (circular(20) against a 36px
                // strip). Sconl's ask was specifically about the Calendar
                // sub-tab, but this is the ONE shared component every
                // sub-tab across every bottom-nav tab renders through, so
                // the fix lands everywhere that style is reused, not just
                // Calendar's own button.
                borderRadius: BorderRadius.circular(Sz.rSm),
                border: selected ? Border.all(color: C.greenDim) : null,
              ),
              child: Center(
                child: Text(
                  subs[i].label,
                  style: (selected
                          ? T.body2.copyWith(color: C.greenBright, fontWeight: FontWeight.w600)
                          : T.body2)
                      .copyWith(fontSize: 12),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}



/// App bar shared by the shell and pushed views: brand, title, equicycle
/// context, sync indicator. The shell passes [onMenu] to render a hamburger
/// icon in the actions trailing area; secondary screens omit it and get the
/// back arrow from the navigator instead.
class ShellAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ShellAppBar({
    super.key,
    required this.title,
    this.showBrand = true,
    this.actions = const [],
    this.onMenu,
  });
  final String title;
  final bool showBrand;

  /// Screen-specific controls, placed before the sync indicator so the
  /// indicator stays in the same corner on every screen.
  final List<Widget> actions;

  /// When non-null, renders a hamburger icon button as the leading trailing
  /// action. Used by the Shell; secondary screens leave this null.
  final VoidCallback? onMenu;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final canPop = Navigator.of(context).canPop();
    return AppBar(
      automaticallyImplyLeading: false,
      leading: !showBrand && canPop
          ? IconButton(
              icon: const Icon(Icons.chevron_left_rounded, size: 26),
              tooltip: 'Back',
              onPressed: () {
                HapticFeedback.selectionClick();
                Navigator.of(context).maybePop();
              },
            )
          : null,
      titleSpacing: (showBrand || (!canPop && !showBrand)) ? 14 : 0,
      title: Row(
        children: [
          if (showBrand) ...[
            const BrandMark(size: 26),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: T.title),
                ListenableBuilder(
                  listenable: services.store.state,
                  builder: (context, _) {
                    final eq =
                        fmt.m(fmt.m(services.store.state.value)['time']);
                    final line = fmt.s(eq['eqShort']);
                    return line.isEmpty
                        ? const SizedBox.shrink()
                        : Text(line,
                            style: T.monoSmall.copyWith(fontSize: 9.5),
                            overflow: TextOverflow.ellipsis);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        ...actions,
        if (onMenu != null)
          IconButton(
            icon: const Icon(Icons.menu_rounded),
            tooltip: 'Navigation menu',
            onPressed: () {
              HapticFeedback.selectionClick();
              onMenu!();
            },
          )
        else
          const SyncIndicator(),
        const SizedBox(width: 4),
      ],
    );
  }
}

/// Green dot when synced, amber spinner when syncing, red when offline.
/// Tap = sync now.
class SyncIndicator extends StatelessWidget {
  const SyncIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([services.sync, services.outbox]),
      builder: (context, _) {
        final sync = services.sync;
        final busy = sync.phase != SyncPhase.idle;
        Widget core;
        if (!sync.online) {
          core = const Icon(Icons.cloud_off_rounded, size: 17, color: C.text3);
        } else if (busy) {
          core = const MiniSpinner();
        } else {
          core = const StatusDot(C.green, glow: true);
        }
        return InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            HapticFeedback.selectionClick();
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(sync.statusLine),
              duration: const Duration(seconds: 2),
            ));
            if (sync.online) sync.fullSync();
          },
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                core,
                if (services.outbox.pending > 0) ...[
                  const SizedBox(width: 5),
                  Badge2('${services.outbox.pending}',
                      color: C.amberBg, textColor: C.amber),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Thin strip below the app bar when offline.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, required this.services});
  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([services.sync, services.outbox]),
      builder: (context, _) {
        if (services.sync.online) return const SizedBox.shrink();
        final queued = services.outbox.pending;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          color: C.amberBg,
          child: Row(
            children: [
              const Icon(Icons.cloud_off_rounded, size: 13, color: C.amber),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  queued > 0
                      ? 'Offline · ${fmt.plural(queued, "change")} queued · will sync to OneDrive on reconnect'
                      : 'Offline · reading your local mirror',
                  style: T.tiny.copyWith(color: C.amber),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Command · Channels · Projects · Personal · Settings — 5 true tabs.
/// The floating chat FAB replaces the old Ask slot.
/// The hamburger is now in the app bar; this bar is purely navigational.
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.tab,
    required this.onTab,
    required this.services,
  });

  final int tab;
  final void Function(int) onTab;
  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: services.sync,
      builder: (context, _) {
        final n = services.sync.newAlerts;
        return PillNavBar(
          index: tab,
          onSelect: onTab,
          items: [
            const PillNavItem(icon: Icons.bolt_rounded,         label: 'Command'),
            const PillNavItem(icon: Icons.dynamic_feed_rounded, label: 'Channels'),
            const PillNavItem(icon: Icons.folder_rounded, label: 'Projects', svgAsset: 'assets/icons/nav_projects.svg'),
            const PillNavItem(icon: Icons.person_rounded, label: 'Personal', svgAsset: 'assets/icons/nav_personal.svg'),
            PillNavItem(
              icon: Icons.settings_rounded,
              label: 'Settings',
              badge: n > 0 ? _AlertCount(n) : null,
            ),
          ],
        );
      },
    );
  }
}


class _AlertCount extends StatelessWidget {
  const _AlertCount(this.n);
  final int n;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: C.green,
        borderRadius: BorderRadius.circular(8),
      ),
      constraints: const BoxConstraints(minWidth: 15),
      child: Text(
        n > 99 ? '99' : '$n',
        textAlign: TextAlign.center,
        style: T.monoSmall.copyWith(
            color: C.textInverse, fontSize: 8.5, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Grouped navigation, mirroring the web sidebar exactly.
class MenuSheet extends StatelessWidget {
  const MenuSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final state = fmt.m(services.store.state.value);
    final inboxCount = fmt.i(state['inbox_count']);
    final ideasCount = fmt.i(state['ideas_count']);

    void go(Widget view, String title) {
      Navigator.pop(context);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SecondaryScreen(title: title, child: view),
        ),
      );
    }

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.82,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (ctx, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                color: C.borderMid,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // ── SETTINGS + SEARCH (top row) ───────────────────────
          // BN26090611: matches the web panel's own Settings-left/
          // Search-right single row, moved out of the bottom of Systems.
          // "Search" on web (`#cmd-trigger`) is the command palette
          // (Ctrl+K), not a text-search feature -- this app already has
          // one (`command_palette.dart`, desktop-only until now), so this
          // wires an existing widget in rather than building new search.
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Expanded(
                  child: _topRowButton(ctx, Icons.settings_rounded, 'Settings',
                      () => go(const SettingsView(), 'Settings')),
                ),
                const SizedBox(width: 8),
                _topRowButton(ctx, Icons.search_rounded, null,
                    () => showCommandPalette(
                        ctx, (item) => go(item.builder(), item.label)),
                    square: true),
              ],
            ),
          ),
          // ── COMMAND ──────────────────────────────────────────
          const SectionLabel('Command'),
          _item(ctx, Icons.bolt_rounded, 'Hub',
              () => go(const HubView(), 'Hub')),
          _item(ctx, Icons.task_alt_rounded, 'Tasks',
              () => go(const TasksView(), 'Tasks')),
          _item(ctx, Icons.flag_rounded, 'Planning',
              () => go(const PlanningView(), 'Planning')),
          _item(ctx, Icons.calendar_month_rounded, 'Calendar',
              () => go(const CalendarView(), 'Calendar')),
          _item(ctx, Icons.notifications_rounded, 'Alerts',
              () => go(const NotificationsView(), 'Alerts')),
          // ── CHANNELS ─────────────────────────────────────────
          const SectionLabel('Channels'),
          _item(ctx, Icons.groups_rounded, 'Teams',
              () => go(const TeamsView(), 'Teams')),
          _item(ctx, Icons.inbox_rounded, 'Inbox',
              () => go(const InboxView(), 'Inbox'),
              badge: inboxCount > 0 ? '$inboxCount' : null),
          _item(ctx, Icons.share_rounded, 'Buffer',
              () => go(const SocialView(), 'Buffer')),
          _item(ctx, Icons.view_kanban_rounded, 'Kanban',
              () => go(const JiraView(), 'Kanban')),
          _item(ctx, Icons.code_rounded, 'GitHub',
              () => go(const GithubView(), 'GitHub')),
          // ── PROJECTS ─────────────────────────────────────────
          const SectionLabel('Projects'),
          _item(ctx, Icons.rocket_launch_rounded, 'Portfolio',
              () => go(const PortfolioView(), 'Portfolio')),
          _item(ctx, Icons.inventory_2_rounded, 'Products',
              () => go(const ProjectsView(cat: 'product'), 'Products')),
          _item(ctx, Icons.layers_rounded, 'Platforms',
              () => go(const ProjectsView(cat: 'platform'), 'Platforms')),
          _item(ctx, Icons.apartment_rounded, 'Corporate',
              () => go(const CorporateView(), 'Corporate')),
          // ── PERSONAL ─────────────────────────────────────────
          const SectionLabel('Personal'),
          _item(ctx, Icons.local_fire_department_rounded, 'Rhythm',
              () => go(const RhythmView(), 'Rhythm')),
          _item(ctx, Icons.school_rounded, 'Academia',
              () => go(const LearningView(), 'Academia')),
          _item(ctx, Icons.account_balance_wallet_rounded, 'Finance',
              () => go(const FinanceView(), 'Finance')),
          _item(ctx, Icons.auto_stories_rounded, 'Journal',
              () => go(const JournalView(), 'Journal')),
          _item(ctx, Icons.lightbulb_rounded, 'Ideas',
              () => go(const IdeasView(), 'Ideas'),
              badge: ideasCount > 0 ? '$ideasCount' : null),
          // ── CIRCLE ───────────────────────────────────────────
          const SectionLabel('Circle'),
          _item(ctx, Icons.favorite_rounded, 'Family',
              () => go(const CircleView(ring: 'family'), 'Family')),
          _item(ctx, Icons.work_rounded, 'Professional',
              () => go(const CircleView(ring: 'professional'), 'Professional')),
          _item(ctx, Icons.celebration_rounded, 'Social',
              () => go(const CircleView(ring: 'social'), 'Social')),
          _item(ctx, Icons.contacts_rounded, 'Contacts',
              () => go(const ContactsView(), 'Contacts')),
          // ── SPACES ───────────────────────────────────────────
          const SectionLabel('Spaces'),
          _item(ctx, Icons.hub_rounded, 'All Spaces',
              () => go(const SpacesView(), 'Spaces')),
          _item(ctx, Icons.visibility_rounded, 'Visionary',
              () => go(const SpacesView(axis: 'VIS'), 'Visionary')),
          _item(ctx, Icons.engineering_rounded, 'Innovator',
              () => go(const SpacesView(axis: 'INN'), 'Innovator')),
          _item(ctx, Icons.palette_rounded, 'Creator',
              () => go(const SpacesView(axis: 'CRE'), 'Creator')),
          // ── SYSTEMS ──────────────────────────────────────────
          // BN26090611: "System" -> "Systems", matching the web panel's
          // own rename (RG26090501). Ops added (new this session, wasn't
          // reachable from the drawer before). Articles/Decisions & Risks/
          // Services/Outbox have no literal web left-panel counterpart
          // (Outbox is a mobile-only offline-queue concept; Services
          // overlaps with the new Ops view but isn't identical -- kept as
          // real, working mobile features rather than dropped to force a
          // 1:1 match with a panel that doesn't have a slot for them) --
          // flagged rather than guessed, see build.md's BN26090611 note.
          const SectionLabel('Systems'),
          _item(ctx, Icons.dns_rounded, 'Ops',
              () => go(const OpsView(), 'Ops')),
          _item(ctx, Icons.shield_outlined, 'Security',
              () => go(const SecurityView(), 'Security')),
          _item(ctx, Icons.apps_rounded, 'Services',
              () => go(const HostedServicesView(), 'Services')),
          _item(ctx, Icons.folder_rounded, 'Files',
              () => go(const FilesView(), 'Files')),
          _item(ctx, Icons.play_circle_filled_rounded, 'Media',
              () => go(const MediaView(), 'Media')),
          _item(ctx, Icons.link_rounded, 'Audit Chain',
              () => go(const AuditView(), 'Audit Chain')),
          _item(ctx, Icons.article_rounded, 'Articles',
              () => go(const ArticlesView(), 'Articles')),
          _item(ctx, Icons.gavel_rounded, 'Decisions & Risks',
              () => go(const DecisionsView(), 'Decisions & Risks')),
          _item(ctx, Icons.outbox_rounded, 'Outbox',
              () => go(const OutboxView(), 'Outbox'),
              badgeListenable: services.outbox),
          const SizedBox(height: 18),
          const Divider(),
          const SizedBox(height: 10),
          SystemStatusLines(services: services),
        ],
      ),
    );
  }


  Widget _item(BuildContext context, IconData icon, String label,
      VoidCallback onTap,
      {String? badge, Listenable? badgeListenable}) {
    Widget row = Row(
      children: [
        Icon(icon, size: 17, color: C.text2),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: T.w500(T.body2))),
        if (badge != null)
          Badge2(badge, color: C.greenDim, textColor: Colors.white),
        if (badgeListenable != null)
          ListenableBuilder(
            listenable: badgeListenable,
            builder: (context, _) {
              final services = AppScope.of(context);
              final n = services.outbox.pending;
              return n > 0
                  ? Badge2('$n', color: C.amberBg, textColor: C.amber)
                  : const SizedBox.shrink();
            },
          ),
        const SizedBox(width: 4),
        const Icon(Icons.chevron_right_rounded, size: 16, color: C.text3),
      ],
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(Sz.rMd),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: row,
        ),
      ),
    );
  }

  /// BN26090611: Settings/Search top row. `label == null` renders an
  /// icon-only square button (the Search/command-palette side, matching
  /// the web panel's own icon-only Ctrl+K trigger); otherwise a labeled
  /// pill filling the available width (the Settings side).
  Widget _topRowButton(
      BuildContext context, IconData icon, String? label, VoidCallback onTap,
      {bool square = false}) {
    return Material(
      color: C.surface,
      borderRadius: BorderRadius.circular(Sz.rMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(Sz.rMd),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: square
              ? const EdgeInsets.all(12)
              : const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: label == null
              ? Icon(icon, size: 18, color: C.text2)
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 17, color: C.text2),
                    const SizedBox(width: 10),
                    Text(label, style: T.w500(T.body2)),
                  ],
                ),
        ),
      ),
    );
  }

}

/// Wrapper scaffold for views pushed from the Menu.
class SecondaryScreen extends StatelessWidget {
  const SecondaryScreen({super.key, required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return Scaffold(
      appBar: ShellAppBar(title: title, showBrand: false),
      body: Column(
        children: [
          OfflineBanner(services: services),
          Expanded(child: child),
        ],
      ),
    );
  }
}
