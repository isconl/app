import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/ui/widgets/news_watch_card.dart';

import 'support/test_services.dart';

class NewsApi extends ScriptedApi {
  NewsApi(super.answers);
  final List<Map<String, dynamic>> posts = [];
  Completer<Map<String, dynamic>>? sweepGate;

  @override
  Future<dynamic> postJson(String path, Map<String, dynamic> body, {bool cold = false}) async {
    posts.add({'path': path, ...body});
    if (path == '/api/news/sweep' && sweepGate != null) return sweepGate!.future;
    if (path == '/api/news/sweep') return {'success': true, 'raised': 3};
    return {'success': true};
  }
}

final competitors = {
  'competitors': [
    {'ID': 'c1', 'VENTURE': 'Viva', 'COMPETITOR': 'Rival Co', 'STATUS': 'active'},
    {'ID': 'c2', 'VENTURE': '-', 'COMPETITOR': 'Solo Rival', 'STATUS': 'disabled'},
  ],
};
final topics = {
  'topics': [
    {'ID': 't1', 'KIND': 'location', 'TERM': 'Nairobi', 'STATUS': 'active'},
  ],
};

void main() {
  test('a row is on unless it says disabled, and the competitor line drops an empty venture', () {
    expect(newsActive({'STATUS': 'active'}), isTrue);
    expect(newsActive({'STATUS': ''}), isTrue);
    expect(newsActive({}), isTrue);
    expect(newsActive({'STATUS': 'disabled'}), isFalse);
    expect(competitorLine({'VENTURE': 'Viva', 'COMPETITOR': 'Rival Co'}), 'Viva / Rival Co');
    expect(competitorLine({'VENTURE': '-', 'COMPETITOR': 'Solo Rival'}), 'Solo Rival');
    expect(competitorLine({'VENTURE': '', 'COMPETITOR': 'Solo Rival'}), 'Solo Rival');
  });

  test('the sweep result says how many were raised as alerts and never calls the count news', () {
    expect(sweepResultLine({'raised': 0}), 'Sweep finished. Nothing new.');
    expect(sweepResultLine({}), 'Sweep finished. Nothing new.');
    expect(sweepResultLine({'raised': 1}), 'Sweep finished. 1 new match raised as alert.');
    expect(sweepResultLine({'raised': 3}), 'Sweep finished. 3 new matches raised as alerts.');
  });

  Future<NewsApi> pump(WidgetTester tester, Map<String, Object> answers) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = NewsApi(answers);
    final services = (await tester.runAsync(() => buildTestServices(api)))!;
    await tester.pumpWidget(AppScope(services: services, child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: NewsWatchCard())))));
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

  testWidgets('both lists show and a paused competitor reads as off', (tester) async {
    await pump(tester, {'/api/news/competitors': competitors, '/api/news/topics': topics});
    expect(find.text('Viva / Rival Co'), findsOneWidget);
    expect(find.text('Solo Rival'), findsOneWidget);
    expect(tester.widget<Switch>(find.descendant(of: find.byKey(const Key('news-comp-c1')), matching: find.byType(Switch))).value, isTrue);
    expect(tester.widget<Switch>(find.descendant(of: find.byKey(const Key('news-comp-c2')), matching: find.byType(Switch))).value, isFalse);
    expect(find.text('Nairobi'), findsOneWidget);
    expect(find.text('location'), findsOneWidget);
  });

  testWidgets('an empty list says none yet', (tester) async {
    await pump(tester, {'/api/news/competitors': {'competitors': []}, '/api/news/topics': {'topics': []}});
    expect(find.text('None yet.'), findsNWidgets(2));
  });

  testWidgets('pausing a competitor posts its id and fields with status disabled', (tester) async {
    final api = await pump(tester, {'/api/news/competitors': competitors, '/api/news/topics': topics});
    await tester.tap(find.descendant(of: find.byKey(const Key('news-comp-c1')), matching: find.byType(Switch)));
    await settle(tester);
    final sent = api.posts.firstWhere((p) => p['path'] == '/api/news/competitors');
    expect(sent['id'], 'c1');
    expect(sent['competitor'], 'Rival Co');
    expect(sent['venture'], 'Viva');
    expect(sent['status'], 'disabled');
  });

  testWidgets('removing a term asks first and then posts its id', (tester) async {
    final api = await pump(tester, {'/api/news/competitors': competitors, '/api/news/topics': topics});
    await tester.tap(find.descendant(of: find.byKey(const Key('news-topic-t1')), matching: find.byType(IconButton)));
    await tester.pumpAndSettle();
    expect(api.posts.where((p) => p['path'] == '/api/news/topics/delete'), isEmpty, reason: 'nothing is sent before the confirm');
    await tester.tap(find.text('Remove').last);
    await settle(tester);
    expect(api.posts.firstWhere((p) => p['path'] == '/api/news/topics/delete')['id'], 't1');
  });

  testWidgets('adding a competitor and a term posts them with no id', (tester) async {
    final api = await pump(tester, {'/api/news/competitors': {'competitors': []}, '/api/news/topics': {'topics': []}});
    await tester.tap(find.byKey(const Key('news-add-comp')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('news-comp-name')), 'New Rival');
    await tester.enterText(find.byKey(const Key('news-comp-venture')), 'Wellspring');
    await tester.tap(find.byKey(const Key('news-comp-save')));
    await settle(tester);
    final c = api.posts.firstWhere((p) => p['path'] == '/api/news/competitors');
    expect(c.containsKey('id'), isFalse);
    expect(c['competitor'], 'New Rival');
    expect(c['venture'], 'Wellspring');

    await tester.tap(find.byKey(const Key('news-add-topic')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('news-topic-term')), 'Kenya fintech');
    await tester.tap(find.byKey(const Key('news-topic-save')));
    await settle(tester);
    final t = api.posts.firstWhere((p) => p['path'] == '/api/news/topics');
    expect(t['term'], 'Kenya fintech');
    expect(t['kind'], 'topic');
  });

  testWidgets('a double tap on Run sweep sends one request, and the result is the count raised as alerts', (tester) async {
    final api = await pump(tester, {'/api/news/competitors': competitors, '/api/news/topics': topics});
    api.sweepGate = Completer<Map<String, dynamic>>();
    await tester.tap(find.byKey(const Key('news-sweep')));
    await tester.pump();
    expect(find.text('Sweeping...'), findsOneWidget);
    await tester.tap(find.byKey(const Key('news-sweep')), warnIfMissed: false);
    await tester.pump();
    api.sweepGate!.complete({'success': true, 'raised': 2});
    await settle(tester);
    expect(api.posts.where((p) => p['path'] == '/api/news/sweep'), hasLength(1));
    expect(find.text('Sweep finished. 2 new matches raised as alerts.'), findsOneWidget);
  });
}
