import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/api/client.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/ui/views/learning.dart';
import 'package:isconl/ui/views/study_search_view.dart';
import 'package:isconl/util/study_search.dart';

import 'support/test_services.dart';

class _Api extends ApiClient {
  _Api() : super(baseUrl: 'http://test', token: 'test');
  @override
  Future<dynamic> getJson(String path, {bool cold = false, bool stored = true}) async => <String, dynamic>{};
}

const _md = '''
# Reading an Organisation

Intro paragraph about [[blueprint|the founders' early choices about structure]] and how they persist.

## MASTER · Who Writes Standards

The quiet part is that authorship of the standard is authorship of the selection criteria. Whoever
wrote the rules has already decided most of what the organisation will do.

## PROBE · Test Your Reading

**Probe:** A dentist is the busiest in her town. Which side is she on?
''';

void main() {
  late ModuleDoc doc;
  setUp(() => doc = indexModule('org', '04-standards.md', _md));

  test('indexing strips markup, keeps heading paths and the reader paragraph numbers', () {
    expect(doc.title, 'Reading an Organisation');
    final master = doc.paras.firstWhere((p) => p.text.contains('authorship of the standard'));
    expect(master.heading, 'MASTER · Who Writes Standards');
    expect(master.index, 3); // chunks: h1, intro, h2, body, ...
    expect(doc.paras.first.text, isNot(contains('[[')));
    expect(doc.terms.single.term, 'blueprint');
  });

  test('a body word finds its paragraph with the match marked in a short snippet', () {
    final r = searchDocs([doc], 'selection criteria');
    expect(r.text.length, 1);
    final h = r.text.single;
    expect(h.para.heading, startsWith('MASTER'));
    expect(h.marks, isNotEmpty);
    final (a, b) = h.marks.first;
    expect(h.snippet.substring(a, b).toLowerCase(), anyOf('selection', 'criteria'));
    expect(h.snippet.length, lessThanOrEqualTo(155));
  });

  test('a glossary term finds its definition, a title word finds the module', () {
    expect(searchDocs([doc], 'blueprint').glossary.single.term.definition, contains('founders'));
    expect(searchDocs([doc], 'organisation').modules.single.doc.key, 'org/04-standards.md');
  });

  test('under two characters returns nothing; every word must match; no match is empty', () {
    expect(searchDocs([doc], 'a').isEmpty, true);
    expect(searchDocs([doc], 'dentist banana').text, isEmpty);
    expect(searchDocs([doc], 'zzzzzz').isEmpty, true);
  });

  test('600 modules search in well under 150 ms', () {
    final big = List.generate(600, (i) => indexModule('c$i', 'm.md', '${_md.replaceAll('standard', 'standard$i')}\n\n${'filler text ' * 400}'));
    final sw = Stopwatch()..start();
    final r = searchDocs(big, 'dentist');
    sw.stop();
    expect(r.text.length, 30);
    expect(sw.elapsedMilliseconds, lessThan(150));
  });

  Future<AppServices> setup(WidgetTester t) async {
    t.view.physicalSize = const Size(600, 1200);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    return (await t.runAsync(() => buildTestServices(_Api(), online: false)))!;
  }

  testWidgets('results are grouped, and a text result opens the module at its paragraph', (t) async {
    final services = await setup(t);
    final index = StudyIndex.forTesting([doc]);
    await t.pumpWidget(AppScope(services: services, child: MaterialApp(home: StudySearchScreen(index: index))));
    await t.pump();
    await t.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
    await t.pump();

    await t.enterText(find.byKey(const Key('study-search-field')), 'standard');
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('IN THE TEXT'), findsOneWidget);

    await t.enterText(find.byKey(const Key('study-search-field')), 'blueprint');
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('GLOSSARY'), findsOneWidget);

    await t.enterText(find.byKey(const Key('study-search-field')), 'selection');
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.byKey(const ValueKey('text-org/04-standards.md-3')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    final lesson = t.widget<LessonScreen>(find.byType(LessonScreen));
    expect(lesson.course, 'org');
    expect(lesson.initialParagraph, 3);
    expect(lesson.foundText, contains('authorship of the standard'));
    for (var i = 0; i < 4; i++) {
      await t.runAsync(() => Future.delayed(const Duration(milliseconds: 150)));
      await t.pump(const Duration(seconds: 1));
    }
  });

  testWidgets('recent searches are kept (last 10) and can be cleared', (t) async {
    final services = await setup(t);
    final index = StudyIndex.forTesting([doc]);
    await t.pumpWidget(AppScope(services: services, child: MaterialApp(home: StudySearchScreen(index: index))));
    await t.pump();
    await t.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
    await t.pump();
    for (final q in ['alpha', 'beta']) {
      await t.enterText(find.byKey(const Key('study-search-field')), q);
      await t.testTextInput.receiveAction(TextInputAction.search);
      await t.pump();
      await t.runAsync(() => Future.delayed(const Duration(milliseconds: 60)));
      await t.pump();
    }
    await t.enterText(find.byKey(const Key('study-search-field')), '');
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('beta'), findsOneWidget);
    expect(find.text('alpha'), findsOneWidget);
    await t.tap(find.text('Clear'));
    await t.pump();
    await t.runAsync(() => Future.delayed(const Duration(milliseconds: 60)));
    await t.pump();
    expect(find.text('beta'), findsNothing);
  });
}
