import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/services/close_feed.dart';
import 'package:isconl/ui/widgets/slate_closes_card.dart';

import 'support/test_services.dart';

CloseEvent ev(String id, {String project = 'iSconl', String title = 'A title', String note = '', bool sensitive = false, bool landed = false}) =>
    CloseEvent(id: id, project: project, title: title, note: note, sensitive: sensitive, landed: landed);

// Nairobi is UTC+3.
DateTime nairobi(int h, int m) => DateTime.utc(2026, 10, 15, h - 3, m);

void main() {
  group('BI26101529: reading the feed', () {
    test('events, the cursor and the first line of a close note', () {
      final r = parseCloses({
        'cursor': 'c42',
        'events': [
          {'id': 'BI1', 'project': 'iSconl', 'title': 'T', 'note': 'First line\nsecond'},
          {'id': 'BI2', 'project': 'slate', 'title': 'U', 'landed': true},
          {'title': 'no id is dropped'},
        ],
      });
      expect(r.cursor, 'c42');
      expect(r.events.map((e) => e.id), ['BI1', 'BI2']);
      expect(r.events.first.note, 'First line');
      expect(r.events.last.landed, isTrue);
    });
  });

  group('BI26101529: what to notify', () {
    final prefs = ClosePrefs();

    test('one close: title is Closed: <ID>, body is the row title and the first line of its note', () {
      final n = planCloseNotices([ev('BI26101520', title: 'Cycle focus', note: 'Released v0.3.125')], prefs, quiet: false).single;
      expect(n.title, 'Closed: BI26101520');
      expect(n.body, 'Cycle focus\nReleased v0.3.125');
      expect(n.payload, 'slate-row:BI26101520');
      expect(n.grouped, isFalse);
    });

    test('a landed row says landed and not yet verified live, never done', () {
      final n = planCloseNotices([ev('BS1', landed: true)], prefs, quiet: false).single;
      expect(n.title, 'Landed: BS1');
      expect(n.body, contains('Landed (not yet verified live)'));
      expect(n.title, isNot(contains('Closed')));
    });

    test('two closes are two notifications, three or more are one that expands to the list', () {
      expect(planCloseNotices([ev('A'), ev('B')], prefs, quiet: false), hasLength(2));
      final g = planCloseNotices([ev('A'), ev('B'), ev('C'), ev('D'), ev('E')], prefs, quiet: false).single;
      expect(g.title, '5 rows closed');
      expect(g.grouped, isTrue);
      expect(g.lines, hasLength(5));
    });

    test('a switched-off feed and a muted project give nothing', () {
      expect(planCloseNotices([ev('A')], ClosePrefs(enabled: false), quiet: false), isEmpty);
      expect(planCloseNotices([ev('A', project: 'viva')], ClosePrefs(muted: {'viva'}), quiet: false), isEmpty);
      final mixed = planCloseNotices([ev('A', project: 'viva'), ev('B', project: 'iSconl')], ClosePrefs(muted: {'viva'}), quiet: false);
      expect(mixed.single.title, 'Closed: B');
    });

    test('quiet hours suppress, unless quiet hours are off', () {
      expect(planCloseNotices([ev('A')], ClosePrefs(), quiet: true), isEmpty);
      expect(planCloseNotices([ev('A')], ClosePrefs(quietHours: false), quiet: true), hasLength(1));
    });

    test('a sensitive row shows only the project and is private on the lock screen', () {
      final n = planCloseNotices([ev('BX9', project: 'viva', title: 'Secret thing', sensitive: true)], prefs, quiet: false).single;
      expect(n.body, 'a sensitive row in viva');
      expect(n.title, isNot(contains('BX9')));
      expect(n.body, isNot(contains('Secret')));
      expect(n.payload, isNot(contains('BX9')));
      expect(n.private, isTrue);
      final g = planCloseNotices([ev('A'), ev('B'), ev('C', sensitive: true, title: 'Hidden')], prefs, quiet: false).single;
      expect(g.private, isTrue);
      expect(g.lines.join(' '), isNot(contains('Hidden')));
    });

    test('quiet hours are the Protected and Rest blocks, in Nairobi time', () {
      expect(inQuietBlock(nairobi(5, 30)), isTrue); // Protected
      expect(inQuietBlock(nairobi(23, 0)), isTrue); // Rest
      expect(inQuietBlock(nairobi(2, 0)), isTrue); // Rest, past midnight
      expect(inQuietBlock(nairobi(12, 0)), isFalse);
      expect(inQuietBlock(nairobi(18, 30)), isFalse); // Hearth
    });
  });

  group('BI26101529: the poll', () {
    test('the first poll sets the cursor and shows nothing; later closes notify once, never twice, and survive a restart', () async {
      final api = ScriptedApi({
        '/api/slate/closes': {
          'cursor': 'c1',
          'events': [
            {'id': 'OLD1', 'project': 'iSconl', 'title': 'Old'},
          ],
        },
      });
      final services = (await buildTestServices(api));
      final shown = <CloseNotice>[];
      CloseFeed make() => CloseFeed(
            api: () => api,
            db: services.db,
            notify: (n) async => shown.addAll(n),
            now: () => nairobi(12, 0),
          );
      var feed = make();
      expect(await feed.pollOnce(), 0);
      expect(feed.cursor, 'c1');
      expect(shown, isEmpty);
      expect(api.asked.last, startsWith('/api/slate/closes?wait=0'));

      api.answers['/api/slate/closes'] = {
        'cursor': 'c2',
        'events': [
          {'id': 'NEW1', 'project': 'iSconl', 'title': 'New one', 'note': 'done'},
        ],
      };
      expect(await feed.pollOnce(), 1);
      expect(api.asked.last, contains('since=c1'));
      expect(shown.single.title, 'Closed: NEW1');

      // The same event again, as after a retry: not notified twice.
      expect(await feed.pollOnce(), 0);
      expect(shown, hasLength(1));

      // A restart: a new feed on the same database carries on from the cursor and the seen ids.
      feed = make();
      expect(await feed.pollOnce(), 0);
      expect(feed.cursor, 'c2');
      expect(shown, hasLength(1));
    });

    test('quiet hours suppress the notification but the cursor still moves, so nothing is replayed later', () async {
      final api = ScriptedApi({
        '/api/slate/closes': {'cursor': 'c1', 'events': <dynamic>[]},
      });
      final services = (await buildTestServices(api));
      final shown = <CloseNotice>[];
      final feed = CloseFeed(api: () => api, db: services.db, notify: (n) async => shown.addAll(n), now: () => nairobi(23, 0));
      await feed.pollOnce();
      api.answers['/api/slate/closes'] = {
        'cursor': 'c2',
        'events': [
          {'id': 'Q1', 'project': 'iSconl', 'title': 'At night'},
        ],
      };
      expect(await feed.pollOnce(), 0);
      expect(shown, isEmpty);
      expect(feed.cursor, 'c2');
    });

    test('a project a close came from is remembered, so Settings can offer to mute it', () async {
      final api = ScriptedApi({
        '/api/slate/closes': {'cursor': 'c1', 'events': <dynamic>[]},
      });
      final services = (await buildTestServices(api));
      final feed = CloseFeed(api: () => api, db: services.db, notify: (_) async {}, now: () => nairobi(12, 0));
      await feed.pollOnce();
      api.answers['/api/slate/closes'] = {
        'cursor': 'c2',
        'events': [
          {'id': 'P1', 'project': 'viva', 'title': 'x'},
        ],
      };
      await feed.pollOnce();
      expect(feed.prefs.seenProjects, contains('viva'));
    });
  });

  group('BI26101529: Settings', () {
    testWidgets('the switch is on by default and a project can be muted', (tester) async {
      final api = ScriptedApi({});
      final services = (await tester.runAsync(() => buildTestServices(api)))!;
      final feed = CloseFeed(api: () => api, db: services.db, notify: (_) async {});
      feed.prefs.seenProjects.add('viva');
      await tester.pumpWidget(AppScope(services: services, child: MaterialApp(home: Scaffold(body: SlateClosesCard(feed: feed)))));
      await tester.pump();
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('slate-closes-enabled'))).value, isTrue);
      await tester.tap(find.byKey(const Key('slate-closes-mute-viva')));
      await tester.pump();
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 150)));
      await tester.pump(const Duration(seconds: 1));
      expect(feed.prefs.muted, contains('viva'));
      feed.stop();
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 150)));
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
