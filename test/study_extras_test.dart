import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/services/study_extras.dart';
import 'package:isconl/theme.dart';
import 'package:isconl/ui/widgets/study_extras.dart';
import 'package:isconl/util/markdown.dart';

class FakeStudy implements StudyExtrasApi {
  Campus campusData = const Campus(bands: []);
  Contributions contribs = const Contributions(days: [], total: 0);
  final calls = <String>[];
  PrimeResult primeData = const PrimeResult(ok: true, course: 'c1', file: 'm1.md', content: 'Line');
  Object? tutorFails;
  String answer = 'It means **this**.';

  @override
  Future<Campus> campus() async => campusData;
  @override
  Future<Contributions> studyContributions() async => contribs;
  @override
  Future<Contributions> githubContributions({bool refresh = false}) async {
    calls.add('gh:${refresh ? 'refresh' : 'cached'}');
    return contribs;
  }

  @override
  Future<PrimeResult> prime(String q) async {
    calls.add('prime:$q');
    return primeData;
  }

  @override
  Future<String> tutor({required String course, required String file, required String question}) async {
    calls.add('tutor:$course/$file:$question');
    if (tutorFails != null) throw tutorFails!;
    return answer;
  }
}

Widget host(Widget w) => MaterialApp(theme: buildTheme(), home: Scaffold(body: SingleChildScrollView(child: w)));

Contributions week(List<int> counts, {String start = '2026-10-04'}) {
  final d0 = DateTime.parse(start);
  return Contributions(
    days: [for (var i = 0; i < counts.length; i++) ContribDay(d0.add(Duration(days: i)).toIso8601String().substring(0, 10), counts[i])],
    total: counts.fold(0, (a, b) => a + b),
  );
}

void main() {
  group('parsing', () {
    test('campus bands and items', () {
      final c = HubStudyExtrasApi.parseCampus({
        'minutes': 25,
        'computed': true,
        'bands': [
          {'label': 'Now', 'tone': 'urgent', 'items': [
            {'courseId': 'c1', 'lesson': 'm1.md', 'title': 'Mod', 'courseTitle': 'Course', 'minutes': 10, 'status': 'done'},
          ]},
        ],
      });
      expect(c.minutes, 25);
      expect(c.computed, isTrue);
      expect(c.bands.single.items.single.done, isTrue);
      expect(c.isEmpty, isFalse);
      expect(const Campus(bands: []).isEmpty, isTrue);
    });

    test('contributions: total falls back to a real sum, streak and active days', () {
      final c = HubStudyExtrasApi.parseContributions({
        'days': [
          {'date': '2026-10-10', 'count': 0},
          {'date': '2026-10-11', 'count': 2},
          {'date': '2026-10-12', 'count': 5},
        ],
      });
      expect(c.total, 7);
      expect(c.activeDays, 2);
      expect(c.streak, 2);
      expect(HubStudyExtrasApi.parseContributions({'days': [], 'totalContributions': 40}).total, 40);
    });

    test('intensity levels are relative to the busiest day', () {
      final c = week([0, 1, 3, 5, 8]);
      expect([for (final d in c.days) c.level(d.count)], [0, 1, 2, 3, 4]);
    });

    test('the tutor question quotes the passage first', () {
      final q = tutorQuestion('A long   passage\nof text.', 'What does it mean?');
      expect(q, 'About this passage from the module: "A long passage of text."\n\nWhat does it mean?');
      expect(tutorQuestion('x' * 500, 'q').contains('...'), isTrue);
    });
  });

  group('CampusCard', () {
    testWidgets('shows bands with a computed flag and opens a module', (t) async {
      final api = FakeStudy()
        ..campusData = const Campus(computed: true, minutes: 15, bands: [
          CampusBand(label: 'Read now', tone: 'urgent', items: [
            CampusItem(courseId: 'c1', lesson: 'm1.md', title: 'Negotiation', courseTitle: 'Sales', minutes: 12, why: 'Meeting tomorrow'),
          ]),
          CampusBand(label: 'Empty', tone: 'later', items: []),
        ]);
      final opened = <String>[];
      await t.pumpWidget(host(CampusCard(api: api, onOpen: (c, l) => opened.add('$c/$l'))));
      await t.pumpAndSettle();
      expect(find.text('Campus'), findsOneWidget);
      expect(find.textContaining('about 15 min for the urgent ones'), findsOneWidget);
      expect(find.byKey(const Key('campus-computed')), findsOneWidget);
      expect(find.text('READ NOW'), findsOneWidget);
      expect(find.text('EMPTY'), findsNothing); // an empty band is not shown
      expect(find.text('Meeting tomorrow'), findsOneWidget);
      await t.tap(find.byKey(const Key('campus-c1-m1.md')));
      expect(opened, ['c1/m1.md']);
    });

    testWidgets('collapses on a tap of the header and says nothing when there is no advice', (t) async {
      final api = FakeStudy()
        ..campusData = const Campus(bands: [
          CampusBand(label: 'Now', tone: 'urgent', items: [CampusItem(courseId: 'c', lesson: 'l', title: 'T', courseTitle: 'C')]),
        ]);
      await t.pumpWidget(host(CampusCard(api: api, onOpen: (_, __) {})));
      await t.pumpAndSettle();
      expect(find.text('T'), findsOneWidget);
      await t.tap(find.byKey(const Key('campus-head')));
      await t.pumpAndSettle();
      expect(find.text('T'), findsNothing);
      final empty = FakeStudy();
      await t.pumpWidget(host(CampusCard(key: const Key('other'), api: empty, onOpen: (_, __) {})));
      await t.pumpAndSettle();
      expect(find.text('Campus'), findsNothing);
    });
  });

  group('ContributionsCard', () {
    testWidgets('draws the stats and the grid', (t) async {
      final c = week([0, 2, 4, 6, 0, 1, 3]);
      await t.pumpWidget(host(ContributionsCard(title: 'Study activity', loader: (_) async => c)));
      await t.pumpAndSettle();
      expect(t.widget<Text>(find.byKey(const Key('contrib-total'))).data, '16');
      expect(t.widget<Text>(find.byKey(const Key('contrib-active'))).data, '5');
      expect(t.widget<Text>(find.byKey(const Key('contrib-streak'))).data, '2');
      expect(find.byKey(const Key('day-2026-10-05')), findsOneWidget);
    });

    testWidgets('Refresh forces a fresh read for GitHub', (t) async {
      final api = FakeStudy()..contribs = week([1, 2, 3]);
      await t.pumpWidget(host(ContributionsCard(title: 'Activity', canRefresh: true, loader: (r) => api.githubContributions(refresh: r))));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('contrib-refresh')));
      await t.pumpAndSettle();
      expect(api.calls, ['gh:cached', 'gh:refresh']);
    });

    testWidgets('no activity and a failed load both say so', (t) async {
      await t.pumpWidget(host(ContributionsCard(title: 'A', loader: (_) async => const Contributions(days: [], total: 0))));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('contrib-empty')), findsOneWidget);
      await t.pumpWidget(host(ContributionsCard(key: const Key('b'), title: 'B', loader: (_) async => throw Exception('down'))));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('contrib-error')), findsOneWidget);
    });
  });

  group('PrimeCard', () {
    testWidgets('finds the lesson on a tap, shows a preview and the full text on request', (t) async {
      final api = FakeStudy()..primeData = PrimeResult(ok: true, course: 'c1', file: 'm1.md', content: List.generate(60, (i) => 'Line number $i').join('\n'));
      await t.binding.setSurfaceSize(const Size(420, 3000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(host(PrimeCard(query: 'Negotiate the lease', api: api)));
      expect(find.byKey(const Key('prime-source')), findsNothing);
      await t.tap(find.byKey(const Key('prime-go')));
      await t.pumpAndSettle();
      expect(api.calls, ['prime:Negotiate the lease']);
      expect(find.text('c1 · m1.md'), findsOneWidget);
      expect(find.textContaining('Line number 39'), findsOneWidget);
      expect(find.textContaining('Line number 45'), findsNothing);
      await t.tap(find.byKey(const Key('prime-more')));
      await t.pumpAndSettle();
      expect(find.textContaining('Line number 55'), findsOneWidget);
    });

    testWidgets('no matching lesson says so', (t) async {
      final api = FakeStudy()..primeData = const PrimeResult(ok: false, error: 'No module matched');
      await t.pumpWidget(host(PrimeCard(query: 'x', api: api)));
      await t.tap(find.byKey(const Key('prime-go')));
      await t.pumpAndSettle();
      expect(find.text('No module matched'), findsOneWidget);
    });
  });

  group('tutor', () {
    Widget paragraphs(TutorController c) => MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Markdown(
                'First paragraph here.\n\nSecond paragraph here.',
                paragraphHook: ParagraphHook(
                  onLongPress: (i, t) {},
                  footer: (i, t) => TutorFooter(controller: c, paragraph: i, text: t),
                ),
              ),
            ),
          ),
        );

    testWidgets('with Ask on, a paragraph offers the tutor; the question quotes it and the answer shows under that paragraph only', (t) async {
      final api = FakeStudy();
      final c = TutorController(api: api, course: 'c1', file: 'm1.md');
      await t.pumpWidget(paragraphs(c));
      expect(find.byKey(const Key('tutor-ask-0')), findsNothing); // off by default
      c.toggleMode();
      await t.pumpAndSettle();
      expect(find.byKey(const Key('tutor-ask-0')), findsOneWidget);
      expect(find.byKey(const Key('tutor-ask-1')), findsOneWidget);
      await t.tap(find.byKey(const Key('tutor-ask-1')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('tutor-passage')), findsOneWidget);
      await t.enterText(find.byKey(const Key('tutor-question')), 'Why?');
      await t.tap(find.byKey(const Key('tutor-send')));
      await t.pumpAndSettle();
      expect(api.calls.single, startsWith('tutor:c1/m1.md:About this passage from the module: "Second paragraph here."'));
      expect(api.calls.single, endsWith('Why?'));
      expect(find.byKey(const Key('tutor-1')), findsOneWidget);
      expect(find.byKey(const Key('tutor-0')), findsNothing);
      expect(find.textContaining('this'), findsWidgets);
    });

    testWidgets('a failed answer shows the reason, and Dismiss clears it', (t) async {
      final api = FakeStudy()..tutorFails = Exception('The tutor is resting');
      final c = TutorController(api: api, course: 'c1', file: 'm1.md');
      await t.pumpWidget(paragraphs(c));
      c.toggleMode();
      await t.pumpAndSettle();
      await c.ask(0, 'First paragraph here.', 'Why?');
      await t.pumpAndSettle();
      expect(find.byKey(const Key('tutor-error')), findsOneWidget);
      expect(find.textContaining('The tutor is resting'), findsOneWidget);
      await t.tap(find.byKey(const Key('tutor-dismiss-0')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('tutor-0')), findsNothing);
    });

    test('an empty question is not sent', () async {
      final api = FakeStudy();
      final c = TutorController(api: api, course: 'c', file: 'f');
      await c.ask(0, 'text', '   ');
      expect(api.calls, isEmpty);
    });

    test('a new question on the same paragraph replaces its answer', () async {
      final api = FakeStudy();
      final c = TutorController(api: api, course: 'c', file: 'f');
      await c.ask(2, 'p', 'one');
      api.answer = 'Second answer';
      await c.ask(2, 'p', 'two');
      expect(c.answers[2], 'Second answer');
      expect(c.answers.length, 1);
    });
  });
}
