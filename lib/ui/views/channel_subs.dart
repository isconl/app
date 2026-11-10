import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../data/db.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../nav_menu.dart' show parseNavGroups;
import '../widgets/common.dart';
import '../widgets/reader.dart';
import 'github.dart';
import 'jira.dart';
import 'social.dart';

/// BI26092637: the Channels sub-tabs come from `/api/nav`, never from a list in
/// the app. Mobile shows Inbox (landing), Deck, Teams and Tools; the nav views
/// jira, social and github fold into the one Tools tab, at the position of
/// the first of them. Press is not a mobile sub-tab (Sconl, 27 Sep 2026).
enum ChannelKind { inbox, deck, teams, tools }

class ChannelSub {
  const ChannelSub(this.kind, this.label);
  final ChannelKind kind;
  final String label;
}

const toolViews = ['jira', 'social', 'github'];

ChannelKind? _kindOf(String view) => switch (view) {
      'inbox' => ChannelKind.inbox,
      'canvas' || 'deck' => ChannelKind.deck,
      'teams' => ChannelKind.teams,
      'tools' || 'jira' || 'social' || 'github' => ChannelKind.tools,
      _ => null,
    };

/// What a nav payload gives the Channels tab, in the server's order. With no nav yet
/// (first run, offline) the default is Inbox, Deck, Teams, Tools.
List<ChannelSub> channelPlan(dynamic navValue) {
  final flow = parseNavGroups(navValue).where((g) => g.key == 'flow').toList();
  final out = <ChannelSub>[];
  if (flow.isNotEmpty) {
    for (final item in flow.first.items) {
      final kind = _kindOf(item.view);
      if (kind == null) continue;
      if (out.any((s) => s.kind == kind)) continue;
      out.add(ChannelSub(kind, kind == ChannelKind.tools ? 'Tools' : item.label));
    }
  }
  if (out.isEmpty) {
    return const [
      ChannelSub(ChannelKind.inbox, 'Inbox'),
      ChannelSub(ChannelKind.deck, 'Deck'),
      ChannelSub(ChannelKind.teams, 'Teams'),
      ChannelSub(ChannelKind.tools, 'Tools'),
    ];
  }
  return out;
}

/// The tool views the nav offers, in nav order (a subset of [toolViews]); all three without a nav.
List<String> toolViewsIn(dynamic navValue) {
  final flow = parseNavGroups(navValue).where((g) => g.key == 'flow').toList();
  final found = <String>[];
  if (flow.isNotEmpty) {
    for (final item in flow.first.items) {
      if (toolViews.contains(item.view) && !found.contains(item.view)) found.add(item.view);
    }
  }
  return found.isEmpty ? List.of(toolViews) : found;
}

/// Which tool Tools shows, remembered across restarts. Tiles elsewhere set it before opening Tools.
class ToolsPrefs extends ChangeNotifier {
  ToolsPrefs._();
  static final ToolsPrefs instance = ToolsPrefs._();

  @visibleForTesting
  ToolsPrefs.forTesting();

  static const _key = 'channels.tools.v1';
  String selected = 'jira';
  bool _loaded = false;

  Future<void> ensureLoaded(AppDb db) async {
    if (_loaded) return;
    _loaded = true;
    try {
      final v = (await db.getSnapshot(_key))?.$1;
      if (v is Map && toolViews.contains(v['selected'])) {
        selected = v['selected'] as String;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> select(String view, {AppDb? db}) async {
    if (!toolViews.contains(view)) return;
    selected = view;
    notifyListeners();
    if (db != null) {
      try {
        await db.putSnapshot(_key, {'selected': view});
      } catch (_) {}
    }
  }
}

/// Tools: Kanban, Buffer and GitHub behind one switch, each view unchanged.
class ToolsView extends StatefulWidget {
  const ToolsView({super.key, this.views = toolViews, this.prefs});
  final List<String> views;

  /// Replaced in tests.
  final ToolsPrefs? prefs;

  @override
  State<ToolsView> createState() => _ToolsViewState();
}

class _ToolsViewState extends State<ToolsView> {
  ToolsPrefs get _prefs => widget.prefs ?? ToolsPrefs.instance;

  static const _labels = {'jira': 'Kanban', 'social': 'Buffer', 'github': 'GitHub'};

  @override
  void initState() {
    super.initState();
    _prefs.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.prefs == null) _prefs.ensureLoaded(AppScope.of(context).db);
    });
  }

  @override
  void dispose() {
    _prefs.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final views = widget.views.isEmpty ? toolViews : widget.views;
    final current = views.contains(_prefs.selected) ? _prefs.selected : views.first;
    final db = widget.prefs == null ? AppScope.of(context).db : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
        child: SegmentedButton<String>(
          key: const Key('tools-switch'),
          style: SegmentedButton.styleFrom(selectedBackgroundColor: C.green, selectedForegroundColor: C.textInverse),
          segments: [for (final v in views) ButtonSegment(value: v, label: Text(_labels[v] ?? v))],
          selected: {current},
          onSelectionChanged: (s) => _prefs.select(s.first, db: db),
        ),
      ),
      Expanded(
        child: switch (current) {
          'social' => const SocialView(),
          'github' => const _GithubScroll(),
          _ => const JiraView(),
        },
      ),
    ]);
  }
}

class _GithubScroll extends StatelessWidget {
  const _GithubScroll();
  @override
  Widget build(BuildContext context) => const SingleChildScrollView(padding: EdgeInsets.fromLTRB(14, 6, 14, 96), child: GithubView());
}

// ---- Deck ----

class DeckBoard {
  DeckBoard(this.id, this.title, this.staged);
  final String id;
  final String title;
  final int staged;
}

class DeckDraft {
  DeckDraft(this.id, this.title, this.updatedAt);
  final String id;
  final String title;
  final DateTime? updatedAt;
}

class DeckStudio {
  DeckStudio(this.boards, this.drafts);
  final List<DeckBoard> boards;
  final List<DeckDraft> drafts;
  bool get isEmpty => boards.isEmpty && drafts.isEmpty;

  /// `{boards:[{id,title,staged}], drafts:[{id,title,updatedAt}]}` from `GET /api/deck/studio`.
  static DeckStudio parse(dynamic json) {
    final m = fmt.m(json);
    return DeckStudio(
      [
        for (final b in fmt.lm(m['boards']))
          if (fmt.s(b['title']).isNotEmpty) DeckBoard(fmt.s(b['id']), fmt.s(b['title']), fmt.i(b['staged'])),
      ],
      [
        for (final d in fmt.lm(m['drafts']))
          if (fmt.s(d['title']).isNotEmpty) DeckDraft(fmt.s(d['id']), fmt.s(d['title']), fmt.parseDate(d['updatedAt'])),
      ],
    );
  }
}

/// Deck on the phone: the studio's boards and drafts, read-only for now.
class DeckChannelView extends StatelessWidget {
  const DeckChannelView({super.key});

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return SnapshotView(
      snapshot: services.store.deckStudio,
      empty: const EmptyState('Deck is not connected yet', 'Boards and drafts appear here once the hub serves the studio.', icon: Icons.dashboard_customize_rounded),
      builder: (context, data) {
        final studio = DeckStudio.parse(data);
        if (studio.isEmpty) {
          return const EmptyState('Nothing in the studio', 'Boards and drafts appear here as they are made.', icon: Icons.dashboard_customize_rounded);
        }
        final now = DateTime.now();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (studio.boards.isNotEmpty) ...[
            const SectionLabel('Boards'),
            for (final b in studio.boards)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Panel(
                  key: ValueKey('board-${b.id}'),
                  child: Row(children: [
                    Expanded(child: Text(b.title, style: T.body2.copyWith(color: C.text))),
                    Text('${b.staged} staged', style: T.monoSmall),
                  ]),
                ),
              ),
          ],
          if (studio.drafts.isNotEmpty) ...[
            const SectionLabel('Drafts'),
            for (final d in studio.drafts)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Panel(
                  key: ValueKey('draft-${d.id}'),
                  onTap: () => Navigator.push<void>(context, MaterialPageRoute(builder: (_) => DeckDraftScreen(id: d.id, title: d.title))),
                  child: Row(children: [
                    Expanded(child: Text(d.title, style: T.body2.copyWith(color: C.text))),
                    Text(d.updatedAt == null ? '' : 'updated ${_ago(d.updatedAt!, now)}', style: T.monoSmall),
                  ]),
                ),
              ),
          ],
        ]);
      },
    );
  }
}

String _ago(DateTime t, DateTime now) {
  final d = now.difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 48) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}

/// A draft, read-only.
class DeckDraftScreen extends StatelessWidget {
  const DeckDraftScreen({super.key, required this.id, required this.title});
  final String id;
  final String title;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final snap = services.store.detail('deckdraft', id, '/api/deck/drafts/${Uri.encodeComponent(id)}');
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(title: Text(title, overflow: TextOverflow.ellipsis)),
      body: SnapshotView(
        snapshot: snap,
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 56),
        builder: (context, data) => ReadingSurface(children: [ReadingBody(fmt.s(fmt.m(data)['content']))]),
      ),
    );
  }
}
