// BI26101806: the two lines under the ring on every Console face, and the shared layout that keeps the card one shape.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/console/console_lines.dart';
import 'package:isconl/ui/widgets/console_faces.dart' show ConsoleFaceLayout;
import 'package:isconl/ui/widgets/context_ring_card.dart';

import 'test_services.dart';

DateTime _nairobi(int h, int m) => DateTime.utc(2026, 10, 18, h - 3, m); // 10:00 Nairobi is 07:00 UTC

void main() {
  setUpAll(initSqfliteForTests);

  group('pulse lines (the daily block)', () {
    test('inside a block: the block and the time left, then the next block and its start', () {
      final l = pulseLines(currentName: 'Deep work', leftMins: 42, nextName: 'Lunch', nextStart: '13:00', load: '2/4 slots');
      expect(l.line1, 'Deep work · 42m left');
      expect(l.line2, 'Next: Lunch at 13:00');
      expect(l.chip, '2/4 slots');
    });

    test('hours and minutes read as 1h 5m, whole hours as 2h, under a minute as under 1m', () {
      expect(leftWords(65), '1h 5m');
      expect(leftWords(120), '2h');
      expect(leftWords(0.4), 'under 1m');
      expect(leftWords(59), '59m');
    });

    test('before the day starts and after it ends', () {
      final before = pulseLines(before: true, nextName: 'Deep work', nextStart: '08:00');
      expect(before.line1, 'Before the day starts');
      expect(before.line2, 'Next: Deep work at 08:00');
      final after = pulseLines(after: true);
      expect(after.line1, 'Day done');
      expect(after.line2, 'Back at 08:00 tomorrow');
    });

    test('between blocks with nothing after', () {
      final l = pulseLines();
      expect(l.line1, 'Between blocks');
      expect(l.line2, 'No more blocks today');
    });
  });

  group('recorder lines', () {
    test('ready, recording, paused, take, and saved', () {
      expect(recorderLines(state: RecState.idle).line1, 'Ready to record');
      expect(recorderLines(state: RecState.recording, elapsed: const Duration(minutes: 2, seconds: 13)).line1, 'Recording 02:13');
      expect(recorderLines(state: RecState.paused, elapsed: const Duration(seconds: 5)).line1, 'Paused 00:05');
      expect(recorderLines(state: RecState.review, elapsed: const Duration(seconds: 70)).line1, 'Take 01:10 · keep or discard');
      expect(recorderLines(state: RecState.idle, savedFor: const Duration(minutes: 2, seconds: 13)).line1, 'Saved 02:13');
    });

    test('line 2 names where it goes and the last one, in Nairobi time', () {
      final at = DateTime.utc(2026, 10, 17, 12, 42).millisecondsSinceEpoch; // 15:42 Nairobi
      expect(recorderLines(state: RecState.idle, lastAtMs: at).line2, 'Saves to hold · Audio/recordings · last 17 Oct 15:42');
      expect(recorderLines(state: RecState.idle).line2, 'Saves to hold · Audio/recordings · none yet');
    });
  });

  group('the card', () {
    // A plain 08:00 to 17:00 day, so the lines at fixed times do not depend on the default schedule.
    final plan = {
      'blocks': [
        {'name': 'Deep work', 'start': 480, 'end': 780, 'axis': 'work', 'third': 'Work', 'slots': 4, 'placeable': true},
        {'name': 'Lunch', 'start': 780, 'end': 840, 'axis': 'home', 'third': 'Home', 'slots': 0, 'placeable': false},
        {'name': 'Study', 'start': 840, 'end': 1020, 'axis': 'work', 'third': 'Work', 'slots': 2, 'placeable': true},
      ],
    };

    Future<AppServices> pump(WidgetTester t, DateTime now) async {
      final services = (await t.runAsync(() => buildTestServices()))!;
      services.store.dayBlock.value = plan;
      await t.pumpWidget(AppScope(
        services: services,
        child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ContextRingCard(clock: () => now)))),
      ));
      await t.pump();
      return services;
    }

    Future<void> cycle(WidgetTester t) async {
      for (var i = 0; i < 2; i++) {
        await t.tap(find.byKey(const ValueKey('console-pill')));
        await t.pump(const Duration(milliseconds: 80));
      }
      await t.pump(const Duration(milliseconds: 250));
    }

    testWidgets('the default face reads Console · pulse and carries the two lines', (t) async {
      await pump(t, _nairobi(10, 0));
      expect(t.widget<Text>(find.byKey(const ValueKey('console-pill'))).data, 'Console · pulse');
      expect(t.widget<Text>(find.byKey(const ValueKey('console-pulse-line1'))).data, 'Deep work · 3h left');
      expect(t.widget<Text>(find.byKey(const ValueKey('console-pulse-line2'))).data, 'Next: Lunch at 13:00');
      expect(find.text('2/4 slots'), findsNothing, reason: 'the load chip is for placeable blocks with tasks; here it reads from the plan');
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 31));
    });

    testWidgets('after 17:00 the lines say the day is done', (t) async {
      await pump(t, _nairobi(18, 30));
      expect(t.widget<Text>(find.byKey(const ValueKey('console-pulse-line1'))).data, 'Day done');
      expect(t.widget<Text>(find.byKey(const ValueKey('console-pulse-line2'))).data, 'Next: Deep work at 08:00');
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 31));
    });

    testWidgets('before 08:00 the lines say the day has not started', (t) async {
      await pump(t, _nairobi(6, 30));
      expect(t.widget<Text>(find.byKey(const ValueKey('console-pulse-line1'))).data, 'Before the day starts');
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 31));
    });

    testWidgets('all three faces draw the same height, so the card does not jump when you double-tap', (t) async {
      await pump(t, _nairobi(10, 0));
      double faceHeight() => t.getSize(find.byType(ConsoleFaceLayout)).height;
      final progress = faceHeight();
      await cycle(t);
      expect(t.widget<Text>(find.byKey(const ValueKey('console-pill'))).data, 'Console · Player');
      final player = faceHeight();
      await cycle(t);
      expect(t.widget<Text>(find.byKey(const ValueKey('console-pill'))).data, 'Console · Recorder');
      final recorder = faceHeight();
      expect(player, progress);
      expect(recorder, progress);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 31));
    });

    testWidgets('the recorder face shows its state on line 1 and where it saves on line 2', (t) async {
      await pump(t, _nairobi(10, 0));
      await cycle(t);
      await cycle(t);
      expect(t.widget<Text>(find.byKey(const ValueKey('console-rec-clock'))).data, 'Ready to record');
      expect(t.widget<Text>(find.byKey(const ValueKey('console-rec-status'))).data, startsWith('Saves to hold · Audio/recordings'));
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 31));
    });
  });
}
