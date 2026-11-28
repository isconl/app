import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/ui/widgets/status_briefs_card.dart';

import 'support/test_services.dart';

class BriefApi extends ScriptedApi {
  BriefApi(super.answers, {this.sendError});
  final String? sendError;
  final List<Map<String, dynamic>> posts = [];

  @override
  Future<dynamic> postJson(String path, Map<String, dynamic> body, {bool cold = false}) async {
    posts.add({'path': path, ...body});
    if (sendError != null && path == '/api/status-briefs/send') return {'success': false, 'error': sendError};
    return {'success': true};
  }
}

final subjects = {
  'subjects': [
    {'SUBJECT_ID': 'SUBJ001', 'TYPE': 'engagement', 'SOURCE_REF': 'viva', 'STATUS': 'active'},
    {'SUBJECT_ID': 'SUBJ002', 'TYPE': 'engagement', 'SOURCE_REF': 'old-org', 'STATUS': 'retired'},
  ],
};

Map<String, dynamic> brief(String id, String status, String created) => {
      'ID': id,
      'SUBJECT_ID': 'SUBJ001',
      'WEEK_OF': '2026-10-05',
      'STATUS': status,
      'CREATED_AT': created,
      'SIGNAL': ['Contract signed.'],
      'SUBSTANCE': ['Three modules shipped.'],
      'TRAJECTORY': <String>[],
    };

void main() {
  test('the latest brief is the newest by date, then id; none gives null', () {
    expect(latestBrief([]), isNull);
    final b = latestBrief([brief('B1', 'sent', '2026-10-01'), brief('B3', 'draft', '2026-10-08'), brief('B2', 'sent', '2026-10-08')]);
    expect(b!['ID'], 'B3');
  });

  test('only a draft can be sent', () {
    expect(briefSendable(brief('B1', 'draft', 'x')), isTrue);
    expect(briefSendable(brief('B1', 'sent', 'x')), isFalse);
    expect(briefSendable(null), isFalse);
  });

  test('a recipient is one plain address', () {
    expect(looksLikeEmail('name@example.com'), isTrue);
    expect(looksLikeEmail(' name@example.com '), isTrue);
    for (final bad in ['', 'name', 'a@b', 'a@@b.c', 'a b@c.d', 'a@c.d, b@c.d', '<a@c.d>', 'a@.c', 'a@c.']) {
      expect(looksLikeEmail(bad), isFalse, reason: bad);
    }
  });

  Future<BriefApi> pump(WidgetTester tester, Map<String, Object> answers, {String? sendError}) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = BriefApi(answers, sendError: sendError);
    final services = (await tester.runAsync(() => buildTestServices(api)))!;
    await tester.pumpWidget(AppScope(services: services, child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: StatusBriefsCard())))));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 80));
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 40)));
    }
    return api;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 80));
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 40)));
    }
  }

  final answers = <String, Object>{
    '/api/active-subjects': subjects,
    '/api/status-briefs': {
      'briefs': [brief('B1', 'sent', '2026-10-01'), brief('B2', 'draft', '2026-10-08')],
    },
  };

  testWidgets('each active engagement shows its latest brief with the three lists; a retired one is left out', (tester) async {
    await pump(tester, answers);
    expect(find.text('viva'), findsOneWidget);
    expect(find.text('old-org'), findsNothing);
    expect(find.text('week of 2026-10-05 · draft'), findsOneWidget);
    expect(find.text('- Contract signed.'), findsOneWidget);
    expect(find.text('- Three modules shipped.'), findsOneWidget);
    expect(find.text('none'), findsOneWidget, reason: 'the empty Trajectory list');
    expect(find.byKey(const Key('brief-send-B2')), findsOneWidget);
  });

  testWidgets('drafting posts the subject id and sends nothing outward', (tester) async {
    final api = await pump(tester, answers);
    await tester.tap(find.byKey(const Key('brief-draft-SUBJ001')));
    await settle(tester);
    final d = api.posts.firstWhere((p) => p['path'] == '/api/status-briefs/draft');
    expect(d['subjectId'], 'SUBJ001');
    expect(api.posts.where((p) => p['path'] == '/api/status-briefs/send'), isEmpty);
  });

  testWidgets('sending asks for the address, shows the recipient, and posts only after the second tap', (tester) async {
    final api = await pump(tester, answers);
    await tester.tap(find.byKey(const Key('brief-send-B2')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('brief-to')), 'boss@example.com');
    await tester.tap(find.byKey(const Key('brief-to-go')));
    await tester.pumpAndSettle();
    expect(find.text('Send this brief to boss@example.com?'), findsOneWidget);
    expect(api.posts.where((p) => p['path'] == '/api/status-briefs/send'), isEmpty, reason: 'nothing leaves before the confirm');
    await tester.tap(find.text('Send').last);
    await settle(tester);
    final s = api.posts.firstWhere((p) => p['path'] == '/api/status-briefs/send');
    expect(s['briefId'], 'B2');
    expect(s['via'], 'email');
    expect(s['to'], 'boss@example.com');
  });

  testWidgets('cancelling at the confirm, or typing something that is not an address, sends nothing', (tester) async {
    final api = await pump(tester, answers);
    await tester.tap(find.byKey(const Key('brief-send-B2')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('brief-to')), 'not an address');
    await tester.tap(find.byKey(const Key('brief-to-go')));
    await settle(tester);
    expect(find.text('Type one email address.'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.tap(find.byKey(const Key('brief-send-B2')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('brief-to')), 'boss@example.com');
    await tester.tap(find.byKey(const Key('brief-to-go')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel').last);
    await settle(tester);
    expect(api.posts.where((p) => p['path'] == '/api/status-briefs/send'), isEmpty);
  });

  testWidgets('a refused send shows the server\'s reason', (tester) async {
    await pump(tester, answers, sendError: 'Mail is not configured.');
    await tester.tap(find.byKey(const Key('brief-send-B2')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('brief-to')), 'boss@example.com');
    await tester.tap(find.byKey(const Key('brief-to-go')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send').last);
    await settle(tester);
    expect(find.text('Mail is not configured.'), findsOneWidget);
  });

  testWidgets('a brief already sent offers no Send button', (tester) async {
    await pump(tester, {
      '/api/active-subjects': subjects,
      '/api/status-briefs': {
        'briefs': [brief('B1', 'sent', '2026-10-08')],
      },
    });
    expect(find.byKey(const Key('brief-send-B1')), findsNothing);
    expect(find.byKey(const Key('brief-draft-SUBJ001')), findsOneWidget);
  });
}
