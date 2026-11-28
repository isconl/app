// BI26101816: Rhythm, Settings and the four Channels spaces (Inbox, Deck, Teams, Tools) wear the shared space header: the
// search entry above exactly three tabs, and the search names the tab that holds a known item.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/theme.dart';
import 'package:isconl/ui/views/channel_subs.dart';
import 'package:isconl/ui/views/inbox.dart';
import 'package:isconl/ui/views/rhythm.dart';
import 'package:isconl/ui/views/settings.dart';
import 'package:isconl/ui/views/teams.dart';
import 'package:isconl/ui/widgets/space_header.dart';

import 'support/test_services.dart';

void main() {
  final today = DateTime.now();
  String iso(int h, int m) =>
      '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}T${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

  Future<AppServices> pump(WidgetTester t, Widget view) async {
    t.view.physicalSize = const Size(900, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final services = (await t.runAsync(() => buildTestServices(ScriptedApi({}))))!;
    services.store.rhythm.value = {
      'habits': [
        {'id': 'h1', 'title': 'Walk after lunch', 'focusWord': 'Recovery', 'minimumVersion': '10 minutes', 'anchor': ''},
      ],
      'logs': {
        for (var i = 0; i < 3; i++)
          '${today.subtract(Duration(days: i)).year}-${today.subtract(Duration(days: i)).month.toString().padLeft(2, '0')}-${today.subtract(Duration(days: i)).day.toString().padLeft(2, '0')}': {'h1': true},
      },
      'days': <dynamic>[],
    };
    services.store.circle.value = {'people': [{'ID': 'P1', 'NAME': 'Ada Lovelace'}]};
    services.store.state.value = {
      'feed': [
        {'ID': '1', 'RECEIVED_AT': iso(9, 5), 'BODY': 'hello there', 'DIRECTION': 'in', 'CHANNEL': 'whatsapp', 'PERSON_ID': 'P1', 'STATUS': 'new', 'SENDER': '', 'TITLE': ''},
      ],
    };
    services.store.deckStudio.value = {
      'boards': [{'id': 'b1', 'title': 'Work review: Joel', 'staged': 2}],
      'drafts': [{'id': 'd1', 'title': 'Pricing note', 'updatedAt': today.toIso8601String()}],
    };
    await t.pumpWidget(AppScope(services: services, child: MaterialApp(theme: buildTheme(), home: Scaffold(body: view))));
    await t.pump();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump(const Duration(seconds: 1));
    return services;
  }

  Future<void> end(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 11));
  }

  testWidgets('Rhythm: the entry above Today, Habits and Year, and a habit shows its streak on Habits', (t) async {
    await pump(t, const RhythmView());
    expect(find.text('Search habits'), findsOneWidget);
    for (final l in RhythmView.tabLabels) {
      expect(find.text(l), findsWidgets, reason: l);
    }
    await t.tap(find.byKey(const Key('rhythm-tab-habits')));
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    expect(t.widget<Text>(find.byKey(const Key('streak-h1'))).data, 'streak 3d');
    await end(t);
  });

  test('a habit streak counts back from today, or from yesterday when today is not ticked yet', () {
    final d = DateTime(2026, 10, 20);
    final logs = <String, dynamic>{
      '2026-10-20': {'h': true},
      '2026-10-19': {'h': true},
      '2026-10-17': {'h': true},
    };
    expect(RhythmView.habitStreak(logs, 'h', d), 2);
    expect(RhythmView.habitStreak({'2026-10-19': {'h': true}, '2026-10-18': {'h': true}}, 'h', d), 2);
    expect(RhythmView.habitStreak({}, 'h', d), 0);
  });

  testWidgets('Settings: the entry above General, Study and notes and Account and sync', (t) async {
    await pump(t, const SettingsView());
    expect(find.text('Search settings'), findsOneWidget);
    for (final l in settingsTabLabels) {
      expect(find.text(l), findsWidgets, reason: l);
    }
    expect(find.text('DAY CLOSE'), findsOneWidget);
    await end(t);
  });

  testWidgets('Inbox: the entry above Unread, Waiting and All, with the unread thread on the first', (t) async {
    await pump(t, const InboxView());
    expect(find.text('Search messages and people'), findsOneWidget);
    for (final l in inboxTabLabels) {
      expect(find.text(l), findsWidgets, reason: l);
    }
    expect(find.text('Ada Lovelace'), findsOneWidget);
    await end(t);
  });

  testWidgets('Deck: the entry above Boards, Drafts and Sent', (t) async {
    await pump(t, const DeckChannelView());
    expect(find.text('Search boards, drafts and sent documents'), findsOneWidget);
    for (final l in DeckChannelView.tabLabels) {
      expect(find.text(l), findsWidgets, reason: l);
    }
    await end(t);
  });

  testWidgets('searches name the tab that holds a known item', (t) async {
    final s = await pump(t, const SizedBox());
    late List<SpaceHit> rhythm, settings, inbox, deck, tools, teams;
    await t.pumpWidget(AppScope(services: s, child: Builder(builder: (c) {
      rhythm = RhythmView.hitsFor(c);
      settings = settingsHits(c);
      inbox = inboxHits(c);
      deck = DeckChannelView.hitsFor(c);
      tools = ToolsView.hitsFor(c);
      teams = teamsHits([
        {
          'title': 'Studio',
          'members': [{'name': 'Ann'}],
          'work': [{'title': 'Queued item'}],
        }
      ]);
      return const SizedBox();
    })));
    expect(rhythm.firstWhere((h) => h.title == 'Walk after lunch').tab, 1);
    expect(settings.firstWhere((h) => h.title == 'Day close').tab, 0);
    expect(settings.firstWhere((h) => h.title == 'News watch').tab, 1);
    expect(settings.firstWhere((h) => h.title == 'Passkeys').tab, 2);
    expect(inbox.firstWhere((h) => h.title == 'Ada Lovelace').tab, 0, reason: 'it has an unread message');
    expect(deck.firstWhere((h) => h.title == 'Work review: Joel').tab, 0);
    expect(deck.firstWhere((h) => h.title == 'Pricing note').tab, 1);
    expect(tools.firstWhere((h) => h.title == 'GitHub').tab, 2);
    expect(teams.firstWhere((h) => h.title == 'Ann').tab, 1);
    expect(teams.firstWhere((h) => h.title == 'Queued item').tab, 2);
    expect(filterHits(settings, 'sign-in keys').single.title, 'Passkeys');
    await end(t);
  });
}
