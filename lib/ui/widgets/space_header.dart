import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/tab_memory.dart';
import 'common.dart';
import 'sub_tabs.dart';

/// BI26101802: the header Study set the pattern for, as one widget every sub-tab space wears: a search entry, then
/// exactly three tabs. The search is tailored to the space (its hint names what it finds, its hits are that space's own
/// data) and opens a full search screen. A space with nothing searchable yet passes [filterHits] built from the list it
/// shows, so the box still filters what is on screen.
const int spaceTabCount = 3;

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
  const SpaceTab(this.label, this.body);
  final String label;
  final Widget body;
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
  }) : assert(tabs.length == spaceTabCount, 'a space has exactly $spaceTabCount tabs');

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
    if (t == null || t < 0 || t >= spaceTabCount || !mounted) return;
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
      readTabIndex(AppScope.of(context).db, widget.space, spaceTabCount).then((saved) {
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
          child: SubTabs(
            key: ValueKey('${widget.space}-view-$_restored'),
            keyPrefix: widget.space,
            labels: [for (final t in widget.tabs) t.label],
            initialIndex: _tab,
            onChanged: (i) {
              _tab = i;
              try {
                writeTabIndex(AppScope.of(context).db, widget.space, i);
              } catch (_) {}
            },
            children: [for (final t in widget.tabs) t.body],
          ),
        ),
      ],
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
