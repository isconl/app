import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart' show HapticFeedback;

import '../../app_scope.dart';
import '../../data/db.dart';
import '../../theme.dart';
import '../../util/tab_memory.dart';
import 'common.dart';
import 'space_manifest.dart';
import 'sub_tabs.dart';

/// BI26101802: the header Study set the pattern for, as one widget every sub-tab space wears: a search entry, then
/// exactly three tabs. The search is tailored to the space (its hint names what it finds, its hits are that space's own
/// data) and opens a full search screen. A space with nothing searchable yet passes [filterHits] built from the list it
/// shows, so the box still filters what is on screen.
const int spaceTabCount = 3;

/// BI26102802: the rail is built for up to five destinations, so a space can grow past three without a redesign.
const int spaceMaxTabs = 5;

/// BI26102802 (Sconl's sketch, 28 Oct 2026): how a space moves between its destinations. [rail] is a vertical pill
/// of icons on the right edge, above the floating buttons; [tabs] is the row of tabs under the search entry.
enum SpaceNav { rail, tabs }

/// The one switch for every space, read once at start and changed live from Settings > General. Bare widget tests
/// never load it, so they keep [SpaceNav.tabs] and tap tabs as before; the app loads the stored choice, Rail when
/// none is stored.
class SpaceNavMode {
  SpaceNavMode._();

  static final ValueNotifier<SpaceNav> mode = ValueNotifier(SpaceNav.tabs);
  static const _key = 'space.nav.v1';

  static Future<void> load(AppDb db) async {
    try {
      final v = (await db.getSnapshot(_key))?.$1;
      mode.value = v is Map && v['mode'] == 'tabs' ? SpaceNav.tabs : SpaceNav.rail;
    } catch (_) {
      mode.value = SpaceNav.rail;
    }
  }

  static Future<void> set(AppDb db, SpaceNav m) async {
    mode.value = m;
    try {
      await db.putSnapshot(_key, {'mode': m.name});
    } catch (_) {}
  }
}

/// BI26102802: the rail is icon-only, so every destination label in the app has its own icon here, in one table, and
/// a test fails when a space gains a label this table does not know. [SpaceTab.icon] overrides it for one space.
const Map<String, IconData> spaceTabIcons = {
  // BI26102890: the five-destination list (space_manifest.dart). Activity is slot 5 in every space.
  'Activity': Icons.history_rounded,
  'Notices': Icons.notifications_rounded,
  'Register': Icons.view_list_rounded,
  'Equicycle': Icons.blur_circular_rounded,
  'Month': Icons.calendar_month_rounded,
  'Planner': Icons.view_week_rounded,
  'Practices': Icons.workspaces_rounded,
  'Platforms': Icons.layers_rounded,
  'Focus': Icons.center_focus_strong_rounded,
  'Assets': Icons.account_balance_rounded,
  'Shared': Icons.share_rounded,
  'Hosts': Icons.computer_rounded,
  'Security': Icons.shield_rounded,
  // Hub, Compass
  'Now': Icons.bolt_rounded,
  'Today': Icons.today_rounded,
  'Services': Icons.dns_rounded,
  'Next': Icons.upcoming_rounded,
  'Later': Icons.more_time_rounded,
  // Slate, Ledger, Practice
  'Overview': Icons.space_dashboard_rounded,
  'Grid': Icons.grid_view_rounded,
  'Asks': Icons.contact_support_rounded,
  'Transactions': Icons.receipt_long_rounded,
  'Plan': Icons.savings_rounded,
  'Documents': Icons.description_rounded,
  'Enquiries': Icons.contact_mail_rounded,
  // Study, Codex
  'Map': Icons.map_rounded,
  'Campus': Icons.school_rounded,
  'Tracks': Icons.route_rounded,
  'Ideas': Icons.lightbulb_rounded,
  'Journals': Icons.menu_book_rounded,
  'Scans': Icons.document_scanner_rounded,
  // Inbox, Tools, Deck
  'Unread': Icons.mark_email_unread_rounded,
  'Waiting': Icons.hourglass_top_rounded,
  'All': Icons.all_inbox_rounded,
  'Jira': Icons.view_kanban_rounded,
  'Social': Icons.forum_rounded,
  'GitHub': Icons.code_rounded,
  'Boards': Icons.dashboard_rounded,
  'Drafts': Icons.edit_note_rounded,
  'Sent': Icons.send_rounded,
  // Corporate, Teams, Projects
  'Entities': Icons.business_rounded,
  'Work': Icons.work_rounded,
  'People': Icons.people_alt_rounded,
  'Health': Icons.monitor_heart_rounded,
  'Active': Icons.play_circle_rounded,
  'Building': Icons.construction_rounded,
  'Shipped': Icons.rocket_launch_rounded,
  // Rhythm
  'Habits': Icons.repeat_rounded,
  'Year': Icons.calendar_month_rounded,
  // OpSec, Hold, Accounts
  'Logs': Icons.notes_rounded,
  'Browse': Icons.folder_open_rounded,
  'Recent': Icons.history_rounded,
  'Device': Icons.smartphone_rounded,
  'Addresses': Icons.alternate_email_rounded,
  'Sign-ups': Icons.how_to_reg_rounded,
  'AI seats': Icons.smart_toy_rounded,
  // Settings
  'General': Icons.tune_rounded,
  'Study and notes': Icons.sticky_note_2_rounded,
  'Account and sync': Icons.manage_accounts_rounded,
};

/// The icon a destination wears on the rail: its own, else the table's, else a plain dot (which the test forbids).
IconData spaceTabIconFor(SpaceTab t) => t.icon ?? spaceTabIcons[t.label] ?? Icons.circle_outlined;

/// One search result: a title, a line under it, and what tapping it opens.
class SpaceHit {
  const SpaceHit({required this.title, this.subtitle = '', this.onOpen, this.tab});
  final String title;
  final String subtitle;

  /// Opens the hit's own detail screen, when the space has one.
  final void Function(BuildContext context)? onOpen;

  /// Otherwise the hit sends the space to the tab that holds it.
  final int? tab;
}

/// The words of [query] must all appear, in any order, in the title or subtitle; case does not matter.
List<SpaceHit> filterHits(List<SpaceHit> all, String query, {int limit = 60}) {
  final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return const [];
  final out = <SpaceHit>[];
  for (final h in all) {
    final hay = '${h.title} ${h.subtitle}'.toLowerCase();
    if (words.every(hay.contains)) {
      out.add(h);
      if (out.length >= limit) break;
    }
  }
  return out;
}

/// Lets a space's own code switch its tab (OpSec jumps to Logs when a service's logs are asked for).
class SpaceTabController extends ChangeNotifier {
  int? _requested;
  int? get requested => _requested;
  void select(int tab) {
    _requested = tab;
    notifyListeners();
  }
}

class SpaceTab {
  const SpaceTab(this.label, this.body, {this.icon});
  final String label;
  final Widget body;

  /// The rail's icon for this destination when [spaceTabIcons] should not decide it.
  final IconData? icon;
}

/// The search entry that sits above the three tabs. Same look as Study's.
class SpaceSearchEntry extends StatelessWidget {
  const SpaceSearchEntry({super.key, required this.hint, required this.onTap});
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: onTap,
      child: Row(children: [
        const Icon(Icons.search_rounded, size: 18, color: C.text3),
        const SizedBox(width: 10),
        Expanded(child: Text(hint, style: T.body2.copyWith(color: C.text3), maxLines: 1, overflow: TextOverflow.ellipsis)),
      ]),
    );
  }
}

/// The search entry, then exactly three tabs. [onSearch] opens the space's search; when it is null the entry opens a
/// [SpaceSearchScreen] over [hits].
class SpaceView extends StatefulWidget {
  const SpaceView({
    super.key,
    required this.space,
    this.searchHint,
    required this.tabs,
    this.hits,
    this.onSearch,
    this.initialTab = 0,
    this.searchKey,
    this.subtitle,
    this.subtitleKey,
    this.top,
    this.showSearch = true,
    this.controller,
  }) : assert(tabs.length >= 2 && tabs.length <= spaceMaxTabs, 'a space has two to $spaceMaxTabs destinations');

  /// Stable id for the key prefix and the remembered tab.
  final String space;
  final String? searchHint;
  final List<SpaceTab> tabs;
  final List<SpaceHit> Function(BuildContext)? hits;
  final void Function(BuildContext)? onSearch;
  final int initialTab;
  final Key? searchKey;

  /// A quiet line between the search entry and the tabs.
  final String? subtitle;
  final Key? subtitleKey;

  /// Something that sits above the search entry (OpSec's headline line).
  final Widget? top;
  final bool showSearch;
  final SpaceTabController? controller;

  @override
  State<SpaceView> createState() => _SpaceViewState();
}

class _SpaceViewState extends State<SpaceView> {
  // BI26102890: the space's own destinations laid onto its five slots (space_manifest.dart).
  List<SpaceTab> get _tabs => fiveDestinations(widget.space, widget.tabs);
  // A space never opens on an Overview that is only a placeholder: it opens on its first real destination.
  late int _tab = widget.initialTab == 0 ? firstRealDestination(_tabs) : widget.initialTab;
  int _restored = 0;
  bool _read = false;

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_onRequest);
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onRequest);
    super.dispose();
  }

  void _onRequest() {
    final t = widget.controller?.requested;
    if (t == null || t < 0 || t >= _tabs.length || !mounted) return;
    setState(() {
      _tab = t;
      _restored++;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_read) return;
    _read = true;
    try {
      readTabIndex(AppScope.of(context).db, widget.space, _tabs.length).then((saved) {
        if (mounted && saved != null && saved != _tab) {
          setState(() {
            _tab = saved;
            _restored++;
          });
        }
      });
    } catch (_) {
      // No database in scope (a bare widget test): the default tab applies.
    }
  }

  Future<void> _search() async {
    if (!widget.showSearch || widget.searchHint == null) return;
    if (widget.onSearch != null) return widget.onSearch!(context);
    final hint = widget.searchHint!;
    final picked = await Navigator.push<SpaceHit>(
      context,
      MaterialPageRoute(
        builder: (ctx) => SpaceSearchScreen(title: hint, hint: hint, hits: widget.hits?.call(ctx) ?? const []),
      ),
    );
    if (picked?.tab != null && mounted) {
      setState(() {
        _tab = picked!.tab!;
        _restored++;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasSearch = widget.showSearch && widget.searchHint != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.top != null)
          Padding(
            padding: EdgeInsets.fromLTRB(14, 10, 14, hasSearch ? 0 : 6),
            child: widget.top,
          ),
        if (hasSearch)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: KeyedSubtree(
              key: widget.searchKey ?? Key('${widget.space}-search-entry'),
              child: SpaceSearchEntry(hint: widget.searchHint!, onTap: _search),
            ),
          ),
        if (widget.subtitle != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(widget.subtitle!, key: widget.subtitleKey, style: T.small.copyWith(color: C.text3)),
          ),
        Expanded(
          child: ValueListenableBuilder<SpaceNav>(
            valueListenable: SpaceNavMode.mode,
            builder: (context, mode, _) => mode == SpaceNav.rail
                ? SpaceRailBody(
                    key: ValueKey('${widget.space}-rail-view-$_restored'),
                    space: widget.space,
                    tabs: _tabs,
                    index: _tab.clamp(0, _tabs.length - 1),
                    onSelect: (i) {
                      setState(() => _tab = i);
                      _remember(i);
                    },
                  )
                : SubTabs(
                    key: ValueKey('${widget.space}-view-$_restored'),
                    keyPrefix: widget.space,
                    labels: [for (final t in _tabs) t.label],
                    initialIndex: _tab,
                    onChanged: (i) {
                      _tab = i;
                      _remember(i);
                    },
                    children: [for (final t in _tabs) t.body],
                  ),
          ),
        ),
      ],
    );
  }

  void _remember(int i) {
    try {
      writeTabIndex(AppScope.of(context).db, widget.space, i);
    } catch (_) {}
  }
}

/// BI26102802: a space in rail mode. The destination fills the canvas; the rail floats on the right edge, centred
/// over the floating-button column and just above its second small button ([ViewFab] slot 1), as in Sconl's sketch:
/// rail, secondary, secondary, primary. A destination is built the first time it is opened and kept after, so its
/// scroll position and loaded data survive switching away and back, and a space never loads all of them at once.
/// The rail slides off while the canvas scrolls down and comes back on the way up, so it never sits over reading.
class SpaceRailBody extends StatefulWidget {
  const SpaceRailBody({super.key, required this.space, required this.tabs, required this.index, required this.onSelect});

  final String space;
  final List<SpaceTab> tabs;
  final int index;
  final ValueChanged<int> onSelect;

  /// Centred over the 56 dp primary button at the screen's 16 dp margin, the same line [ViewFab] uses.
  static const double right = 16 + 28 - SpaceRail.width / 2;

  /// Clear of two small buttons: [ViewFab] slot 1's top (a small button takes 48 dp with its tap padding), plus a
  /// 10 dp gap, the stack's own spacing.
  static const double bottom = ViewFab.bottom + ViewFab.slotStep + 48 + 10;

  @override
  State<SpaceRailBody> createState() => _SpaceRailBodyState();
}

class _SpaceRailBodyState extends State<SpaceRailBody> {
  late final Set<int> _built = {widget.index};
  bool _shown = true;

  @override
  void didUpdateWidget(covariant SpaceRailBody old) {
    super.didUpdateWidget(old);
    _built.add(widget.index);
  }

  bool _onScroll(UserScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    final show = switch (n.direction) {
      ScrollDirection.reverse => false, // reading on: the content moves up, the rail steps aside
      ScrollDirection.forward => true, // heading back up: the rail returns
      ScrollDirection.idle => _shown,
    };
    if (show != _shown) setState(() => _shown = show);
    return false;
  }

  void _select(int i) {
    if (i == widget.index) return;
    HapticFeedback.selectionClick();
    setState(() {
      _built.add(i);
      _shown = true;
    });
    widget.onSelect(i);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: NotificationListener<UserScrollNotification>(
            onNotification: _onScroll,
            child: IndexedStack(
              index: widget.index,
              sizing: StackFit.expand,
              children: [
                for (var i = 0; i < widget.tabs.length; i++)
                  KeyedSubtree(
                    key: ValueKey('${widget.space}-rail-page-$i'),
                    child: _built.contains(i) ? widget.tabs[i].body : const SizedBox.shrink(),
                  ),
              ],
            ),
          ),
        ),
        Positioned(
          right: SpaceRailBody.right,
          bottom: SpaceRailBody.bottom,
          child: AnimatedSlide(
            offset: _shown ? Offset.zero : const Offset(1.6, 0),
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: _shown ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: IgnorePointer(
                ignoring: !_shown,
                child: SpaceRail(space: widget.space, tabs: widget.tabs, index: widget.index, onSelect: _select),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The rail itself: a raised pill holding one icon per destination. The active one sits on the nav green's pill with
/// the bright green icon, the rest are dim; each is a 48 dp target whose name shows on long press and is read out by
/// a screen reader.
class SpaceRail extends StatelessWidget {
  const SpaceRail({super.key, required this.space, required this.tabs, required this.index, required this.onSelect});

  final String space;
  final List<SpaceTab> tabs;
  final int index;
  final ValueChanged<int> onSelect;

  static const double width = 56;
  static const double item = 48;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: ValueKey('$space-rail'),
      color: C.panel,
      elevation: 3,
      shadowColor: Colors.black54,
      shape: const StadiumBorder(side: BorderSide(color: C.border)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: SizedBox(
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < tabs.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: _RailItem(
                    key: ValueKey('$space-rail-${tabs[i].label.toLowerCase()}'),
                    label: tabs[i].label,
                    icon: spaceTabIconFor(tabs[i]),
                    selected: i == index,
                    onTap: () => onSelect(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({super.key, required this.label, required this.icon, required this.selected, required this.onTap});

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        preferBelow: false,
        child: SizedBox(
          width: SpaceRail.item,
          height: SpaceRail.item,
          child: Material(
            color: selected ? NavTint.bgOn : Colors.transparent,
            shape: StadiumBorder(side: selected ? const BorderSide(color: NavTint.border) : BorderSide.none),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: onTap,
              child: Icon(icon, size: 22, color: selected ? NavTint.fg : C.text3),
            ),
          ),
        ),
      ),
    );
  }
}

/// A plain search screen over a list of hits: a field, then the hits that match every word typed.
class SpaceSearchScreen extends StatefulWidget {
  const SpaceSearchScreen({super.key, required this.title, required this.hint, required this.hits});
  final String title;
  final String hint;
  final List<SpaceHit> hits;

  @override
  State<SpaceSearchScreen> createState() => _SpaceSearchScreenState();
}

class _SpaceSearchScreenState extends State<SpaceSearchScreen> {
  final _field = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final found = filterHits(widget.hits, _q);
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          key: const Key('space-search-field'),
          controller: _field,
          autofocus: true,
          decoration: InputDecoration(hintText: widget.hint, border: InputBorder.none),
          style: T.body,
          onChanged: (v) => setState(() => _q = v),
        ),
      ),
      body: _q.trim().isEmpty
          ? const EmptyState('Search', 'Type to search this space.', icon: Icons.search_rounded)
          : found.isEmpty
              ? EmptyState('No matches', 'Nothing here matches "${_q.trim()}".', icon: Icons.search_off_rounded)
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
                  itemCount: found.length,
                  itemBuilder: (ctx, i) => ListTile(
                    key: Key('space-hit-$i'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(found[i].title, style: T.w600(T.body2)),
                    subtitle: found[i].subtitle.isEmpty ? null : Text(found[i].subtitle, style: T.small.copyWith(color: C.text3), maxLines: 2, overflow: TextOverflow.ellipsis),
                    onTap: () {
                      if (found[i].onOpen != null) {
                        found[i].onOpen!(ctx);
                      } else {
                        Navigator.pop(ctx, found[i]);
                      }
                    },
                  ),
                ),
    );
  }
}
