import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/study/pick/models.dart';
import 'package:isconl/study/pick/scorer.dart';
import 'package:isconl/study/study_service.dart';
import 'package:isconl/theme.dart';
import 'package:isconl/ui/widgets/study_pick_card.dart';

void main() {
  Map<String, dynamic> sampleData() => {
        'librarySyncedAt': '2026-10-26T15:30:00Z',
        'groups': [
          {'id': 'med', 'label': 'Medicine', 'color': '#3fb950'},
          {'id': 'corp', 'label': 'Corporate', 'color': '#2f81f7'},
        ],
        'courses': [
          {
            'ID': 'med-foundations',
            'GROUP_ID': 'med',
            'lessons': [
              {'file': 'anatomy.md', 'title': 'Human Anatomy 101', 'status': 'new'},
              {'file': 'physiology.md', 'title': 'Physiology Overview', 'status': 'new'},
              {'file': 'advanced.md', 'title': 'Advanced Pathology', 'status': 'new'},
            ],
          },
        ],
      };

  StudyPickResult sampleResult() {
    final card1 = const ModuleCard(
      id: 'med-foundations/anatomy.md',
      track: 'med',
      minutes: 25,
      difficulty: 2,
    );
    final cardLighter = const ModuleCard(
      id: 'med-foundations/physiology.md',
      track: 'med',
      minutes: 15,
      difficulty: 1,
    );
    final cardDeeper = const ModuleCard(
      id: 'med-foundations/advanced.md',
      track: 'med',
      minutes: 45,
      difficulty: 4,
    );

    final parts = [
      const ScorePart('fit', 0.85, 3.0),
      const ScorePart('coverage', 0.60, 2.0),
      const ScorePart('relevance', 0.50, 1.5),
    ];

    final top = Recommendation(
      card1,
      4.5,
      'fits the 25 minutes before your 15:00 block; Medicine is behind cycle pace',
      parts,
    );
    final lighter = Recommendation(
      cardLighter,
      3.2,
      'fits 15 minutes; light introductory reading',
      [const ScorePart('fit', 0.9, 3.0)],
    );
    final deeper = Recommendation(
      cardDeeper,
      3.0,
      'deeper dive into pathology',
      [const ScorePart('coverage', 0.8, 2.0)],
    );

    final now = DateTime(2026, 10, 26, 14, 30);
    final inputs = StudyInputs(
      now: now,
      cards: [card1, cardLighter, cardDeeper],
      minutesUntilNextBlock: 30,
      nextBlockLabel: '15:00',
      cycle: const CycleInfo(lengthDays: 7, dayOfCycle: 3),
      tracks: {
        'med': TrackState(
          unreadMinutes: 120,
          targetDate: DateTime(2026, 11, 24),
          minutesReadThisCycle: 20,
        ),
        'corp': TrackState(
          unreadMinutes: 90,
          targetDate: DateTime(2026, 12, 1),
          minutesReadThisCycle: 10,
        ),
      },
    );

    final pick = StudyPick(
      top: top,
      lighter: lighter,
      deeper: deeper,
      candidates: 3,
      scored: [top, lighter, deeper],
    );

    return StudyPickResult(
      pick,
      degraded: false,
      titles: {
        'med-foundations/anatomy.md': 'Human Anatomy 101',
        'med-foundations/physiology.md': 'Physiology Overview',
        'med-foundations/advanced.md': 'Advanced Pathology',
      },
      inputs: inputs,
    );
  }

  Widget buildCampusHost({
    required Widget child,
    double width = 360,
    double height = 640,
  }) {
    return MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            height: height,
            child: SingleChildScrollView(child: child),
          ),
        ),
      ),
    );
  }

  testWidgets('Campus screen 360 px first: Now card, fit line, Start button, alternates', (tester) async {
    final res = sampleResult();
    String? opened;

    await tester.pumpWidget(buildCampusHost(
      child: StudyPickCard(
        data: sampleData(),
        onOpen: (c, l) => opened = '$c/$l',
        picker: (_) async => res,
      ),
      width: 360,
    ));
    await tester.pumpAndSettle();

    // 1. Now card at top
    expect(find.byKey(const Key('study-pick')), findsOneWidget);
    expect(find.text('Human Anatomy 101'), findsOneWidget);
    expect(find.text('Medicine · med-foundations'), findsOneWidget);
    expect(find.text('25 min'), findsOneWidget);

    // Fit line
    expect(find.text('fits before your 15:00 block'), findsOneWidget);

    // Start button
    expect(find.byKey(const Key('study-pick-start')), findsOneWidget);
    await tester.tap(find.byKey(const Key('study-pick-start')));
    expect(opened, 'med-foundations/anatomy.md');

    // 3. Two alternates under it
    expect(find.byKey(const Key('study-pick-lighter')), findsOneWidget);
    expect(find.byKey(const Key('study-pick-deeper')), findsOneWidget);
    expect(find.textContaining('Physiology Overview'), findsOneWidget);
    expect(find.textContaining('Advanced Pathology'), findsOneWidget);

    // Tapping alternate
    await tester.tap(find.byKey(const Key('study-pick-lighter')));
    expect(opened, 'med-foundations/physiology.md');
  });

  testWidgets('Why this? expands score parts as bars in plain words with no raw numbers', (tester) async {
    final res = sampleResult();

    await tester.pumpWidget(buildCampusHost(
      child: StudyPickCard(
        data: sampleData(),
        onOpen: (_, _) {},
        picker: (_) async => res,
      ),
    ));
    await tester.pumpAndSettle();

    // 2. Why this?
    expect(find.byKey(const Key('study-pick-why')), findsOneWidget);
    await tester.tap(find.byKey(const Key('study-pick-why')));
    await tester.pumpAndSettle();

    expect(find.text('Why this?'), findsWidgets);
    expect(find.text('Fits before your 15:00 block'), findsOneWidget);
    expect(find.text('med is behind cycle pace'), findsOneWidget);

    // Verify NO raw numbers alone in score parts
    expect(find.text('0.85'), findsNothing);
    expect(find.text('2.55'), findsNothing);
  });

  testWidgets('Not now opens 4 chips and selecting one advances to next pick at once', (tester) async {
    final res = sampleResult();

    await tester.pumpWidget(buildCampusHost(
      child: StudyPickCard(
        data: sampleData(),
        onOpen: (_, _) {},
        picker: (_) async => res,
      ),
    ));
    await tester.pumpAndSettle();

    // 4. Not now
    expect(find.byKey(const Key('study-pick-not-now')), findsOneWidget);
    await tester.tap(find.byKey(const Key('study-pick-not-now')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('not-now-tired')), findsOneWidget);
    expect(find.byKey(const Key('not-now-no-time')), findsOneWidget);
    expect(find.byKey(const Key('not-now-not-relevant')), findsOneWidget);
    expect(find.byKey(const Key('not-now-skip')), findsOneWidget);

    // Tap 'Tired' chip
    await tester.tap(find.byKey(const Key('not-now-tired')));
    await tester.pumpAndSettle();

    // Next pick appears at once! (Human Anatomy 101 dismissed, next is Physiology Overview)
    expect(find.text('Human Anatomy 101'), findsNothing);
    expect(find.text('Physiology Overview'), findsOneWidget);
  });

  testWidgets('Coverage rings per track: tap displays forecast finish date', (tester) async {
    final res = sampleResult();

    await tester.pumpWidget(buildCampusHost(
      child: StudyPickCard(
        data: sampleData(),
        onOpen: (_, _) {},
        picker: (_) async => res,
      ),
    ));
    await tester.pumpAndSettle();

    // 5. Coverage rings
    expect(find.byKey(const Key('coverage-rings')), findsOneWidget);
    expect(find.byKey(const Key('coverage-ring-med')), findsOneWidget);
    expect(find.byKey(const Key('coverage-ring-corp')), findsOneWidget);

    // Tap med track ring
    await tester.tap(find.byKey(const Key('coverage-ring-med')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Medicine: forecast finish 24 Nov 2026'), findsOneWidget);
  });

  testWidgets('Week strip shows 7 dots with today highlighted', (tester) async {
    final res = sampleResult();

    await tester.pumpWidget(buildCampusHost(
      child: StudyPickCard(
        data: sampleData(),
        onOpen: (_, _) {},
        picker: (_) async => res,
      ),
    ));
    await tester.pumpAndSettle();

    // 6. Week strip
    expect(find.byKey(const Key('study-week-strip')), findsOneWidget);
    expect(find.text('Week plan'), findsOneWidget);
    expect(find.text('Day 3 of 7'), findsOneWidget);
  });

  testWidgets('Offline badge shows rebuilt from downloads when degraded', (tester) async {
    final normal = sampleResult();
    final degradedRes = StudyPickResult(
      normal.pick,
      degraded: true,
      titles: normal.titles,
      inputs: normal.inputs,
    );

    await tester.pumpWidget(buildCampusHost(
      child: StudyPickCard(
        data: sampleData(),
        onOpen: (_, _) {},
        picker: (_) async => degradedRes,
      ),
    ));
    await tester.pumpAndSettle();

    // 7. Offline degraded badge
    expect(find.byKey(const Key('study-pick-degraded')), findsOneWidget);
    expect(find.text('rebuilt from downloads'), findsOneWidget);
  });
}
