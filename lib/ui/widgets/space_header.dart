import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/space_nav_prefs.dart';
import '../../util/tab_memory.dart';
import 'common.dart';
import 'space_rail.dart';
import 'sub_tabs.dart';

/// BI26101802: the header Study set the pattern for, as one widget every sub-tab space wears: a search entry, then
/// exactly three tabs. The search is tailored to the space (its hint names what it finds, its hits are that space's own
/// data) and opens a full search screen. A space with nothing searchable yet passes [filterHits] built from the list it
/// shows, so the box still filters what is on screen.
/// BI26102802: rail navigation inside spaces: vertical pill rail on the right edge holding up to five icons, one per
/// destination. Setting (Settings: Space navigation, Rail or Tabs) defaults to Rail, switchable back without restart.
const int spaceTabCount = 3;
const int maxSpaceDestinations = 5;

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
  final IconData? icon;

  IconData get effectiveIcon => icon ?? defaultIconFor(label);

  static IconData defaultIconFor(String label) {
    switch (label.trim().toLowerCase()) {
      case 'map': return Icons.map_outlined;
      case 'campus': return Icons.school_outlined;
      case 'tracks': return Icons.alt_route_rounded;
      case 'now': return Icons.radar_rounded;
      case 'today': return Icons.today_rounded;
      case 'services': return Icons.dns_rounded;
      case 'addresses': return Icons.alternate_email_rounded;
      case 'sign-ups': case 'signups': return Icons.subscriptions_outlined;
      case 'ai seats': case 'seats': return Icons.psychology_outlined;
      case 'browse': return Icons.folder_open_rounded;
      case 'recent': return Icons.history_rounded;
      case 'device': return Icons.phone_android_rounded;
      case 'storage': return Icons.inventory_2_outlined;
      case 'general': return Icons.tune_rounded;
      case 'study and notes': return Icons.edit_note_rounded;
      case 'account and sync': return Icons.sync_lock_rounded;
      case 'command': return Icons.terminal_rounded;
      case 'tasks': return Icons.task_alt_rounded;
      case 'register': return Icons.table_chart_outlined;
      case 'inbox': return Icons.inbox_rounded;
      case 'deck': return Icons.view_kanban_outlined;
      case 'teams': return Icons.groups_outlined;
      case 'tools': return Icons.construction_rounded;
      case 'overview': return Icons.dashboard_outlined;
      case 'leads': return Icons.trending_up_rounded;
      case 'practices': return Icons.business_center_outlined;
      case 'documents': return Icons.description_outlined;
      case 'calendar': return Icons.calendar_month_outlined;
      case 'rhythm': return Icons.speed_rounded;
      case 'review': return Icons.rate_review_outlined;
      case 'assets': return Icons.account_balance_outlined;
      case 'report': return Icons.assessment_outlined;
      case 'plan': return Icons.assignment_outlined;
      case 'transactions': return Icons.receipt_long_outlined;
      case 'portfolio': return Icons.folder_special_outlined;
      case 'focus': return Icons.center_focus_strong_rounded;
      case 'ideas': return Icons.lightbulb_outline_rounded;
      case 'articles': return Icons.article_outlined;
      case 'activity': return Icons.timeline_rounded;
      case 'audit': return Icons.fact_check_outlined;
      case 'status': return Icons.info_outline_rounded;
      case 'one': return Icons.looks_one_outlined;
      case 'two': return Icons.looks_two_outlined;
      case 'three': return Icons.looks_3_outlined;
      case 'four': return Icons.looks_4_outlined;
      case 'five': return Icons.looks_5_outlined;
      default: return Icons.circle_outlined;
    }
  }
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

/// The search entry, then destinations inside a space.
/// In Tabs mode: horizontal tab bar with green underline under the search entry.
/// In Rail mode: vertical pill rail on the right edge holding up to 5 icons.
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
    this.mode,
    this.primaryFab,
    this.secondaryFabs,
  }) : assert(tabs.length >= 3 && tabs.length <= maxSpaceDestinations, 'a space has between 3 and $maxSpaceDestinations destinations');

  /// Stable id for the key prefix and the remembered tab.
  final String space;
  final String? searchHint;
  final List<SpaceTab> tabs;
  final List<SpaceHit> Function(BuildContext)? hits;
  final void Function(BuildContext)? onSearch;
  final int initialTab;
  final Key? searchKey;

  /// A quiet line between the search entry and the tabs/canvas.
  final String? subtitle;
  final Key? subtitleKey;

  /// Something that sits above the search entry (OpSec's headline line).
  final Widget? top;
  final bool showSearch;
  final SpaceTabController? controller;

  /// Mode override (Rail or Tabs). When null, reads SpaceNavPrefs.instance.mode.
  final SpaceNavMode? mode;

  /// Optional primary and secondary FABs for layout coordination.
  final Widget? primaryFab;
  final List<Widget>? secondaryFabs;

  @override
  State<SpaceView> createState() => _SpaceViewState();
}

class _SpaceViewState extends State<SpaceView> {
  late int _tab = widget.initialTab;
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
    if (t == null || t < 0 || t >= widget.tabs.length || !mounted) return;
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
      SpaceNavPrefs.instance.ensureLoaded(AppScope.of(context).db);
      readTabIndex(AppScope.of(context).db, widget.space, widget.tabs.length).then((saved) {
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
    return ListenableBuilder(
      listenable: SpaceNavPrefs.instance,
      builder: (context, _) {
        final activeMode = widget.mode ?? SpaceNavPrefs.instance.mode;
        final hasSearch = widget.showSearch && widget.searchHint != null;
        final activeIndex = _tab.clamp(0, widget.tabs.length - 1);

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
              child: activeMode == SpaceNavMode.tabs
                  ? SubTabs(
                      key: ValueKey('${widget.space}-view-$_restored'),
                      keyPrefix: widget.space,
                      labels: [for (final t in widget.tabs) t.label],
                      initialIndex: activeIndex,
                      onChanged: (i) {
                        _tab = i;
                        try {
                          writeTabIndex(AppScope.of(context).db, widget.space, i);
                        } catch (_) {}
                      },
                      children: [for (final t in widget.tabs) t.body],
                    )
                  : Stack(
                      key: ValueKey('${widget.space}-rail-stack'),
                      children: [
                        // Canvas: padded on the right so content never sits under the rail
                        Padding(
                          padding: const EdgeInsets.only(right: 68),
                          child: KeyedSubtree(
                            key: ValueKey('${widget.space}-canvas-$activeIndex'),
                            child: widget.tabs[activeIndex].body,
                          ),
                        ),
                        // Floating rail: right edge, sits vertically above the 2 secondary FAB slots
                        Positioned(
                          right: 20,
                          bottom: 184,
                          child: SpaceRail(
                            keyPrefix: widget.space,
                            tabs: widget.tabs,
                            currentIndex: activeIndex,
                            onSelect: (i) {
                              setState(() {
                                _tab = i;
                                _restored++;
                              });
                              try {
                                writeTabIndex(AppScope.of(context).db, widget.space, i);
                              } catch (_) {}
                            },
                          ),
                        ),
                        // Stacked secondary FABs if provided
                        if (widget.secondaryFabs != null) ...[
                          for (var i = 0; i < widget.secondaryFabs!.length; i++)
                            Positioned(
                              right: 24,
                              bottom: 82 + i * 50.0,
                              child: widget.secondaryFabs![i],
                            ),
                        ],
                        // Primary FAB if provided
                        if (widget.primaryFab != null)
                          Positioned(
                            right: 16,
                            bottom: 16,
                            child: widget.primaryFab!,
                          ),
                      ],
                    ),
            ),
          ],
        );
      },
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
