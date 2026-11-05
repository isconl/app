import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/theme.dart';
import 'package:isconl/ui/widgets/compass_reviews.dart';

import 'support/test_services.dart';

/// BI26100136: the Compass season and year review cards on the phone, against fixtures in the shape scope serves.
Map<String, dynamic> season(int k, {bool offered = false, bool onTheDay = false, Map<String, dynamic>? review, List<dynamic> mixes = const []}) => {
      'season': k, 'key': 'eq2:26-S$k', 'cycles': [k * 3 - 2, k * 3], 'offered': offered, 'onTheDay': onTheDay, 'done': review != null, 'review': review, 'mixes': mixes,
    };

Map<String, dynamic> state(Map<String, dynamic> pos, List<Map<String, dynamic>> seasons, {Map<String, dynamic>? year}) => {
      'available': true,
      'position': pos,
      'seasons': seasons,
      'year': {'key': 'eq2:26-Y', 'open': false, 'review': null, 'seasonReviews': [], 'nextFirstCycle': 'eq2:27-C01', ...?year},
    };

final mixes = [
  {'cycleKey': 'eq2:26-C04', 'mix': {'primary': 'Plant', 'secondary': 'Make', 'weights': [67, 33]}},
  {'cycleKey': 'eq2:26-C05', 'mix': null},
];

void main() {
  test('a mix line names the cycle, the words and their weights, or says none is set', () {
    expect(reviewMixLine(mixes[0]), 'C04: Plant 67 / Make 33');
    expect(reviewMixLine(mixes[1]), 'C05: no mix set');
  });

  Future<ScriptedApi> pump(WidgetTester tester, Map<String, dynamic> body) async {
    final api = ScriptedApi({'/api/compass/review': body});
    final services = (await tester.runAsync(() => buildTestServices(api)))!;
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppScope(
      services: services,
      child: MaterialApp(theme: buildTheme(), home: const Scaffold(body: SingleChildScrollView(child: CompassReviews()))),
    ));
    await tester.pump();
    await tester.pump();
    return api;
  }

  testWidgets('mid-season shows only when the review opens', (tester) async {
    await pump(tester, state({'year': 2026, 'cycle': 4, 'day': 10, 'stillweek': false}, [season(1, offered: true, review: {'moved': 'm', 'change': 'c'}), season(2), season(3), season(4)]));
    expect(find.byKey(const Key('review-waiting')), findsOneWidget);
    expect(find.text('Season 2 review opens on the last day of C06.'), findsOneWidget);
    expect(find.byKey(const Key('review-moved-2')), findsNothing);
    expect(find.byKey(const Key('review-moved-1')), findsOneWidget, reason: 'the written season stays editable');
  });

  testWidgets('on 26·C06·D28 season 2 is offered due today with its mixes, and saving posts the year, season and texts', (tester) async {
    final posted = <String>[];
    final api = ScriptedApi({'/api/compass/review': state({'year': 2026, 'cycle': 6, 'day': 28, 'stillweek': false}, [season(1), season(2, offered: true, onTheDay: true, mixes: mixes), season(3), season(4)])});
    final services = (await tester.runAsync(() => buildTestServices(_Recording(api, posted))))!;
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppScope(
      services: services,
      child: MaterialApp(theme: buildTheme(), home: const Scaffold(body: SingleChildScrollView(child: CompassReviews()))),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text('Season 2 review'), findsOneWidget);
    expect(find.text('C04 to C06 · due today'), findsOneWidget);
    expect(find.text('C04: Plant 67 / Make 33'), findsOneWidget);
    expect(find.text('C05: no mix set'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('review-moved-2')), 'Shipped the grid');
    await tester.enterText(find.byKey(const Key('review-change-2')), 'Fewer threads');
    await tester.tap(find.byKey(const Key('review-save-2')));
    await tester.pump();
    expect(posted, ['/api/compass/review/season {year: 2026, season: 2, moved: Shipped the grid, change: Fewer threads}']);
  });

  testWidgets('C13 shows the year review with the four seasons and posts next year\'s first mix only with a primary word', (tester) async {
    final posted = <String>[];
    final seasons = [for (var k = 1; k <= 4; k++) season(k, offered: true, review: k == 4 ? null : {'moved': 'moved $k', 'change': 'change $k'})];
    final api = ScriptedApi({
      '/api/compass/review': state({'year': 2026, 'cycle': 13, 'day': 3, 'stillweek': false}, seasons,
          year: {'open': true, 'seasonReviews': [for (final s in seasons) {'season': s['season'], 'review': s['review']}]}),
    });
    final services = (await tester.runAsync(() => buildTestServices(_Recording(api, posted))))!;
    tester.view.physicalSize = const Size(900, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppScope(
      services: services,
      child: MaterialApp(theme: buildTheme(), home: const Scaffold(body: SingleChildScrollView(child: CompassReviews()))),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text('Year review · Audit'), findsOneWidget);
    expect(find.text('Moved: moved 1'), findsOneWidget);
    expect(find.text('not written'), findsOneWidget);
    expect(find.textContaining("Next year's first mix (C01)"), findsOneWidget);
    await tester.enterText(find.byKey(const Key('review-summary')), 'A year of base-building');
    await tester.tap(find.byKey(const Key('review-save-year')));
    await tester.pump();
    expect(posted.last, '/api/compass/review/year {year: 2026, summary: A year of base-building}');
    await tester.enterText(find.byKey(const Key('review-next-primary')), 'Revenue');
    await tester.tap(find.byKey(const Key('review-save-year')));
    await tester.pump();
    expect(posted.last, '/api/compass/review/year {year: 2026, summary: A year of base-building, nextMix: {primary: Revenue}}');
  });

  testWidgets('when the calendar service is down the card says so', (tester) async {
    await pump(tester, {'available': false, 'reason': 'the calendar service did not answer'});
    expect(find.textContaining('the calendar service did not answer'), findsOneWidget);
  });
}

/// A scripted API that also records what is posted.
class _Recording extends ScriptedApi {
  _Recording(ScriptedApi inner, this.log) : super(inner.answers);
  final List<String> log;

  @override
  Future<dynamic> postJson(String path, Map<String, dynamic> body, {bool cold = false}) async {
    log.add('$path $body');
    return {'success': true};
  }
}
