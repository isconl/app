import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/theme.dart';
import 'package:isconl/ui/views/chat.dart';
import 'package:isconl/ui/views/cover_pane.dart';

import 'support/test_services.dart';

/// BI26092642: the Cover tab in the chat sheet, against fixtures in the shape hub's /api/cover/* returns.
class _Api extends ScriptedApi {
  _Api(super.answers, this.log);
  final List<String> log;

  @override
  Future<dynamic> postJson(String path, Map<String, dynamic> body, {bool cold = false}) async {
    log.add('$path $body');
    return {'ok': true, 'connected': true, 'message': {'id': 'm9', 'text': body['text'], 'at': '2026-10-09T10:00:00Z', 'own': true}};
  }
}

final threads = [
  {'id': 't2', 'name': 'Brian', 'personId': '', 'last': {'text': 'Done', 'at': '2026-10-09T08:00:00Z', 'own': true}, 'unread': 0},
  {'id': 't1', 'name': 'Amina', 'personId': 'P1', 'last': {'text': 'See you at 3', 'at': '2026-10-08T09:00:00Z', 'own': false}, 'unread': 2},
];
final messages = [
  {'id': 'm1', 'text': 'See you at 3', 'at': '2026-10-08T09:00:00Z', 'own': false},
  {'id': 'm2', 'text': 'Great, bringing it', 'at': '2026-10-08T09:05:00Z', 'own': true},
  {'id': 'm3', 'text': 'Next day', 'at': '2026-10-09T07:00:00Z', 'own': false},
];
Map<String, Object> connected() => {
      '/api/cover/status': {'connected': true, 'calls': false, 'reason': ''},
      '/api/cover/threads': {'ok': true, 'connected': true, 'threads': threads},
      '/api/cover/messages': {'ok': true, 'connected': true, 'messages': messages},
    };

void main() {
  test('time and day helpers', () {
    expect(coverTime('2026-10-08T09:05:00Z'), '09:05');
    expect(coverTime(''), '');
    expect(coverDay('2026-10-08T09:05:00Z'), '2026-10-08');
  });

  Future<List<String>> pump(WidgetTester tester, Map<String, Object> answers, {Widget? child}) async {
    final log = <String>[];
    final services = (await tester.runAsync(() => buildTestServices(_Api(answers, log))))!;
    tester.view.physicalSize = const Size(700, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppScope(
      services: services,
      child: MaterialApp(theme: buildTheme(), home: Scaffold(body: child ?? const CoverPane())),
    ));
    await tester.pump();
    await tester.pump();
    return log;
  }

  testWidgets('Cover not connected: says so plainly, with a retry, and nothing is thrown', (tester) async {
    await pump(tester, {'/api/cover/status': {'connected': false, 'calls': false, 'reason': 'Cover is not set up on this console yet (no COVER_URL).'}});
    expect(find.byKey(const Key('cover-off')), findsOneWidget);
    expect(find.textContaining('not set up on this console yet'), findsOneWidget);
    expect(find.textContaining('The agent chat is not affected'), findsOneWidget);
    expect(find.byKey(const Key('cover-retry')), findsOneWidget);
  });

  testWidgets('connected: the list shows people, the last message and the unread count', (tester) async {
    await pump(tester, connected());
    expect(find.text('Brian'), findsOneWidget);
    expect(find.text('Amina'), findsOneWidget);
    expect(find.text('You: Done'), findsOneWidget);
    expect(find.text('2'), findsOneWidget, reason: 'Amina has two unread');
    expect(find.text('08:00'), findsOneWidget);
  });

  testWidgets('a thread: own on the right, others on the left, a time on each bubble, calls disabled; sending posts the text', (tester) async {
    final log = await pump(tester, connected());
    await tester.tap(find.byKey(const Key('cover-thread-t1')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('cover-msg-m2-out')), findsOneWidget);
    expect(find.byKey(const Key('cover-msg-m1-in')), findsOneWidget);
    final right = tester.getTopRight(find.byKey(const Key('cover-msg-m2-out'))).dx;
    final left = tester.getTopLeft(find.byKey(const Key('cover-msg-m1-in'))).dx;
    expect(right, greaterThan(tester.getTopRight(find.byKey(const Key('cover-msg-m1-in'))).dx), reason: 'own messages sit further right');
    expect(left, lessThan(tester.getTopLeft(find.byKey(const Key('cover-msg-m2-out'))).dx));
    expect(find.text('09:05'), findsOneWidget);
    expect(find.text('2026-10-08'), findsOneWidget);
    expect(find.text('2026-10-09'), findsOneWidget);
    expect(tester.widget<IconButton>(find.byKey(const Key('cover-voice'))).onPressed, isNull, reason: 'calls coming');
    expect(tester.widget<IconButton>(find.byKey(const Key('cover-video'))).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('cover-input')), '  hello  ');
    await tester.tap(find.byKey(const Key('cover-send')));
    await tester.pump();
    await tester.pump();
    expect(log, ['/api/cover/send {thread: t1, text: hello}']);
  });

  testWidgets('the chat sheet has Agent and Cover tabs: Agent is the default and Cover opens the pane without breaking the agent', (tester) async {
    await pump(tester, connected(), child: const ChatSheet(embedded: true));
    expect(find.byKey(const Key('chat-tab-agent')), findsOneWidget);
    expect(find.byKey(const Key('chat-tab-cover')), findsOneWidget);
    expect(find.text('iSconl Assistant'), findsOneWidget);
    expect(find.byType(CoverPane), findsNothing, reason: 'Agent first');
    await tester.tap(find.byKey(const Key('chat-tab-cover')));
    await tester.pump();
    await tester.pump();
    expect(find.byType(CoverPane), findsOneWidget);
    expect(find.text('Amina'), findsOneWidget);
    await tester.tap(find.byKey(const Key('chat-tab-agent')));
    await tester.pump();
    expect(find.byType(CoverPane), findsNothing);
    // Let the sheet's own database reads (history, the remembered tab) finish before the tree goes away.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
  });
}
