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
import 'views/buffer.dart';
import 'views/calendar.dart';
import 'views/chat.dart';
import 'views/circle.dart';
import 'views/decisions.dart';
import 'views/files.dart';
import 'views/finance.dart';
import 'views/github.dart';
import 'views/hub.dart';
import 'views/ideas.dart';
import 'views/inbox.dart';
import 'views/jira.dart';
import 'views/journal.dart';
import 'views/learning.dart';
import 'views/notifications.dart';
import 'views/outbox_view.dart';
import 'views/planning.dart';
import 'views/projects.dart';
import 'views/rhythm.dart';
import 'views/settings.dart';
import 'views/spaces.dart';
import 'views/tasks.dart';
import 'views/teams.dart';
import 'widgets/common.dart';
import 'widgets/nav_bar.dart';
import 'widgets/system_status.dart';

/// The shell: Hub · Tasks · Ask · Alerts · Menu.
/// "Order mirrors the day: orient, do, ask." (dashboard/index.html)
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final services = AppScope.of(context);
      services.sync.onNewAlerts =
          (fresh) => AlertService.instance.showAgentAlerts(fresh);
      services.sync.start();
      services.sync.fullSync(wake: true).then((_) async {
        // The whole library, on the device, whether or not he has opened it.
        // check() asks the agent what exists and what moved; prefetchAll() pulls
        // everything not already current, including modules never touched. On a
        // library that is already complete this is zero requests.
        await services.modules.check();
        await services.modules.prefetchAll();
        // M-Pesa context, every sync. With nothing new this is one cheap
        // platform call and no network - see services/sms_ingest.dart.
        await services.sms.run();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final titles = ['Hub', 'Tasks', 'Alerts'];
    return Scaffold(
      appBar: ShellAppBar(title: titles[_tab]),
      body: Column(
        children: [
          OfflineBanner(services: services),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: const [
                HubView(),
                TasksView(),
                NotificationsView(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _BottomBar(
        tab: _tab,
        onTab: (t) => setState(() => _tab = t),
        onAsk: () => openChatSheet(context),
        onMenu: () => _openMenu(context),
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

/// App bar shared by the shell and pushed views: brand, title, equicycle
/// context, live sync indicator.
class ShellAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ShellAppBar(
      {super.key,
      required this.title,
      this.showBrand = true,
      this.actions = const []});
  final String title;
  final bool showBrand;

  /// Screen-specific controls, placed before the sync indicator so the
  /// indicator stays in the same corner on every screen.
  final List<Widget> actions;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return AppBar(
      automaticallyImplyLeading: !showBrand,
      titleSpacing: showBrand ? 14 : 0,
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
        const SyncIndicator(),
        const SizedBox(width: 12),
      ],
      shape: const Border(bottom: BorderSide(color: C.border)),
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

/// Hub · Tasks · Ask · Alerts · Menu, in the expanding-pill style ARCHITECT
/// specified (see `widgets/nav_bar.dart`).
///
/// The elevated green Ask circle that used to sit in the middle is gone: a
/// raised button in the centre of a flat animated row fights it. Ask keeps its
/// prominence a quieter way - it is the one item tinted green at rest, so it
/// is still the thing your eye lands on first.
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.tab,
    required this.onTab,
    required this.onAsk,
    required this.onMenu,
  });

  final int tab;
  final void Function(int) onTab;
  final VoidCallback onAsk;
  final VoidCallback onMenu;

  /// Row order, and the map from row position to tab index. Ask and Menu are
  /// actions, so they hold no tab.
  static const _askSlot = 2;
  static const _menuSlot = 4;
  static const _tabForSlot = {0: 0, 1: 1, 3: 2};
  static const _slotForTab = {0: 0, 1: 1, 2: 3};

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return ListenableBuilder(
      listenable: services.sync,
      builder: (context, _) {
        final n = services.sync.newAlerts;
        return PillNavBar(
          index: _slotForTab[tab] ?? -1,
          onSelect: (slot) {
            if (slot == _askSlot) return onAsk();
            if (slot == _menuSlot) return onMenu();
            final t = _tabForSlot[slot];
            if (t != null) onTab(t);
          },
          items: [
            const PillNavItem(icon: Icons.bolt_rounded, label: 'Hub'),
            const PillNavItem(icon: Icons.task_alt_rounded, label: 'Tasks'),
            const PillNavItem(
              icon: Icons.forum_rounded,
              label: 'Ask',
              isTab: false,
              restingColor: C.green,
            ),
            PillNavItem(
              icon: Icons.notifications_rounded,
              label: 'Alerts',
              badge: n > 0 ? _AlertCount(n) : null,
            ),
            const PillNavItem(
                icon: Icons.menu_rounded, label: 'Menu', isTab: false),
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
          const SectionLabel('Command'),
          _item(ctx, Icons.flag_rounded, 'Planning',
              () => go(const PlanningView(), 'Planning')),
          _item(ctx, Icons.calendar_month_rounded, 'Calendar',
              () => go(const CalendarView(), 'Calendar')),
          _item(ctx, Icons.lightbulb_rounded, 'Ideas',
              () => go(const IdeasView(), 'Ideas'),
              badge: ideasCount > 0 ? '$ideasCount' : null),
          const SectionLabel('Channels'),
          _item(ctx, Icons.inbox_rounded, 'Inbox',
              () => go(const InboxView(), 'Inbox'),
              badge: inboxCount > 0 ? '$inboxCount' : null),
          _item(ctx, Icons.view_kanban_rounded, 'Kanban',
              () => go(const JiraView(), 'Kanban')),
          _item(ctx, Icons.groups_rounded, 'Teams',
              () => go(const TeamsView(), 'Teams')),
          _item(ctx, Icons.code_rounded, 'GitHub',
              () => go(const GithubView(), 'GitHub')),
          _item(ctx, Icons.share_rounded, 'Buffer',
              () => go(const BufferView(), 'Buffer')),
          const SectionLabel('Personal'),
          _item(ctx, Icons.account_balance_wallet_rounded, 'Finance',
              () => go(const FinanceView(), 'Finance')),
          _item(ctx, Icons.local_fire_department_rounded, 'Rhythm',
              () => go(const RhythmView(), 'Rhythm')),
          _item(ctx, Icons.auto_stories_rounded, 'Journal',
              () => go(const JournalView(), 'Journal')),
          _item(ctx, Icons.school_rounded, 'Learning',
              () => go(const LearningView(), 'Learning')),
          const SectionLabel('Circle'),
          _item(ctx, Icons.favorite_rounded, 'Family',
              () => go(const CircleView(ring: 'family'), 'Family')),
          _item(ctx, Icons.work_rounded, 'Professional',
              () => go(const CircleView(ring: 'professional'), 'Professional')),
          _item(ctx, Icons.celebration_rounded, 'Social',
              () => go(const CircleView(ring: 'social'), 'Social')),
          const SectionLabel('Projects & Spaces'),
          _item(ctx, Icons.rocket_launch_rounded, 'Projects',
              () => go(const ProjectsView(), 'Projects')),
          _item(ctx, Icons.hub_rounded, 'Spaces',
              () => go(const SpacesView(), 'Spaces')),
          _item(ctx, Icons.folder_rounded, 'Files',
              () => go(const FilesView(), 'Files')),
          _item(ctx, Icons.article_rounded, 'Articles',
              () => go(const ArticlesView(), 'Articles')),
          _item(ctx, Icons.gavel_rounded, 'Decisions & Risks',
              () => go(const DecisionsView(), 'Decisions & Risks')),
          const SectionLabel('System'),
          _item(ctx, Icons.link_rounded, 'Audit Chain',
              () => go(const AuditView(), 'Audit Chain')),
          _item(ctx, Icons.outbox_rounded, 'Outbox',
              () => go(const OutboxView(), 'Outbox'),
              badgeListenable: services.outbox),
          _item(ctx, Icons.settings_rounded, 'Settings',
              () => go(const SettingsView(), 'Settings')),
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
