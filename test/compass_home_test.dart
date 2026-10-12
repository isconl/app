import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/api/client.dart' show ApiException;
import 'package:isconl/app_scope.dart';
import 'package:isconl/ui/views/planning.dart';
import 'package:isconl/ui/widgets/compass_home.dart';

import 'support/test_services.dart';

class HomeApi extends ScriptedApi {
  HomeApi(super.answers, {this.postError});
  final List<Map<String, dynamic>> posts = [];
  final Object? postError;

  @override
  Future<dynamic> postJson(String path, Map<String, dynamic> body, {bool cold = false}) async {
    posts.add({'path': path, ...body});
    if (postError != null) throw postError!;
    return {'ok': true};
  }
}

Map<String, dynamic> eq({int day = 6, bool stillweek = false, dynamic season = 2}) => {
      'year': 2026,
      'yearLabel': '26',
      'season': season,
      'cycle': 5,
      'sprint': 9,
      'day': day,
      'stillweek': stillweek,
    };

Map<String, dynamic> cycle({bool needsTertiary = false, Map<String, dynamic>? next}) => {
      'source': 'auto',
      'needsTertiary': needsTertiary,
      'mix': {'primary': 'Leverage', 'secondary': 'Health', 'tertiary': 'Learning', 'weights': [60, 30, 10]},
      'next': next ?? {'cycleKey': 'eq2:26-C06', 'queued': null},
    };

void main() {
  test('the season line reads from the calendar answer, with the review cycle and the Stillweek worded as the web console does', () {
    expect(eqHeaderLine(eq()), 'Year 26 · Season 2 · Cycle 5 · Sprint 9');
    expect(eqHeaderLine(eq(season: null)), 'Year 26 · Review cycle · Cycle 5 · Sprint 9');
    expect(eqHeaderLine(eq(day: 3, stillweek: true)), 'Year 26 · the Stillweek, day 3');
    expect(cycleKeyOf(eq()), 'eq2:26-C05');
    expect(cycleKeyOf({'year': 2027, 'cycle': 13}), 'eq2:27-C13');
    expect(cycleKeyOf({}), isNull);
  });

  test('mix parts pair each named word with its weight and skip empty slots', () {
    expect(mixParts({'primary': 'Leverage', 'secondary': 'Health', 'tertiary': 'Learning', 'weights': [60, 30, 10]}).map((p) => '${p.word} ${p.weight}').toList(), ['Leverage 60', 'Health 30', 'Learning 10']);
    expect(mixParts({'primary': 'Leverage', 'tertiary': 'Learning', 'weights': [70, 30]}).map((p) => '${p.word} ${p.weight}').toList(), ['Leverage 70', 'Learning 30']);
    expect(mixParts({}), isEmpty);
  });

  test('prompts: the empty 10% slot always, the next-cycle prompts only from day 15, and a held or queued next cycle is read back', () {
    expect(mixPrompts(cycle(needsTertiary: true), 3).emptyTenth, isTrue);
    expect(mixPrompts(cycle(), 14).chooseNext, isFalse);
    expect(mixPrompts(cycle(), 15).chooseNext, isTrue);
    final queued = mixPrompts(cycle(next: {'cycleKey': 'eq2:26-C06', 'queued': {'word': 'Scout'}}), 20);
    expect(queued.queuedWord, 'Scout');
    expect(queued.held, isFalse);
    expect(mixPrompts(cycle(next: {'cycleKey': 'eq2:26-C06', 'queued': {'hold': true}}), 20).held, isTrue);
    expect(mixPrompts(cycle(next: {}), 20).chooseNext, isFalse);
  });

  test('habits group by stage in the fixed order, unknown stages read as maintenance, habits without a focus word are left out', () {
    final g = habitsByStage([
      {'id': 'a', 'focusWord': 'Leverage', 'stage': 'tertiary'},
      {'id': 'b', 'focusWord': 'Leverage', 'stage': 'primary'},
      {'id': 'c', 'focusWord': 'Health', 'stage': 'odd'},
      {'id': 'd', 'focusWord': '', 'stage': 'primary'},
    ]);
    expect(g.map((x) => x.stage).toList(), ['primary', 'tertiary', 'maintenance']);
    expect(g[0].habits.single['id'], 'b');
    expect(g[2].habits.single['id'], 'c');
  });

  test('goals group shortest horizon first with unknown horizons last', () {
    final g = plansByHorizon([
      {'HORIZON': 'Year'},
      {'HORIZON': 'sprint'},
      {'HORIZON': 'odd'},
      {'HORIZON': 'cycle'},
      {'HORIZON': 'sprint'},
    ]);
    expect(g.map((x) => '${x.horizon}:${x.plans.length}').toList(), ['sprint:2', 'cycle:1', 'year:1', 'odd:1']);
  });

  Future<HomeApi> pump(WidgetTester tester, Widget body, Map<String, Object> answers, {Object? postError, bool scroll = true}) async {
    final api = HomeApi(answers, postError: postError);
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final services = (await tester.runAsync(() => buildTestServices(api)))!;
    await tester.pumpWidget(AppScope(services: services, child: MaterialApp(home: Scaffold(body: scroll ? SingleChildScrollView(child: body) : body))));
    for (var i = 0; i < 4; i++) {
      await tester.pump();
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 60)));
    }
    await tester.pump();
    return api;
  }

  final rhythm = {
    'habits': [
      {'id': 'h1', 'title': 'Ship one thing', 'focusWord': 'Leverage', 'stage': 'primary'},
      {'id': 'h2', 'title': 'Walk', 'focusWord': 'Health', 'stage': 'secondary'},
    ],
    'logs': {
      '2026-10-12': {'h2': true},
    },
  };

  testWidgets('Focus shows the season line, the mix with its source, and the habits by slot, ticked as logged', (tester) async {
    final api = await pump(tester, const CompassFocus(today: '2026-10-12'), {
      '/api/calendar/eq': eq(),
      '/api/cycle-theme': cycle(),
      '/api/personal/rhythm': rhythm,
    });
    expect(find.text('Year 26 · Season 2 · Cycle 5 · Sprint 9'), findsOneWidget);
    expect(find.text('Leverage 60%  ·  Health 30%  ·  Learning 10%'), findsOneWidget);
    expect(find.text('auto'), findsOneWidget);
    expect(find.text('Ship one thing'), findsOneWidget);
    expect(tester.widget<Checkbox>(find.byKey(const Key('habit-h1'))).value, isFalse);
    expect(tester.widget<Checkbox>(find.byKey(const Key('habit-h2'))).value, isTrue);
    expect(api.asked, contains('/api/calendar/eq?date=2026-10-12'));
    expect(api.asked, contains('/api/cycle-theme?cycleKey=eq2%3A26-C05&resolve=1'));
    // Before day 15 and with a full mix, no prompts.
    expect(find.byKey(const Key('mix-next')), findsNothing);
    expect(find.byKey(const Key('mix-fill-tenth')), findsNothing);
  });

  testWidgets('from day 15 the next-cycle prompt shows, and Keep the primary posts a hold for the next cycle key', (tester) async {
    final api = await pump(tester, const CompassFocus(today: '2026-10-12'), {
      '/api/calendar/eq': eq(day: 16),
      '/api/cycle-theme': cycle(),
      '/api/personal/rhythm': rhythm,
    });
    expect(find.text('Pick the word that enters next cycle at 10%.'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('mix-hold')));
    await tester.tap(find.byKey(const Key('mix-hold')));
    await tester.pump();
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 80)));
    await tester.pump();
    expect(api.posts.single, {'path': '/api/cycle-theme/queue', 'cycleKey': 'eq2:26-C06', 'hold': true});
  });

  testWidgets('choosing a word posts it for the next cycle at 10%', (tester) async {
    final api = await pump(tester, const CompassFocus(today: '2026-10-12'), {
      '/api/calendar/eq': eq(day: 20),
      '/api/cycle-theme': cycle(),
      '/api/personal/rhythm': rhythm,
    });
    await tester.ensureVisible(find.byKey(const Key('mix-choose-next')));
    await tester.tap(find.byKey(const Key('mix-choose-next')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('compass-word')), 'Scout');
    await tester.tap(find.byKey(const Key('compass-word-save')));
    await tester.pump();
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 80)));
    await tester.pump();
    expect(api.posts.single, {'path': '/api/cycle-theme/queue', 'cycleKey': 'eq2:26-C06', 'word': 'Scout'});
  });

  testWidgets('a 409 from the queue reads as the hand-set message, not a status code', (tester) async {
    await pump(
      tester,
      const CompassFocus(today: '2026-10-12'),
      {'/api/calendar/eq': eq(day: 16), '/api/cycle-theme': cycle(), '/api/personal/rhythm': rhythm},
      postError: ApiException(409, 'conflict'),
    );
    await tester.ensureVisible(find.byKey(const Key('mix-hold')));
    await tester.tap(find.byKey(const Key('mix-hold')));
    await tester.pump();
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 80)));
    await tester.pump();
    expect(find.text('That cycle already has a mix you set by hand, so nothing was queued.'), findsOneWidget);
  });

  testWidgets('the empty 10% slot offers a word', (tester) async {
    await pump(tester, const CompassFocus(today: '2026-10-12'), {
      '/api/calendar/eq': eq(),
      '/api/cycle-theme': cycle(needsTertiary: true),
      '/api/personal/rhythm': rhythm,
    });
    expect(find.text('The 10% slot is empty.'), findsOneWidget);
    expect(find.byKey(const Key('mix-fill-tenth')), findsOneWidget);
  });

  testWidgets('the Planning home has the three parts and opens on Focus', (tester) async {
    await pump(tester, const PlanningView(), scroll: false, {
      '/api/calendar/eq': eq(),
      '/api/cycle-theme': cycle(),
      '/api/personal/rhythm': rhythm,
      '/api/plans': {
        'plans': [
          {'ID': 'p1', 'TITLE': 'Ship the app', 'HORIZON': 'sprint', 'tasks': []},
          {'ID': 'p2', 'TITLE': 'Year goal', 'HORIZON': 'year', 'tasks': []},
        ],
      },
    });
    for (final part in compassParts) {
      expect(find.text(part), findsWidgets);
    }
    expect(find.text('Year 26 · Season 2 · Cycle 5 · Sprint 9'), findsOneWidget);
  });
}
