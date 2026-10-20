import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/theme.dart';
import 'package:isconl/ui/views/inbox.dart';
import 'package:isconl/ui/views/inbox_threads.dart';

import 'support/test_services.dart';

Map<String, dynamic> msg(String id, String at, String body,
        {String dir = 'in', String channel = 'whatsapp', String person = 'P1', String status = 'seen', String sender = '', String title = ''}) =>
    {
      'ID': id,
      'RECEIVED_AT': at,
      'BODY': body,
      'DIRECTION': dir,
      'CHANNEL': channel,
      'PERSON_ID': person,
      'STATUS': status,
      'SENDER': sender,
      'TITLE': title,
    };

String iso(DateTime d, int h, int m) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}T${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

void main() {
  final today = DateTime.now();
  final yesterday = today.subtract(const Duration(days: 1));

  group('BI26092641: the rules', () {
    test('notices are not messages, a bare link is link-only', () {
      expect(messageKind(msg('1', iso(today, 9, 0), 'Messages and calls are end-to-end encrypted.')), MessageKind.system);
      expect(messageKind(msg('2', iso(today, 9, 0), '<Media omitted>')), MessageKind.system);
      expect(messageKind(msg('3', iso(today, 9, 0), 'https://example.com/x')), MessageKind.linkOnly);
      expect(messageKind(msg('4', iso(today, 9, 0), 'hello')), MessageKind.message);
      expect(messageKind(msg('5', iso(today, 9, 0), 'hello', channel: 'system')), MessageKind.system);
    });

    test('a link sent right after a message folds into it; one sent later stands alone', () {
      final rows = threadRows([
        msg('1', iso(yesterday, 14, 30), 'look at this'),
        msg('2', iso(yesterday, 14, 33), 'https://a.example/p'),
        msg('3', iso(yesterday, 16, 0), 'https://b.example/q'),
        msg('4', iso(yesterday, 16, 5), 'Messages and calls are end-to-end encrypted.'),
      ]);
      expect(rows.length, 2);
      expect(rows[0].extraLinks, ['https://a.example/p']);
      expect(rows[1].message['BODY'], 'https://b.example/q');
    });

    test('day labels: Today, Yesterday, then weekday day month', () {
      final now = DateTime(2026, 10, 1, 12);
      expect(dayLabel(DateTime(2026, 10, 1), now), 'Today');
      expect(dayLabel(DateTime(2026, 9, 30), now), 'Yesterday');
      expect(dayLabel(DateTime(2026, 9, 22), now), 'Tue 22 Sep');
      expect(dayLabel(DateTime(2025, 12, 24), now), 'Wed 24 Dec 2025');
    });

    test('two channels of one person merge into one thread in time order; unlinked senders only appear as unknown', () {
      final g = groupThreads([
        msg('1', iso(today, 9, 0), 'on whatsapp', channel: 'whatsapp'),
        msg('2', iso(today, 9, 5), 'by email', channel: 'gmail'),
        msg('3', iso(today, 9, 10), 'who is this', person: '', sender: 'stranger@x.com', channel: 'gmail'),
        msg('4', iso(yesterday, 8, 0), 'older person', person: 'P2'),
      ]);
      expect(g.people.map((t) => t.key), ['P1', 'P2']);
      expect(g.people.first.messages.length, 2);
      expect(g.unknown.map((t) => t.key), ['sender:stranger@x.com']);
      final rows = threadRows(g.people.first.messages);
      expect(rows.map((r) => r.message['ID']), ['1', '2']);
    });

    test('a conversation of only notices makes no thread', () {
      final g = groupThreads([msg('1', iso(today, 9, 0), 'Messages and calls are end-to-end encrypted.')]);
      expect(g.people, isEmpty);
    });
  });

  group('BI26092641: the screens', () {
    Future<void> pumpThread(WidgetTester tester, List<Map<String, dynamic>> messages, {String title = 'Ada'}) async {
      final services = (await tester.runAsync(() => buildTestServices(ScriptedApi({}))))!;
      await tester.pumpWidget(AppScope(services: services, child: MaterialApp(home: InboxThreadView(title: title, messages: messages))));
      await tester.pump();
    }

    testWidgets('own messages sit right in green, theirs left; every bubble has a time and a source', (tester) async {
      await pumpThread(tester, [
        msg('1', iso(today, 9, 5), 'hi there'),
        msg('2', iso(today, 9, 6), 'hello back', dir: 'out'),
      ]);
      final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
      expect(tester.getTopRight(find.byKey(const Key('bubble-out'))).dx, greaterThan(width * 0.6));
      expect(tester.getTopLeft(find.byKey(const Key('bubble-in'))).dx, lessThan(40));
      final outDeco = tester.widget<Container>(find.byKey(const Key('bubble-out'))).decoration as BoxDecoration;
      expect(outDeco.color, C.greenDim);
      expect(find.byKey(const Key('bubble-time')), findsNWidgets(2));
      expect(find.byKey(const Key('bubble-source')), findsNWidgets(2));
      expect(find.text('09:05'), findsOneWidget);
      expect(find.text('WhatsApp'), findsNWidgets(2));
    });

    testWidgets('email bubbles show the subject in bold; link-only rows become a card, notices disappear', (tester) async {
      await pumpThread(tester, [
        msg('1', iso(today, 9, 0), 'Please see the attached plan.', channel: 'gmail', title: 'Q4 plan'),
        msg('2', iso(today, 9, 2), 'https://plan.example/doc', channel: 'gmail'),
        msg('3', iso(today, 9, 3), 'Messages and calls are end-to-end encrypted.'),
      ]);
      expect(find.byKey(const Key('bubble-subject')), findsOneWidget);
      expect(find.text('Q4 plan'), findsOneWidget);
      expect(find.byKey(const Key('link-card')), findsOneWidget);
      expect(find.textContaining('end-to-end'), findsNothing);
      expect(find.byKey(const Key('bubble-in')), findsOneWidget);
    });

    testWidgets('day separators mark each day and the thread opens on the newest message', (tester) async {
      final many = <Map<String, dynamic>>[
        for (var i = 0; i < 60; i++) msg('o$i', iso(yesterday, 8, i % 60), 'old message $i'),
        msg('new', iso(today, 10, 0), 'the newest message'),
      ];
      await pumpThread(tester, many);
      expect(find.text('the newest message'), findsOneWidget);
      expect(find.text('old message 0'), findsNothing);
      expect(find.text('Today'), findsOneWidget);
    });

    testWidgets('the people list shows a source icon and the time, and Unknown holds only unlinked senders', (tester) async {
      final services = (await tester.runAsync(() => buildTestServices(ScriptedApi({}))))!;
      services.store.circle.value = {
        'people': [
          {'ID': 'P1', 'NAME': 'Ada Lovelace'}
        ]
      };
      services.store.state.value = {
        'feed': [
          msg('1', iso(today, 9, 5), 'hi there'),
          msg('3', iso(today, 9, 10), 'who is this', person: '', sender: 'stranger@x.com', channel: 'gmail'),
        ],
      };
      services.store.inboxUnknown.value = {
        'unknown': [
          {'kind': 'email', 'value': 'stranger@x.com', 'sender': 'stranger@x.com', 'channel': 'gmail', 'count': 1}
        ]
      };
      await tester.pumpWidget(AppScope(
        services: services,
        child: const MaterialApp(home: Scaffold(body: InboxView())),
      ));
      await tester.pump();
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 80)));
      await tester.pump();
      // BI26101816: both threads are read, so they sit on All, not Unread.
      await tester.tap(find.byKey(const Key('inbox-tab-all')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Ada Lovelace'), findsOneWidget);
      expect(find.text('UNKNOWN'), findsOneWidget);
      expect(find.byKey(const Key('tile-source')), findsNWidgets(2));
      expect(find.byKey(const Key('tile-time')), findsNWidgets(2));
      expect(find.byKey(const Key('unknown-link')), findsOneWidget);
      expect(find.byKey(const Key('unknown-create')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
      await tester.pump(const Duration(seconds: 2));
    });
  });
}
