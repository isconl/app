import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/api/client.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/ui/widgets/common.dart';
import 'package:isconl/ui/widgets/refresher_cards.dart';

import 'support/test_services.dart';

/// A scripted API that also records the posts, and can be told to refuse them.
class PostApi extends ScriptedApi {
  PostApi(super.answers);
  final List<Map<String, dynamic>> posts = [];
  bool fail = false;

  @override
  Future<dynamic> postJson(String path, Map<String, dynamic> body, {bool cold = false}) async {
    if (fail) throw ApiException(500, 'refused');
    posts.add({'path': path, ...body});
    return {'ok': true};
  }
}

Map<String, dynamic> card(String id, String title) => {
      'id': id,
      'moduleId': 'm-$id',
      'course': 'Course',
      'title': title,
      'fromVersion': '1.0.0',
      'toVersion': '1.1.0',
      'summary': ['First thing that changed.', 'Second thing that changed.'],
      'questions': [
        {'question': 'Question one?', 'answer': 'Answer one.'},
        {'question': 'Question two?', 'answer': 'Answer two.'},
        {'question': 'Question three?', 'answer': 'Answer three.'},
      ],
    };

Map<String, dynamic> body(List<Map<String, dynamic>> cards) => {'cards': cards, 'total': cards.length};

void main() {
  Future<PostApi> pump(WidgetTester tester, Map<String, dynamic> answer, {bool failPosts = false}) async {
    final api = PostApi({'/api/study/refreshers': answer})..fail = failPosts;
    final services = (await tester.runAsync(() => buildTestServices(api)))!;
    services.store.studyRefreshers.value = answer;
    await tester.pumpWidget(AppScope(services: services, child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: RefresherCards())))));
    await tester.pump();
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 80)));
    await tester.pump();
    return api;
  }

  testWidgets('an empty list shows nothing at all', (tester) async {
    await pump(tester, body([]));
    expect(find.byType(SectionLabel), findsNothing);
    expect(find.byType(Card), findsNothing);
  });

  testWidgets('a fixture renders one card per item with its title, two summary lines and both buttons', (tester) async {
    await pump(tester, body([card('r1', 'Module A changed'), card('r2', 'Module B changed')]));
    expect(find.byType(SectionLabel), findsOneWidget);
    expect(find.text('Module A changed'), findsOneWidget);
    expect(find.text('Module B changed'), findsOneWidget);
    expect(find.text('First thing that changed.'), findsNWidgets(2));
    expect(find.text('Refresh (3 questions)'), findsNWidgets(2));
    expect(find.text('Got it'), findsNWidgets(2));
  });

  testWidgets('Got it removes the card at once and posts dismissed once', (tester) async {
    final api = await pump(tester, body([card('r1', 'Module A changed'), card('r2', 'Module B changed')]));
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('refresher-r1')), matching: find.byKey(const Key('refresher-gotit'))));
    await tester.pump();
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    expect(find.text('Module A changed'), findsNothing);
    expect(find.text('Module B changed'), findsOneWidget);
    expect(api.posts, [
      {'path': '/api/study/refreshers/seen', 'id': 'r1', 'how': 'dismissed'},
    ]);
  });

  testWidgets('Refresh walks three questions, Show answer then Next, and Done posts refreshed once', (tester) async {
    final api = await pump(tester, body([card('r1', 'Module A changed')]));
    await tester.tap(find.byKey(const Key('refresher-start')));
    await tester.pump();
    expect(find.text('Question 1 of 3'), findsOneWidget);
    expect(find.text('Answer one.'), findsNothing);
    await tester.tap(find.byKey(const Key('refresher-show')));
    await tester.pump();
    expect(find.text('Answer one.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('refresher-next')));
    await tester.pump();
    expect(find.text('Question 2 of 3'), findsOneWidget);
    await tester.tap(find.byKey(const Key('refresher-show')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('refresher-next')));
    await tester.pump();
    expect(find.text('Question 3 of 3'), findsOneWidget);
    await tester.tap(find.byKey(const Key('refresher-show')));
    await tester.pump();
    expect(find.byKey(const Key('refresher-next')), findsNothing);
    await tester.tap(find.byKey(const Key('refresher-done')));
    await tester.pump();
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    expect(find.text('Module A changed'), findsNothing);
    expect(api.posts, [
      {'path': '/api/study/refreshers/seen', 'id': 'r1', 'how': 'refreshed'},
    ]);
  });

  testWidgets('a post that fails puts the card back', (tester) async {
    final api = await pump(tester, body([card('r1', 'Module A changed')]), failPosts: true);
    await tester.tap(find.byKey(const Key('refresher-gotit')));
    await tester.pump();
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    expect(find.text('Module A changed'), findsOneWidget, reason: 'restored after the failed post');
    expect(api.posts, isEmpty);
  });
}
