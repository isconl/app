import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_scope.dart';
import '../util/equicycle.dart';
import '../data/store.dart' show Snapshot;
import '../data/sync.dart' show SyncPhase;
import '../main.dart' show BrandMark;
import '../readiness/readiness_host.dart';
import '../services/alerts.dart';
import '../theme.dart';
import '../util/fmt.dart' as fmt;
import 'views/articles.dart';
import 'views/audit.dart';
import 'views/calendar.dart';
import 'views/channel_subs.dart';
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
import 'views/codex.dart';
import 'views/identity.dart';
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
import 'nav_menu.dart';
import 'status_chip.dart';
import 'views/slate.dart';
import 'views/social.dart';
import 'views/spaces.dart';
import 'views/surfaced.dart';
import 'views/teams.dart';
import 'widgets/brand.dart' show MonoBrandMark;
import 'whats_new_sheet.dart';
import 'widgets/command_palette.dart';
import 'widgets/common.dart';
import 'widgets/nav_bar.dart';
import 'widgets/system_status.dart';


/// The shell: Command · Channels · Personal · Projects · Settings (5 true tabs).
/// FAB = chat. Hamburger in app bar opens the full navigation menu sheet.
/// Each tab has a horizontal sub-tab strip for inner views.
class Shell extends StatefulWidget {
  const Shell({super.key, this.initialTab = 0, this.initialSub = 0});
  final int initialTab;
  final int initialSub;

  @override
  State<Shell> createState() => _ShellState();
}

// ─── Sub-tab label + view definitions ────────────────────────────────────────
@visibleForTesting
class SubTab {
  const SubTab(this.label, this.view);
  final String label;
  final Widget view;
}

typedef _SubTab = SubTab;

// BN26091012: reordered Calendar before Planning, per Sconl.
const _commandSubs = [
  _SubTab('Hub',       HubView()),
  _SubTab('Slate',     SlateView()),
  _SubTab('Calendar',  CalendarView()),
  _SubTab('Compass',   PlanningView()),
];

// Channels & Personal subs are constructed dynamically (need onNavigate callback).
// They're wired inside _ShellState.

// BN26090606: Portfolio is now the hub-style sub (real PortfolioView --
// Sconl's curated CV/resume links, not the venture-category filter that
// used to sit here), reordered to Portfolio, Corporate, Products,
// Platforms per Sconl's explicit target order.
// BI26092606: Portfolio sub-tab renamed to Practice (PortfolioView unchanged).
// BI26092324: now a real PracticeView (Documents = PortfolioView unchanged,
// plus honest placeholders for Overview/Practices/Codex/Enquiries), matching
// the web console's renderPractice()/PRACTICE_TABS tab for tab.
// BI26100129: Practice carries the Projects dashboard, whose tiles open the siblings.
List<_SubTab> _projectsSubsFor(void Function(int) openSub) => [
  _SubTab('Practice',  PracticeView(onOpenSub: openSub)),
  const _SubTab('Corporate', CorporateView()),
  const _SubTab('Products',  ProjectsView(cat: 'product')),
  const _SubTab('Platforms', ProjectsView(cat: 'platform')),
];

// BN26090606: target confirmed by Sconl -- Settings, Files, Ops, Security.
// Media/Audit/Outbox drop from this bottom-nav row (still reachable via
// the hamburger menu, which keeps every tool regardless of this tab's
// 4-item limit). BG26091020: Ops + Security merged into one tab (later
// relabelled back to "Ops", BG26091406) -- Security's stub content now
// renders as a section inside OpsView, so this row was down to 3
// sub-tabs. BG26091303: Backlog added as the 4th, and the tab itself
// relabelled Settings -> Systems (SettingsView() stays index 0/default).
// BI26100131: Settings carries the Systems dashboard, whose tiles open Ops and the Slate Register.
List<_SubTab> _settingsSubsFor(void Function(int) openSub) => [
  _SubTab('Settings', SettingsView(onOpenSub: openSub)),
  const _SubTab('Hold',     FilesView()),
  const _SubTab('Ops',      OpsView()),
];

class _ShellState extends State<Shell> {
  late int _tab;          // 0=Command 1=Channels 2=Projects 3=Personal 4=Systems
  late int _sub;          // sub-tab index within current tab

  // BI26092605: horizontal swipe now moves between the sub-tabs of the
  // current bottom-nav tab (e.g. Inbox -> Teams -> Kanban -> Buffer), never
  // between bottom-nav tabs. The bottom nav changes only when tapped.
  // Each bottom tab has its own PageController (recreated on tab change to
  // guarantee landing at sub 0); tapping a sub-tab animates it with easeOut
  // (240 ms); _sub is committed only in the sub PageView's onPageChanged.
  late final List<PageController> _subControllers;
  Snapshot? _nav;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
    _sub = widget.initialSub;
    _subControllers = List.generate(
      5,
      (i) => PageController(initialPage: i == _tab ? _sub : 0),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final services = AppScope.of(context);
      _nav = services.store.nav;
      _nav!.hydrate();
      _nav!.addListener(_onNav);
      services.sync.onNewAlerts =
          (fresh) => AlertService.instance.showAgentAlerts(fresh);
      services.sync.start();
      // BI26100531: "What's new" once after an update; never blocks the shell and fails quietly.
      maybeShowWhatsNew(context);
      services.sync.fullSync(wake: true).then((_) async {
        await services.modules.check();
        await services.modules.prefetchAll();
        await services.sms.run();
      });
    });
  }

  @override
  void dispose() {
    _nav?.removeListener(_onNav);
    for (final c in _subControllers) {
      c.dispose();
    }
    super.dispose();
  }

  /// A new nav can change how many Channels sub-tabs there are; keep the page index inside them.
  void _onNav() {
    if (!mounted) return;
    setState(() {
      final n = _subsFor(_tab).length;
      if (_sub >= n) _sub = n - 1;
    });
  }

  void _switchTab(int t) {
    if (_tab == t) {
      if (_sub != 0) {
        _switchSub(0);
      }
      return;
    }
    _subControllers[t].dispose();
    _subControllers[t] = PageController(initialPage: 0);
    setState(() {
      _tab = t;
      _sub = 0;
    });
  }

  void _switchSub(int s) {
    if (_sub == s) return;
    final controller = _subControllers[_tab];
    if (controller.hasClients) {
      controller.animateToPage(
        s,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    }
  }

  void _onSubPageChanged(int s) {
    if (_sub != s) {
      setState(() => _sub = s);
    }
  }

  // BN26090606: Buffer dropped to hit the 4-sub-tab target -- still
  // reachable via the hamburger menu (Sconl's explicit call, 6 Sep 2026).
  // BN26091013: Inbox is now the default/landing sub-tab, order Inbox,
  // Teams, Kanban, Buffer -- ChannelsHomeView's masonry-tile dashboard
  // drops OUT of the 4-tab bottom row (still reachable via the hamburger
  // menu), same precedent BN26090606 already set for Personal
  // (PersonalHomeView -> RhythmView, a real content view replacing a
  // generic dashboard landing).
  // BI26092637: the sub-tabs come from /api/nav (flow group): Inbox, Deck, Teams, Tools
  // (Kanban, Buffer and GitHub folded into Tools). Press is not a mobile sub-tab.
  List<_SubTab> get _channelSubs {
    final nav = AppScope.of(context).store.nav.value;
    final tools = toolViewsIn(nav);
    return [
      for (final p in channelPlan(nav))
        _SubTab(
          p.label,
          switch (p.kind) {
            ChannelKind.inbox => InboxView(onOpenView: _openChannelView),
            ChannelKind.deck => const DeckChannelView(),
            ChannelKind.teams => const TeamsView(),
            ChannelKind.tools => ToolsView(views: tools),
          },
        ),
    ];
  }

  /// Opens the Channels sub-tab that holds [view] (a nav view slug), selecting the tool inside Tools.
  void _openChannelView(String view) {
    final plan = channelPlan(AppScope.of(context).store.nav.value);
    final kind = switch (view) {
      'jira' || 'social' || 'github' => ChannelKind.tools,
      'teams' => ChannelKind.teams,
      'canvas' || 'deck' => ChannelKind.deck,
      _ => ChannelKind.inbox,
    };
    if (toolViews.contains(view)) ToolsPrefs.instance.select(view, db: AppScope.of(context).db);
    final i = plan.indexWhere((p) => p.kind == kind);
    if (i >= 0) _switchSub(i);
  }

  // BN26090606: hub-style sub swapped from PersonalHomeView to RhythmView
  // (was built but never wired into this tab) and relabeled Personal ->
  // Rhythm, matching the webconsole's own Personal-space nav exactly.
  // Ideas dropped to hit the 4-sub-tab target -- still reachable via the
  // hamburger menu (Sconl's explicit call, 6 Sep 2026).
  List<_SubTab> get _personalSubs => [
    _SubTab('Rhythm',    RhythmView(onOpenSub: _switchSub)),
    const _SubTab('Study',  LearningView()),
    const _SubTab('Ledger',     FinanceView()),
    const _SubTab('Codex',   CodexView()),
  ];

  List<_SubTab> _subsFor(int tab) => switch (tab) {
    0 => _commandSubs,
    1 => _channelSubs,
    2 => _projectsSubsFor(_switchSub),
    3 => _personalSubs,
    4 => _settingsSubsFor(_switchSub),
    _ => _commandSubs,
  };

  static const _tabLabels = ['Command', 'Channels', 'Projects', 'Personal', 'Systems'];

  Widget _tabBody(BuildContext context, int tab, AppServices services) {
    final subs = _subsFor(tab);
    final safeSubIndex = _sub.clamp(0, subs.length - 1);
    return Column(
      children: [
        // BN26091004: the amber offline banner now mounts in Settings only
        // (index 4) -- every other tab relies on the compact SyncIndicator
        // beside the hamburger instead (see ShellAppBar's actions below).
        if (tab == 4) OfflineBanner(services: services),
        _SubTabBar(
          subs: subs,
          index: safeSubIndex,
          onSelect: _switchSub,
          services: services,
          tab: tab,
        ),
        Expanded(
          child: PageView(
            key: ValueKey('tab_sub_pageview_$tab'),
            controller: _subControllers[tab],
            onPageChanged: _onSubPageChanged,
            children: subs.map((s) => s.view).toList(),
          ),
        ),
      ],
    );
  }

  /// BI26092622: a view's own chip where it declares one (Systems > Backlog), else data freshness.
  StatusChipSource _chipSource(AppServices services) {
    void open(BuildContext c, String title, Widget page) => Navigator.push(
          c,
          MaterialPageRoute(builder: (_) => SecondaryScreen(title: title, child: page)),
        );
    final fallback = FreshnessChipSource(services, open);
    if (_tab == 0) EquicycleYears.instance.ensureLoaded(services.api, services.db);
    final StatusChipSource? specific = switch ((_tab, _sub)) {
      (4, 2) => OpsChipSource(services, open),
      (0, _) => CycleChipSource(open),
      _ => null,
    };
    return ChipSelector(specific, fallback);
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return PopScope(
      // Allow the system to pop only when we are already at the root position
      // (tab 0, sub 0). Otherwise step back within the app ourselves.
      canPop: _tab == 0 && _sub == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return; // system handled it (we're at root)
        if (_sub > 0) {
          _switchSub(0);
        } else if (_tab > 0) {
          _switchTab(0);
        }
      },
      child: Scaffold(
        appBar: ShellAppBar(
          title: _tabLabels[_tab],
          chipSource: _chipSource(services),
          // BI26100539: ShellAppBar adds the one SyncIndicator itself; a second one here
          // is what drew two dots.
          onMenu: () => openMenu(context),
        ),
        body: _tabBody(context, _tab, services),
        floatingActionButton: CircleFab(
          heroTag: 'fab_chat',
          tooltip: 'Assistant',
          icon: const MonoBrandMark(color: C.textInverse, size: 24),
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
}

/// Opens the navigation menu (BI26092617: a full-screen panel sliding in from the right).
void openMenu(BuildContext context) => openNavMenu(context);

// ─── Sub-tab horizontal strip ─────────────────────────────────────────────────
@visibleForTesting
class SubTabBar extends StatelessWidget {
  const SubTabBar({
    super.key,
    required this.subs,
    required this.index,
    required this.onSelect,
    this.services,
    this.tab,
    this.landingCount,
  });

  final List<SubTab> subs;
  final int index;
  final void Function(int) onSelect;
  final AppServices? services;
  final int? tab;
  final int? landingCount;

  static int? countFor(int tab, AppServices services) {
    switch (tab) {
      case 0: // Command -> Hub: open tasks due today (same as Hub's Today · N)
        final state = fmt.m(services.store.state.value);
        final tasks = fmt.lm(state['tasks']);
        final todays = tasks.where((t) {
          final st = fmt.s(t['STATUS']).toLowerCase();
          return st == 'today';
        }).length;
        return todays > 0 ? todays : null;
      case 1: // Channels -> Inbox: unread inbox items (same filter InboxView uses: STATUS == 'new')
        final state = fmt.m(services.store.state.value);
        final feed = fmt.lm(state['feed']);
        final unread = feed.where((m) => fmt.s(m['STATUS']) == 'new').length;
        return unread > 0 ? unread : null;
      case 2: // Projects -> Practice: number of practice entries in portfolio
        final portfolio = fmt.m(services.store.portfolio.value);
        final items = fmt.lm(portfolio['items']);
        return items.isNotEmpty ? items.length : null;
      case 3: // Personal -> Rhythm: today's day blocks
        final dayData = fmt.m(services.store.day.value);
        final blocks = fmt.l(dayData['blocks']);
        return blocks.isNotEmpty ? blocks.length : null;
      case 4: // Systems -> Settings: no count
      default:
        return null;
    }
  }

  static Listenable? listenableFor(int tab, AppServices services) {
    switch (tab) {
      case 0:
      case 1:
        return services.store.state;
      case 2:
        return services.store.portfolio;
      case 3:
        return services.store.day;
      default:
        return null;
    }
  }

  Widget _buildLandingTab(BuildContext context, bool selected) {
    final baseLabel = subs[0].label.toUpperCase();
    final listenable =
        services != null && tab != null ? listenableFor(tab!, services!) : null;

    Widget renderWithCount(int? count) {
      final text =
          (count != null && count > 0) ? '$baseLabel · $count' : baseLabel;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onSelect(0),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.center,
          child: Text(
            text,
            style: T.label.copyWith(
              // The landing label is Inter ExtraBold (w800) in the app's green, bright when selected and dim
              // when not (BI26100102). T.label itself is untouched: other labels share it.
              fontWeight: FontWeight.w800,
              color: selected ? C.green : C.greenDim,
            ),
          ),
        ),
      );
    }

    if (landingCount != null) {
      return renderWithCount(landingCount);
    }

    if (listenable != null) {
      return ListenableBuilder(
        listenable: listenable,
        builder: (context, _) {
          final count =
              services != null && tab != null ? countFor(tab!, services!) : null;
          return renderWithCount(count);
        },
      );
    }

    final count =
        services != null && tab != null ? countFor(tab!, services!) : null;
    return renderWithCount(count);
  }

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
          if (i == 0) {
            // BI26092606: landing sub-tab rendered as a plain uppercase
            // section title (SectionLabel typography, no box/pill/fill)
            // with live count ("HUB · 12"), not a green button.
            return _buildLandingTab(context, selected);
          }
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onSelect(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                // BN26090606: rounded-rectangle matching small-button radius
                color: selected ? C.greenBg : Colors.transparent,
                borderRadius: BorderRadius.circular(Sz.rSm),
                border: selected ? Border.all(color: C.greenDim) : null,
              ),
              child: Center(
                child: Text(
                  subs[i].label,
                  style: (selected
                          ? T.body2.copyWith(
                              color: C.greenBright,
                              fontWeight: FontWeight.w600)
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

typedef _SubTabBar = SubTabBar;



/// App bar shared by the shell and pushed views: brand, title, equicycle
/// context, sync indicator. The shell passes [onMenu] to render a hamburger
/// icon in the actions trailing area; secondary screens omit it and get the
/// back arrow from the navigator instead.
class ShellAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ShellAppBar({
    super.key,
    required this.title,
    this.chipSource,
    this.showBrand = true,
    this.actions = const [],
    this.onMenu,
  });
  final String title;

  /// BI26092622: the subtle status chip after the title. Null means no chip.
  final StatusChipSource? chipSource;
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
            if (canPop)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.of(context).maybePop();
                },
                child: const BrandMark(size: 26),
              )
            else
              const BrandMark(size: 26),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: T.title, overflow: TextOverflow.ellipsis),
                // BI26100541: the status chips sit on their own line under the title, so the
                // title is never cut short. The cycle line leads, the chip follows.
                ListenableBuilder(
                  listenable: services.store.state,
                  builder: (context, _) {
                    final eq =
                        fmt.m(fmt.m(services.store.state.value)['time']);
                    final line = fmt.s(eq['eqShort']);
                    if (line.isEmpty && chipSource == null) return const SizedBox.shrink();
                    return Row(
                      children: [
                        if (line.isNotEmpty)
                          Flexible(
                            child: Text(line,
                                style: T.monoSmall.copyWith(fontSize: 9.5),
                                overflow: TextOverflow.ellipsis),
                          ),
                        if (chipSource != null)
                          StatusChipLabel(source: chipSource!, separator: line.isNotEmpty),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        ...actions,
        // BI26092617: the sync indicator, then the hamburger, right-most on every view.
        const SyncIndicator(),
        IconButton(
          icon: const Icon(Icons.menu_rounded),
          tooltip: 'Navigation menu',
          onPressed: () {
            HapticFeedback.selectionClick();
            (onMenu ?? () => openMenu(context))();
          },
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

/// The sync mark's state, kept apart from the widget so it can be tested without a service tree.
enum SyncMark { synced, waiting, offline }

/// BI26100539: green when online with nothing waiting, yellow while a sync runs or changes wait,
/// offline when there is no connection.
SyncMark syncMarkFor({required bool online, required bool busy, required int pending}) {
  if (!online) return SyncMark.offline;
  return busy || pending > 0 ? SyncMark.waiting : SyncMark.synced;
}

/// The words behind the mark: its screen-reader label and its tap message.
String syncMarkLabel(SyncMark mark, int pending) => switch (mark) {
      SyncMark.offline => 'Offline',
      SyncMark.waiting => pending > 0 ? '$pending waiting to sync' : 'Syncing',
      SyncMark.synced => 'All synced',
    };

/// One stroked cloud in the app bar (BI26100539): green when all is synced, yellow when something
/// waits, a crossed cloud offline. The count lives in the tap message, not a badge.
class SyncCloud extends StatelessWidget {
  const SyncCloud({super.key, required this.mark, required this.label, this.onTap});
  final SyncMark mark;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final icon = switch (mark) {
      SyncMark.offline => const Icon(Icons.cloud_off_outlined, size: 18, color: C.text3),
      SyncMark.waiting => const Icon(Icons.cloud_outlined, size: 18, color: C.amber),
      SyncMark.synced => const Icon(Icons.cloud_outlined, size: 18, color: C.green),
    };
    return Semantics(
      label: label,
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(10), child: ExcludeSemantics(child: icon)),
      ),
    );
  }
}

class SyncIndicator extends StatelessWidget {
  const SyncIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([services.sync, services.outbox]),
      builder: (context, _) {
        final sync = services.sync;
        final pending = services.outbox.pending;
        final mark = syncMarkFor(
            online: sync.online, busy: sync.phase != SyncPhase.idle, pending: pending);
        return SyncCloud(
          mark: mark,
          label: syncMarkLabel(mark, pending),
          onTap: () {
            HapticFeedback.selectionClick();
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(pending > 0 && sync.online
                  ? '$pending waiting to sync'
                  : sync.statusLine),
              duration: const Duration(seconds: 2),
            ));
            if (sync.online) sync.fullSync();
          },
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
              label: 'Systems',
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
          _item(ctx, Icons.task_alt_rounded, 'Slate',
              () => go(const SlateView(), 'Slate')),
          _item(ctx, Icons.explore_rounded, 'Compass',
              () => go(const PlanningView(), 'Compass')),
          _item(ctx, Icons.calendar_month_rounded, 'Calendar',
              () => go(const CalendarView(), 'Calendar')),
          _item(ctx, Icons.notifications_rounded, 'Alerts',
              () => go(const NotificationsView(), 'Alerts')),
          // ── CHANNELS ─────────────────────────────────────────
          const SectionLabel('Channels'),
          // BN26091013: ChannelsHomeView dropped out of the bottom-nav
          // 4-tab row (Inbox is now the landing tab) -- kept reachable
          // here, same pattern as Buffer/Ideas/Media/Audit/Outbox.
          _item(ctx, Icons.dashboard_rounded, 'Channels',
              () => go(const ChannelsHomeView(), 'Channels')),
          _item(ctx, Icons.flag_rounded, 'Surfaced',
              () => go(const SurfacedView(), 'Surfaced')),
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
          _item(ctx, Icons.rocket_launch_rounded, 'Practice',
              () => go(const PracticeView(), 'Practice')),
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
          _item(ctx, Icons.school_rounded, 'Study',
              () => go(const LearningView(), 'Study')),
          _item(ctx, Icons.account_balance_wallet_rounded, 'Ledger',
              () => go(const FinanceView(), 'Ledger')),
          // BI26100207: Journal and Ideas are one item, Codex, each still on its own route.
          _item(ctx, Icons.auto_stories_rounded, 'Codex',
              () => go(const CodexView(), 'Codex'),
              badge: ideasCount > 0 ? '$ideasCount' : null),
          // BI26100207: the archetype spaces live under Identity, as on the web.
          _item(ctx, Icons.health_and_safety_rounded, 'Readiness',
              () => go(const ReadinessHost(), 'Readiness')),
          _item(ctx, Icons.badge_rounded, 'Identity',
              () => go(const IdentityView(), 'Identity')),
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
          // BG26091020: Ops + Security merged into one "Opsec" entry --
          // Security's stub content now renders as a section inside OpsView.
          _item(ctx, Icons.dns_rounded, 'Ops',
              () => go(const OpsView(), 'Ops')),
          _item(ctx, Icons.apps_rounded, 'Services',
              () => go(const HostedServicesView(), 'Services')),
          _item(ctx, Icons.folder_rounded, 'Hold',
              () => go(const FilesView(), 'Hold')),
          _item(ctx, Icons.play_circle_filled_rounded, 'Media',
              () => go(const MediaView(), 'Media')),
          _item(ctx, Icons.link_rounded, 'Audit',
              () => go(const AuditView(), 'Audit')),
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
    // BN26091004: no OfflineBanner here -- ShellAppBar already renders the
    // compact SyncIndicator in this slot whenever onMenu is unset (every
    // pushed secondary screen), so connectivity is already visible without
    // the amber banner duplicating it.
    // BI26100541: every view opened from the menu wears the same bar as the main pages: logo
    // (tap to go back), title, the chips line and the cloud.
    final services = AppScope.of(context);
    return Scaffold(
      appBar: ShellAppBar(
        title: title,
        chipSource: FreshnessChipSource(
          services,
          (c, t, page) => Navigator.push(
            c,
            MaterialPageRoute(builder: (_) => SecondaryScreen(title: t, child: page)),
          ),
        ),
      ),
      body: child,
    );
  }
}

/// Resolves a nav route key to its (view, title) pair.
(Widget, String)? viewForNavRoute(String route) {
  var r = route.toLowerCase().trim();
  if (r.startsWith('/')) r = r.substring(1);
  if (r.startsWith('api/')) r = r.substring(4);
  return switch (r) {
    'hub' || 'command' => (const HubView(), 'Hub'),
    'tasks' || 'slate' => (const SlateView(), 'Slate'),
    'planning' || 'plans' => (const PlanningView(), 'Compass'),
    'calendar' || 'events' => (const CalendarView(), 'Calendar'),
    'notifications' || 'alerts' => (const NotificationsView(), 'Alerts'),
    'channels' => (const ChannelsHomeView(), 'Channels'),
    'teams' => (const TeamsView(), 'Teams'),
    'surfaced' => (const SurfacedView(), 'Surfaced'),
    'inbox' => (const InboxView(), 'Inbox'),
    'buffer' || 'social' => (const SocialView(), 'Buffer'),
    'kanban' || 'jira' => (const JiraView(), 'Kanban'),
    'github' => (const GithubView(), 'GitHub'),
    'portfolio' || 'practice' => (const PracticeView(), 'Practice'),
    'products' => (const ProjectsView(cat: 'product'), 'Products'),
    'platforms' => (const ProjectsView(cat: 'platform'), 'Platforms'),
    'corporate' => (const CorporateView(), 'Corporate'),
    'rhythm' => (const RhythmView(), 'Rhythm'),
    'study' || 'learning' => (const LearningView(), 'Study'),
    'holdings' || 'finance' || 'ledger' =>(const FinanceView(), 'Ledger'),
    'codex' => (const CodexView(), 'Codex'),
    'identity' => (const IdentityView(), 'Identity'),
    'readiness' => (const ReadinessHost(), 'Readiness'),
    'journal' => (const JournalView(), 'Journal'),
    'ideas' => (const IdeasView(), 'Ideas'),
    'circle' || 'contacts' => (const ContactsView(), 'Contacts'),
    'family' => (const CircleView(ring: 'family'), 'Family'),
    'professional' => (const CircleView(ring: 'professional'), 'Professional'),
    'social_circle' => (const CircleView(ring: 'social'), 'Social'),
    'spaces' => (const SpacesView(), 'Spaces'),
    'ops' => (const OpsView(), 'Ops'),
    'services' || 'hosted' => (const HostedServicesView(), 'Services'),
    'files' || 'hold' => (const FilesView(), 'Hold'),
    'media' => (const MediaView(), 'Media'),
    'audit' => (const AuditView(), 'Audit'),
    'articles' => (const ArticlesView(), 'Articles'),
    'decisions' => (const DecisionsView(), 'Decisions & Risks'),
    'outbox' => (const OutboxView(), 'Outbox'),
    'settings' => (const SettingsView(), 'Settings'),
    'backlog' => (const SlateView(), 'Slate'),
    _ => null,
  };
}

/// Navigates to a view by route name (pushing SecondaryScreen, same as MenuSheet).
void openNavRoute(BuildContext context, String route) {
  final pair = viewForNavRoute(route);
  if (pair != null) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SecondaryScreen(title: pair.$2, child: pair.$1),
      ),
    );
  }
}
