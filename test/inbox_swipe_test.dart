import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/ui/views/inbox_swipe.dart';
import 'package:isconl/util/snooze.dart';

void main() {
  group('snooze choices', () {
    test('later today is three hours on, or 17:00 when that is sooner', () {
      expect(snoozeChoices(DateTime(2026, 10, 3, 9)).first.until, DateTime(2026, 10, 3, 12));
      expect(snoozeChoices(DateTime(2026, 10, 3, 15)).first.until, DateTime(2026, 10, 3, 17));
      expect(snoozeChoices(DateTime(2026, 10, 3, 18)).first.until, DateTime(2026, 10, 3, 21));
    });

    test('tomorrow morning is 09:00 and next week is the coming Monday 09:00', () {
      final sat = snoozeChoices(DateTime(2026, 10, 3, 9)); // 3 Oct 2026 is a Saturday
      expect(sat[1].until, DateTime(2026, 10, 4, 9));
      expect(sat[2].until, DateTime(2026, 10, 5, 9));
      final mon = snoozeChoices(DateTime(2026, 10, 5, 8)); // a Monday means next Monday
      expect(mon[2].until, DateTime(2026, 10, 12, 9));
    });
  });

  group('SnoozeStore', () {
    test('a snoozed thread is hidden until its time, then visible again', () async {
      final s = SnoozeStore.forTesting();
      final t0 = DateTime(2026, 10, 3, 9);
      await s.snooze('p1', DateTime(2026, 10, 3, 12), null);
      expect(s.isSnoozed('p1', t0), true);
      expect(s.isSnoozed('p1', DateTime(2026, 10, 3, 11, 59)), true);
      expect(s.isSnoozed('p1', DateTime(2026, 10, 3, 12)), false);
      expect(s.isSnoozed('other', t0), false);
      await s.unsnooze('p1', null);
      expect(s.isSnoozed('p1', t0), false);
    });
  });

  Widget host({required List<String> log, SnoozeChoice? pick}) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Column(children: [
            SwipeThread(
              key: const ValueKey('t1'),
              onDone: () => log.add('done'),
              chooseSnooze: () async => pick,
              onSnooze: (c) => log.add('snooze ${c.label}'),
              child: const SizedBox(height: 60, width: double.infinity, child: Text('thread one')),
            ),
            TextButton(onPressed: () => showUndoBar(context, 'Marked done', () => log.add('undo')), child: const Text('bar')),
          ]),
        ),
      ),
    );
  }

  testWidgets('swipe right marks done', (t) async {
    final log = <String>[];
    await t.pumpWidget(host(log: log));
    await t.drag(find.text('thread one'), const Offset(500, 0));
    await t.pumpAndSettle();
    expect(log, ['done']);
    expect(find.text('thread one'), findsNothing);
  });

  testWidgets('swipe left snoozes with the chosen option', (t) async {
    final log = <String>[];
    await t.pumpWidget(host(log: log, pick: SnoozeChoice('Tomorrow morning', DateTime(2026, 10, 4, 9))));
    await t.drag(find.text('thread one'), const Offset(-500, 0));
    await t.pumpAndSettle();
    expect(log, ['snooze Tomorrow morning']);
    expect(find.text('thread one'), findsNothing);
  });

  testWidgets('backing out of the snooze sheet springs the row back', (t) async {
    final log = <String>[];
    await t.pumpWidget(host(log: log));
    await t.drag(find.text('thread one'), const Offset(-500, 0));
    await t.pumpAndSettle();
    expect(log, isEmpty);
    expect(find.text('thread one'), findsOneWidget);
  });

  testWidgets('a short drag does nothing (35% threshold)', (t) async {
    final log = <String>[];
    await t.pumpWidget(host(log: log));
    await t.drag(find.text('thread one'), const Offset(60, 0));
    await t.pumpAndSettle();
    expect(log, isEmpty);
    expect(find.text('thread one'), findsOneWidget);
  });

  testWidgets('the undo bar runs the undo and goes after 5 seconds', (t) async {
    final log = <String>[];
    await t.pumpWidget(host(log: log));
    await t.tap(find.text('bar'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 750));
    expect(find.text('Marked done'), findsOneWidget);
    await t.tap(find.text('Undo'));
    await t.pumpAndSettle();
    expect(log, ['undo']);

    await t.tap(find.text('bar'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 750));
    await t.pump(const Duration(seconds: 6));
    await t.pump(const Duration(seconds: 1));
    await t.pumpAndSettle();
    expect(find.text('Marked done'), findsNothing);
  });
}
