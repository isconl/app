import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/data/db.dart';
import 'package:isconl/study/before_room.dart';
import 'package:isconl/study/finish_model.dart';
import 'package:isconl/study/forecast.dart';
import 'package:isconl/study/pick/models.dart';
import 'package:isconl/study/session_log.dart';
import 'package:isconl/study/week_plan.dart';
import 'package:isconl/theme.dart';
import 'package:isconl/ui/widgets/study_model_card.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../console/test_services.dart';

Future<AppDb> freshDb() async {
  final raw = await databaseFactory.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      singleInstance: false,
      version: 8,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE study_sessions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            module TEXT NOT NULL,
            started_at INTEGER NOT NULL,
            ended_at INTEGER NOT NULL,
            fraction_read REAL NOT NULL,
            finished INTEGER NOT NULL,
            hour INTEGER NOT NULL,
            block_name TEXT,
            energy INTEGER,
            not_now_reason TEXT,
            synced INTEGER NOT NULL DEFAULT 0
          )''');
      },
    ),
  );
  return AppDb.forTesting(raw);
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Study assistant 5/5', () {
    test('1. Session log writes to local SQLite table study_sessions and counts correctly', () async {
      final db = await freshDb();
      final log = StudySessionLog(db);

      expect(await log.count(), 0);

      final now = DateTime(2026, 10, 26, 15, 0);
      final rec = StudySessionRecord(
        module: 'anatomy/intro.md',
        startedAt: now.subtract(const Duration(minutes: 25)),
        endedAt: now,
        fractionRead: 1.0,
        finished: true,
        hour: 15,
        blockName: 'focus',
        energy: 4,
      );

      await log.logSession(rec);
      expect(await log.count(), 1);

      final history = await log.getSessions();
      expect(history.length, 1);
      expect(history.first.module, 'anatomy/intro.md');
      expect(history.first.finished, isTrue);
      expect(history.first.hour, 15);
      expect(history.first.energy, 4);

      // Seed 30 sessions
      await log.seedTestSessions(30);
      expect(await log.count(), 31);
    });

    test('2. Finish model: Beta prior, hour/energy/duration bands, isActive threshold', () {
      final model = StudyFinishModel();

      // Empty model is not active (< 30 sessions)
      expect(model.isActive, isFalse);
      expect(model.sessions.length, 0);

      // Default baseline prior before 30 sessions returns 0.5
      final baselineRate = model.predictFinishRate(
        hour: 14,
        energy: 3,
        minutes: 20,
      );
      expect(baselineRate, 0.5);

      // Create model with 35 sessions (28 finished, 7 dropped)
      final records = <StudySessionRecord>[];
      final now = DateTime(2026, 10, 26, 10, 0);
      for (int i = 0; i < 35; i++) {
        final finished = i % 5 != 0; // 80% finished
        records.add(StudySessionRecord(
          module: 'course/m$i.md',
          startedAt: now.subtract(Duration(minutes: 30 * (35 - i))),
          endedAt: now.subtract(Duration(minutes: 30 * (35 - i) - 20)),
          fractionRead: finished ? 1.0 : 0.4,
          finished: finished,
          hour: 10, // Morning
          energy: 8, // High energy
        ));
      }

      final trainedModel = StudyFinishModel(sessions: records);
      expect(trainedModel.isActive, isTrue);
      expect(trainedModel.sessions.length, 35);

      // Finish probability in trained condition (morning, high energy) should be high
      final trainedRate = trainedModel.predictFinishRate(
        hour: 10,
        energy: 8,
        minutes: 20,
      );
      expect(trainedRate, greaterThan(0.75));

      // In untracked hour, falls back to broader hour bucket prior
      final fallbackRate = trainedModel.predictFinishRate(
        hour: 23, // night
        energy: 1, // low
        minutes: 45,
      );
      expect(fallbackRate, lessThan(trainedRate));
    });

    test('3. Before-the-room picks: matches upcoming calendar events in 48h to modules', () {
      const service = BeforeTheRoomService();
      final now = DateTime(2026, 10, 26, 9, 0);

      final events = [
        {
          'title': 'Cardiology Clinic Ward Round',
          'start': now.add(const Duration(hours: 4)).toIso8601String(),
          'location': 'Ward 4B',
        },
        {
          'title': 'Board Meeting Corporate Governance',
          'start': now.add(const Duration(hours: 36)).toIso8601String(),
          'location': 'HQ 12F',
        },
        {
          'title': 'Next Month Review',
          'start': now.add(const Duration(days: 10)).toIso8601String(),
        },
      ];

      final candidateCards = [
        const ModuleCard(
          id: 'med/cardio.md',
          track: 'med',
          minutes: 20,
          difficulty: 3,
          subjects: ['cardiology'],
        ),
        const ModuleCard(
          id: 'corp/governance.md',
          track: 'corp',
          minutes: 30,
          difficulty: 2,
          subjects: ['corporate governance'],
        ),
        const ModuleCard(
          id: 'general/misc.md',
          track: 'general',
          minutes: 15,
          difficulty: 1,
          subjects: ['general surgery'],
        ),
      ];

      final matched = service.findPicks(
        now: now,
        events: events,
        cards: candidateCards,
      );

      expect(matched.length, 2);
      expect(matched.any((m) => m.moduleCard.id == 'med/cardio.md'), isTrue);
      expect(matched.any((m) => m.moduleCard.id == 'corp/governance.md'), isTrue);
      expect(matched.any((m) => m.moduleCard.id == 'general/misc.md'), isFalse);

      final cardioMatch = matched.firstWhere((m) => m.moduleCard.id == 'med/cardio.md');
      expect(cardioMatch.eventTitle, 'Cardiology Clinic Ward Round');
      expect(cardioMatch.matchedSubject, 'cardiology');
    });

    test('4. Cycle week plan: distributes track debt into daily available minutes and replanning', () {
      const cycle = CycleInfo(
        dayOfCycle: 2,
        lengthDays: 7,
      );

      final now = DateTime(2026, 10, 26);
      final Map<String, TrackState> tracks = {
        'med': TrackState(
          unreadMinutes: 120,
          targetDate: now.add(const Duration(days: 60)),
          cyclesBehind: 2.0,
        ),
        'corp': TrackState(
          unreadMinutes: 40,
          targetDate: now.add(const Duration(days: 60)),
          cyclesBehind: 0.5,
        ),
      };

      final plan = CycleWeekPlan.plan(
        cycle: cycle,
        tracks: tracks,
        dailyFreeMinutes: [30, 45, 30, 60, 30, 20, 20],
        currentDay: 2,
      );

      expect(plan.days.length, 7);
      expect(plan.totalPlannedMinutes, greaterThan(100));
      // Day 1 was before currentDay (day 2), so isMissed/past is true
      expect(plan.days[0].isMissed, isTrue);
      // Day 2 is current day, so isMissed is false
      expect(plan.days[1].isMissed, isFalse);
      // Track behind (med) is scheduled first
      expect(plan.days[0].trackId, 'med');
    });

    test('5. Track pace forecast: finish forecasts based on 4-cycle pace average and detects > 2 cycles miss', () {
      final now = DateTime(2026, 10, 26, 12, 0);
      final targetDate = now.add(const Duration(days: 28)); // 4 cycles ahead

      // On-track pace (60 min/cycle average, 200 min left -> needs ~3.3 cycles)
      final onTrack = TrackPaceForecast.calculate(
        trackId: 'med',
        trackLabel: 'Medicine',
        unreadMinutes: 200,
        targetDate: targetDate,
        lastFourCyclesMinutes: [60, 55, 65, 60], // avg 60
        now: now,
      );
      expect(onTrack.isMissByTwoCycles, isFalse);

      // Severely behind track (pace 5 min/cycle -> 20 cycles needed, misses target by 16 cycles!)
      final behindTrack = TrackPaceForecast.calculate(
        trackId: 'corp',
        trackLabel: 'Corporate',
        unreadMinutes: 100,
        targetDate: targetDate,
        lastFourCyclesMinutes: [5, 5, 5, 5],
        now: now,
      );
      expect(behindTrack.isMissByTwoCycles, isTrue);
    });

    testWidgets('6. Settings screen shows finish model status and updates when seeded', (tester) async {
      final services = (await tester.runAsync(() => buildTestServices()))!;

      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: AppScope(
          services: services,
          child: const Scaffold(
            body: SingleChildScrollView(child: StudyModelSettingCard()),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('study-finish-model-status')), findsOneWidget);
      expect(find.textContaining('Off (waiting for 30 sessions'), findsOneWidget);

      // Tap Seed 30 button
      expect(find.byKey(const Key('seed-study-sessions')), findsOneWidget);
      await tester.tap(find.byKey(const Key('seed-study-sessions')));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();

      // Now model is Active!
      expect(find.textContaining('Active (trained on 30 sessions)'), findsOneWidget);
    });
  });
}
