import 'package:flutter/material.dart';


import '../../app_scope.dart';
import '../../data/db.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../nav_menu.dart' show parseNavGroups;
import '../widgets/common.dart';
import '../widgets/reader.dart';
import '../widgets/space_header.dart';
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

/// Tools: Jira (Kanban), Social (Buffer) and GitHub as three tabs under the shared search, each view unchanged
/// (BI26101816). The tool a tile asked for (ToolsPrefs) opens first.
class ToolsView extends StatelessWidget {
  const ToolsView({super.key, this.views = toolViews, this.prefs});
  final List<String> views;

  /// Replaced in tests.
  final ToolsPrefs? prefs;

  static const tabLabels = ['Jira', 'Social', 'GitHub'];

  /// What the three tabs hold, for the search: each tool and the things it contains.
  static const searchTable = <(String, String, int)>[
    ('Jira', 'Kanban: issues and transitions', 0),
    ('Kanban', 'Jira issues by status', 0),
    ('Social', 'Buffer: queued posts and the desk', 1),
    ('Buffer', 'scheduled posts', 1),
    ('GitHub', 'contributions and repositories', 2),
  ];

  static List<SpaceHit> hitsFor(BuildContext context) => [for (final (t, sub, tab) in searchTable) SpaceHit(title: t, subtitle: sub, tab: tab)];

  @override
  Widget build(BuildContext context) {
    final p = prefs ?? ToolsPrefs.instance;
    if (prefs == null) p.ensureLoaded(AppScope.of(context).db);
    return SpaceView(
      space: 'tools',
      searchHint: 'Search Jira, Social and GitHub',
      hits: hitsFor,
      initialTab: toolViews.indexOf(p.selected).clamp(0, 2),
      tabs: const [
        SpaceTab('Jira', JiraView()),
        SpaceTab('Social', SocialView()),
        SpaceTab('GitHub', _GithubScroll()),
      ],
    );
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

/// Deck on the phone, under the shared search: Boards, Drafts and Sent (the approved documents).
class DeckChannelView extends StatelessWidget {
  const DeckChannelView({super.key});

  static const tabLabels = ['Boards', 'Drafts', 'Sent'];

  static const _publishedPath = '/api/deck/published';

  /// The search finds a board, a draft or a sent document and opens the tab that holds it.
  static List<SpaceHit> hitsFor(BuildContext context) {
    final store = AppScope.of(context).store;
    final studio = DeckStudio.parse(store.deckStudio.value);
    return [
      for (final b in studio.boards) SpaceHit(title: b.title, subtitle: '${b.staged} staged', tab: 0),
      for (final d in studio.drafts) SpaceHit(title: d.title, subtitle: 'draft', tab: 1),
      for (final x in fmt.lm(fmt.m(store.detail('deckpublished', 'all', _publishedPath).value)['documents']))
        if (fmt.s(x['title']).isNotEmpty) SpaceHit(title: fmt.s(x['title']), subtitle: [fmt.s(x['space']), fmt.s(x['version'])].where((e) => e.isNotEmpty).join(' · '), tab: 2),
    ];
  }

  static const _empty = EmptyState('Deck is not connected yet', 'Boards and drafts appear here once the hub serves the studio.', icon: Icons.dashboard_customize_rounded);

  Widget _studioTab(BuildContext context, {required bool boards}) {
    final services = AppScope.of(context);
    return SnapshotView(
      snapshot: services.store.deckStudio,
      empty: _empty,
      builder: (context, data) {
        final studio = DeckStudio.parse(data);
        if (studio.isEmpty) {
          return const EmptyState('Nothing in the studio', 'Boards and drafts appear here as they are made.', icon: Icons.dashboard_customize_rounded);
        }
        final now = DateTime.now();
        if (boards) {
          if (studio.boards.isEmpty) return const EmptyState('No boards', 'Live-editable boards appear here.', icon: Icons.dashboard_customize_rounded);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final b in studio.boards)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Panel(
                  key: ValueKey('board-${b.id}'),
                  onTap: () => Navigator.push<void>(context, MaterialPageRoute(builder: (_) => DeckBoardScreen(id: b.id, title: b.title))),
                  child: Row(children: [
                    Expanded(child: Text(b.title, style: T.body2.copyWith(color: C.text))),
                    Text('${b.staged} staged', style: T.monoSmall),
                  ]),
                ),
              ),
          ]);
        }
        if (studio.drafts.isEmpty) return const EmptyState('No drafts', 'Documents that are not yet approved appear here.', icon: Icons.edit_note_rounded);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
        ]);
      },
    );
  }

  Widget _sentTab(BuildContext context) {
    final snap = AppScope.of(context).store.detail('deckpublished', 'all', _publishedPath);
    return SnapshotView(
      snapshot: snap,
      empty: const EmptyState('Nothing sent yet', 'Approved documents appear here.', icon: Icons.send_rounded),
      builder: (context, data) {
        final docs = fmt.lm(fmt.m(data)['documents']);
        if (docs.isEmpty) return const EmptyState('Nothing sent yet', 'Approved documents appear here.', icon: Icons.send_rounded);
        final now = DateTime.now();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final x in docs)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Panel(
                key: ValueKey('sent-${fmt.s(x['id'])}'),
                child: Row(children: [
                  Expanded(child: Text(fmt.s(x['title']), style: T.body2.copyWith(color: C.text))),
                  Text(
                    [fmt.s(x['version']), if (fmt.parseDate(x['updated']) != null) _ago(fmt.parseDate(x['updated'])!, now)].where((e) => e.isNotEmpty).join(' · '),
                    style: T.monoSmall,
                  ),
                ]),
              ),
            ),
        ]);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SpaceView(
      space: 'deck',
      searchHint: 'Search boards, drafts and sent documents',
      hits: hitsFor,
      tabs: [
        SpaceTab(tabLabels[0], _studioTab(context, boards: true)),
        SpaceTab(tabLabels[1], _studioTab(context, boards: false)),
        SpaceTab(tabLabels[2], _sentTab(context)),
      ],
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

/// One staged card on a board, as `GET /api/deck/board/<id>/items` serves it.
class DeckCard {
  const DeckCard({required this.id, required this.kind, required this.title, required this.body, required this.project, required this.field, required this.link, required this.ask});
  final String id, kind, title, body, project, field, link, ask;

  static List<DeckCard> parse(dynamic json) => [
        for (final x in fmt.lm(fmt.m(json)['items']))
          if (fmt.s(x['title']).isNotEmpty)
            DeckCard(id: fmt.s(x['id']), kind: fmt.s(x['kind']), title: fmt.s(x['title']), body: fmt.s(x['body']), project: fmt.s(x['project']), field: fmt.s(x['field']), link: fmt.s(x['link']), ask: fmt.s(x['ask'])),
      ];
}

/// The five fields of a weekly review, in Deck's order, as column headings.
const deckFields = [('signal', 'Signal'), ('substance', 'Substance'), ('trajectory', 'Trajectory'), ('risks', 'Risks'), ('asks', 'Asks')];

/// A board's staged cards grouped under the review's five headings, with a project filter. Read only on the phone:
/// editing, moving, removing and composing are the account owner's on deck.qprow.com (BI26101813 follow-up).
class DeckBoardScreen extends StatefulWidget {
  const DeckBoardScreen({super.key, required this.id, required this.title});
  final String id;
  final String title;

  @override
  State<DeckBoardScreen> createState() => _DeckBoardScreenState();
}

class _DeckBoardScreenState extends State<DeckBoardScreen> {
  String _project = '';

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final snap = services.store.detail('deckboard', widget.id, '/api/deck/board/${Uri.encodeComponent(widget.id)}/items');
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(title: Text(widget.title, overflow: TextOverflow.ellipsis)),
      body: SnapshotView(
        snapshot: snap,
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 56),
        empty: const EmptyState('Nothing staged', 'Cards staged on this board appear here.', icon: Icons.dashboard_customize_rounded),
        builder: (context, data) {
          final cards = DeckCard.parse(data);
          if (cards.isEmpty) return const EmptyState('Nothing staged', 'Cards staged on this board appear here.', icon: Icons.dashboard_customize_rounded);
          final projects = ({for (final c in cards) if (c.project.isNotEmpty) c.project}.toList()..sort());
          final shown = [for (final c in cards) if (_project.isEmpty || c.project == _project) c];
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (projects.length > 1)
              SingleChildScrollView(
                key: const Key('deck-project-filter'),
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(label: Text('All ${cards.length}'), selected: _project.isEmpty, onSelected: (_) => setState(() => _project = ''))),
                  for (final p in projects)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(key: Key('deck-filter-$p'), label: Text('$p ${cards.where((c) => c.project == p).length}'), selected: _project == p, onSelected: (_) => setState(() => _project = p)),
                    ),
                ]),
              ),
            for (final (key, heading) in deckFields)
              if (shown.any((c) => c.field == key)) ...[
                SectionLabel('$heading (${shown.where((c) => c.field == key).length})'),
                for (final c in shown.where((c) => c.field == key))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Panel(
                      key: ValueKey('card-${c.id}'),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(c.title, style: T.w600(T.body2)),
                        if (c.body.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(c.body, style: T.small.copyWith(color: C.text2))),
                        if (c.ask.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Ask: ${c.ask}', style: T.small.copyWith(color: C.amber))),
                        Padding(padding: const EdgeInsets.only(top: 6), child: Text([c.kind, c.project].where((e) => e.isNotEmpty).join(' · '), style: T.monoSmall)),
                      ]),
                    ),
                  ),
              ],
            if (shown.every((c) => !deckFields.any((f) => f.$1 == c.field)) && shown.isNotEmpty)
              for (final c in shown)
                Padding(padding: const EdgeInsets.only(bottom: 8), child: Panel(child: Text(c.title, style: T.body2))),
          ]);
        },
      ),
    );
  }
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
