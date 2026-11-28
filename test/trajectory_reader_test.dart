import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/study/trajectory/trajectory_model.dart';
import 'package:isconl/study/trajectory/trajectory_view.dart';

Map<String, dynamic> _block() => {
      'question': 'Will the handover happen by March?',
      'horizon_90d': '2027-01-14',
      'horizon_12m': '2027-10-14',
      'rescore_on': '2026-11-01',
      'patterns': [
        {'id': 'P2', 'strength': 'strong'},
        {'id': 'P5', 'strength': 'weak'},
      ],
      'register': ['Private note about a person'],
      'scenarios': [
        {
          'id': 's1', 'name': 'Clean handover', 'p': 35, 'impact': 4, 'control': 2,
          'signal': 'A written timeline', 'basis': 'He said so twice.',
          'indicators': ['Calendar holds', 'Draft contract'], 'now': 'Ask for dates',
        },
        {
          'id': 's2', 'name': 'Slips a year', 'p': 50, 'impact': 5, 'control': 1,
          'signal': 'No dates', 'basis': 'Past pattern.', 'indicators': <String>[], 'now': 'Prepare plan B',
        },
      ],
    };

Widget _host(Widget w) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: w)));

void main() {
  group('pure functions', () {
    test('score is p x impact / 100 to two decimals', () {
      expect(scenarioScore(35, 4), 1.4);
      expect(scoreText(35, 4), '1.40');
      expect(scoreText(50, 5), '2.50');
      expect(scoreText(33, 3), '0.99');
      expect(scoreText(7, 3), '0.21');
    });

    test('stale only when more than 30 days past the re-score date', () {
      final d = DateTime(2026, 11, 1);
      expect(isStaleForecast(d, DateTime(2026, 12, 1)), isFalse); // exactly 30 days
      expect(isStaleForecast(d, DateTime(2026, 12, 2)), isTrue);
      expect(isStaleForecast(null, DateTime(2030)), isFalse);
      expect(isStaleForecast(DateTime(2027), DateTime(2026)), isFalse);
    });

    test('dots clamp to 1 to 5', () {
      expect(dotCount(0), 1);
      expect(dotCount(3), 3);
      expect(dotCount(9), 5);
    });

    test('probe accepts whole percentages only', () {
      expect(parseProbe('40'), 40);
      expect(parseProbe(' 40 % '), 40);
      expect(parseProbe('0'), 0);
      expect(parseProbe('100'), 100);
      expect(parseProbe('101'), isNull);
      expect(parseProbe('12.5'), isNull);
      expect(parseProbe('abc'), isNull);
      expect(parseProbe(''), isNull);
    });
  });

  group('parsing the served block', () {
    test('a module without scenarios shows no trajectory', () {
      expect(Trajectory.tryParse(null), isNull);
      expect(Trajectory.tryParse({'scenarios': []}), isNull);
      expect(Trajectory.tryParse('x'), isNull);
    });

    test('the register is closed unless SCONL_ONLY is no', () {
      expect(Trajectory.tryParse(_block())!.sconlOnly, isTrue);
      expect(Trajectory.tryParse(_block(), sconlOnly: 'yes')!.sconlOnly, isTrue);
      expect(Trajectory.tryParse(_block(), sconlOnly: 'no')!.sconlOnly, isFalse);
    });
  });

  group('TrajectoryReader', () {
    final now = DateTime(2026, 10, 15);

    testWidgets('ORIENT shows the question, both horizons and pattern chips; the table is locked until PROBE',
        (t) async {
      await t.pumpWidget(_host(TrajectoryReader(
        trajectory: Trajectory.tryParse(_block())!,
        saved: null,
        onSaveProbe: (_) async {},
        now: () => now,
      )));
      expect(find.text('Will the handover happen by March?'), findsOneWidget);
      expect(find.textContaining('14 Jan 2027'), findsOneWidget);
      expect(find.textContaining('14 Oct 2027'), findsOneWidget);
      expect(find.byKey(const Key('pattern-P2')), findsOneWidget);
      expect(find.byKey(const Key('table-locked')), findsOneWidget);
      expect(find.byKey(const Key('scenario-s1')), findsNothing);
      expect(find.text('Clean handover'), findsNothing);
    });

    testWidgets('a bad PROBE number is refused and nothing is saved', (t) async {
      final saved = <int>[];
      await t.pumpWidget(_host(TrajectoryReader(
        trajectory: Trajectory.tryParse(_block())!,
        saved: null,
        onSaveProbe: (n) async => saved.add(n),
        now: () => now,
      )));
      await t.enterText(find.byKey(const Key('probe-field')), '12.5');
      await t.tap(find.byKey(const Key('probe-save')));
      await t.pump();
      expect(find.byKey(const Key('probe-error')), findsOneWidget);
      expect(saved, isEmpty);
      expect(find.byKey(const Key('scenario-s1')), findsNothing);
    });

    testWidgets('locking in a number saves it and opens the table with the block\'s scores', (t) async {
      final saved = <int>[];
      await t.pumpWidget(_host(TrajectoryReader(
        trajectory: Trajectory.tryParse(_block())!,
        saved: null,
        onSaveProbe: (n) async => saved.add(n),
        now: () => now,
      )));
      await t.enterText(find.byKey(const Key('probe-field')), '40');
      await t.tap(find.byKey(const Key('probe-save')));
      await t.pumpAndSettle();
      expect(saved, [40]);
      expect(find.byKey(const Key('probe-saved')), findsOneWidget);
      expect(find.textContaining('40%'), findsWidgets);
      expect(t.widget<Text>(find.byKey(const Key('score-s1'))).data, '1.40');
      expect(t.widget<Text>(find.byKey(const Key('score-s2'))).data, '2.50');
      expect(t.widget<LinearProgressIndicator>(find.byKey(const Key('bar-s1'))).value, 0.35);
      expect(find.descendant(of: find.byKey(const Key('impact-s1')), matching: find.byIcon(Icons.circle)), findsNWidgets(4));
      expect(find.descendant(of: find.byKey(const Key('control-s1')), matching: find.byIcon(Icons.circle)), findsNWidgets(2));
    });

    testWidgets('a saved number comes back on return and the table is open', (t) async {
      await t.pumpWidget(_host(TrajectoryReader(
        trajectory: Trajectory.tryParse(_block())!,
        saved: ProbeEntry(60, DateTime(2026, 10, 1)),
        onSaveProbe: (_) async {},
        now: () => now,
      )));
      expect(find.textContaining('Your forecast: 60%'), findsOneWidget);
      expect(find.byKey(const Key('probe-field')), findsNothing);
      expect(find.byKey(const Key('scenario-s2')), findsOneWidget);
    });

    testWidgets('tapping a row shows its basis and indicators', (t) async {
      await t.pumpWidget(_host(TrajectoryReader(
        trajectory: Trajectory.tryParse(_block())!,
        saved: ProbeEntry(60, DateTime(2026, 10, 1)),
        onSaveProbe: (_) async {},
        now: () => now,
      )));
      expect(find.byKey(const Key('basis-s1')), findsNothing);
      await t.tap(find.byKey(const Key('scenario-s1')));
      await t.pump();
      expect(find.text('He said so twice.'), findsOneWidget);
      expect(find.text('• Draft contract'), findsOneWidget);
    });

    testWidgets('the stale badge appears only more than 30 days past the re-score date', (t) async {
      Future<void> pump(DateTime now) => t.pumpWidget(_host(TrajectoryReader(
            trajectory: Trajectory.tryParse(_block())!,
            saved: ProbeEntry(60, DateTime(2026, 10, 1)),
            onSaveProbe: (_) async {},
            now: () => now,
          )));
      await pump(DateTime(2026, 11, 20));
      expect(find.byKey(const Key('stale-badge')), findsNothing);
      expect(find.textContaining('Re-score on 1 Nov 2026'), findsOneWidget);
      await pump(DateTime(2026, 12, 5));
      expect(find.byKey(const Key('stale-badge')), findsOneWidget);
    });

    testWidgets('register text is never shown unless SCONL_ONLY is no', (t) async {
      Future<void> pump(Object? flag) => t.pumpWidget(_host(TrajectoryReader(
            trajectory: Trajectory.tryParse(_block(), sconlOnly: flag)!,
            saved: ProbeEntry(60, DateTime(2026, 10, 1)),
            onSaveProbe: (_) async {},
            now: () => now,
          )));
      await pump(null);
      expect(find.text('Private note about a person'), findsNothing);
      await pump('no');
      expect(find.text('Private note about a person'), findsOneWidget);
    });
  });
}
