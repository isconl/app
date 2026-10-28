import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/api/client.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/ui/views/channel_subs.dart';

import 'support/test_services.dart';

class _Api extends ApiClient {
  _Api() : super(baseUrl: 'http://test', token: 'test');
  @override
  Future<dynamic> getJson(String path, {bool cold = false, bool stored = true}) async => <String, dynamic>{};
}

List<Map<String, dynamic>> nav(List<(String, String)> flow) => [
      {'key': 'command', 'label': 'COMMAND', 'children': [{'view': 'today', 'label': 'Hub'}]},
      {'key': 'flow', 'label': 'CHANNELS', 'children': [for (final (v, l) in flow) {'view': v, 'label': l}]},
    ];

void main() {
  group('BI26092637: the Channels plan comes from /api/nav', () {
    test('order and labels follow the nav; Kanban, Buffer and GitHub fold into one Tools tab', () {
      final plan = channelPlan(nav([('inbox', 'Inbox'), ('canvas', 'Canvas'), ('teams', 'Teams'), ('jira', 'Kanban'), ('social', 'Buffer'), ('github', 'GitHub')]));
      expect(plan.map((p) => p.kind), [ChannelKind.inbox, ChannelKind.deck, ChannelKind.teams, ChannelKind.tools]);
      expect(plan.map((p) => p.label), ['Inbox', 'Canvas', 'Teams', 'Tools']);
    });

    test('Tools sits where the first tool is, and a reordered nav reorders the tabs', () {
      final plan = channelPlan(nav([('teams', 'Teams'), ('jira', 'Kanban'), ('inbox', 'Inbox'), ('social', 'Buffer')]));
      expect(plan.map((p) => p.kind), [ChannelKind.teams, ChannelKind.tools, ChannelKind.inbox]);
    });

    test('Press and unknown views are not mobile sub-tabs', () {
      final plan = channelPlan(nav([('inbox', 'Inbox'), ('press', 'Press'), ('mystery', 'X'), ('teams', 'Teams')]));
      expect(plan.map((p) => p.kind), [ChannelKind.inbox, ChannelKind.teams]);
    });

    test('no nav yet falls back to Inbox, Deck, Teams, Tools', () {
      for (final v in [null, <dynamic>[], {'groups': []}]) {
        expect(channelPlan(v).map((p) => p.label), ['Inbox', 'Deck', 'Teams', 'Tools']);
      }
    });

    test("hub's CHANNELS (Inbox, Cover, Deck, Teams, Tools) gives the phone Inbox, Deck, Teams, Tools: the tools item is the Tools tab and Cover is the chat sheet's, not a tab", () {
      final plan = channelPlan(nav([('inbox', 'Inbox'), ('cover', 'Cover'), ('deck', 'Deck'), ('teams', 'Teams'), ('tools', 'Tools')]));
      expect(plan.map((p) => p.kind), [ChannelKind.inbox, ChannelKind.deck, ChannelKind.teams, ChannelKind.tools]);
      expect(plan.map((p) => p.label), ['Inbox', 'Deck', 'Teams', 'Tools']);
      expect(toolViewsIn(nav([('inbox', 'Inbox'), ('tools', 'Tools')])), ['jira', 'social', 'github'], reason: 'with no individual tool items, all three are on offer');
    });

    test('the tools on offer follow the nav too', () {
      expect(toolViewsIn(nav([('inbox', 'Inbox'), ('social', 'Buffer'), ('jira', 'Kanban')])), ['social', 'jira']);
      expect(toolViewsIn(null), ['jira', 'social', 'github']);
    });
  });

  testWidgets('Tools is the shared search over Jira, Social and GitHub, and opens on the tool a tile asked for', (t) async {
    t.view.physicalSize = const Size(1100, 1600);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final services = (await t.runAsync(() => buildTestServices(_Api(), online: false)))!;
    services.store.jira.value = {'issues': <dynamic>[]};
    services.store.buffer.value = {'channels': <dynamic>[], 'queue': <dynamic>[], 'sent': <dynamic>[]};
    services.store.github.value = {'repos': <dynamic>[]};
    final prefs = ToolsPrefs.forTesting();
    await prefs.select('social');
    await t.pumpWidget(AppScope(services: services, child: MaterialApp(home: Scaffold(body: ToolsView(prefs: prefs)))));
    await t.pump();
    expect(find.text('Search Jira, Social and GitHub'), findsOneWidget);
    for (final l in ToolsView.tabLabels) {
      expect(find.text(l), findsWidgets, reason: l);
    }
    await t.tap(find.byKey(const Key('tools-tab-github')));
    await t.pump(const Duration(milliseconds: 400));
    await prefs.select('nonsense');
    expect(prefs.selected, 'social', reason: 'an unknown tool is ignored');
    final stored = ToolsPrefs.forTesting();
    await t.runAsync(() => prefs.select('github', db: services.db));
    await t.runAsync(() => stored.ensureLoaded(services.db));
    expect(stored.selected, 'github');
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 11));
  });

  test('a studio payload parses into boards and drafts', () {
    final s = DeckStudio.parse({
      'boards': [{'id': 'b1', 'title': 'Work review: Joel', 'staged': 4}, {'id': 'x', 'title': ''}],
      'drafts': [{'id': 'd1', 'title': 'Pricing note', 'updatedAt': '2026-10-03T08:00:00Z'}],
    });
    expect(s.boards.single.staged, 4);
    expect(s.drafts.single.title, 'Pricing note');
    expect(s.drafts.single.updatedAt, isNotNull);
    expect(DeckStudio.parse(null).isEmpty, true);
  });

  testWidgets('the Deck view renders a board and a draft from fixtures', (t) async {
    t.view.physicalSize = const Size(600, 1200);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final services = (await t.runAsync(() => buildTestServices(_Api(), online: false)))!;
    services.store.deckStudio.value = {
      'boards': [{'id': 'b1', 'title': 'Work review: Joel', 'staged': 4}],
      'drafts': [{'id': 'd1', 'title': 'Pricing note', 'updatedAt': DateTime.now().subtract(const Duration(hours: 2)).toIso8601String()}],
    };
    await t.pumpWidget(AppScope(services: services, child: const MaterialApp(home: Scaffold(body: DeckChannelView()))));
    await t.pump();
    expect(find.text('Work review: Joel'), findsOneWidget);
    expect(find.text('4 staged'), findsOneWidget);
    expect(find.text('Search boards, drafts and sent documents'), findsOneWidget);
    await t.tap(find.byKey(const Key('deck-tab-drafts')));
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    expect(find.text('Pricing note'), findsOneWidget);
    expect(find.text('updated 2h ago'), findsOneWidget);
    await t.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 11));
  });

  testWidgets('BI26101813: a board opens to its cards under the five review headings, with a project filter', (t) async {
    t.view.physicalSize = const Size(600, 1600);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final services = (await t.runAsync(() => buildTestServices(_Api(), online: false)))!;
    services.store.detail('deckboard', 'b1', '/api/deck/board/b1/items').value = {
      'items': [
        {'id': 'i1', 'kind': 'work', 'title': 'Shipped the board', 'body': '', 'project': 'deck', 'field': 'signal', 'link': '', 'ask': ''},
        {'id': 'i2', 'kind': 'ask', 'title': 'Need a decision', 'body': '', 'project': 'vela', 'field': 'asks', 'link': '', 'ask': 'Pick one'},
      ],
    };
    await t.pumpWidget(AppScope(services: services, child: const MaterialApp(home: DeckBoardScreen(id: 'b1', title: 'Work review: Joel'))));
    await t.pump();
    expect(find.text('SIGNAL (1)'), findsOneWidget);
    expect(find.text('ASKS (1)'), findsOneWidget);
    expect(find.text('Ask: Pick one'), findsOneWidget);
    await t.tap(find.byKey(const Key('deck-filter-deck')));
    await t.pump();
    expect(find.byKey(const ValueKey('card-i1')), findsOneWidget);
    expect(find.byKey(const ValueKey('card-i2')), findsNothing);
    await t.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
    await t.pump(const Duration(seconds: 1));
  });
}
