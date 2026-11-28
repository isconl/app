import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/services/clock.dart';

import 'support/test_services.dart';

class FakeBridge extends ClockBridge {
  FakeBridge() : super(channel: const MethodChannel('test/none'));
  final List<Map<String, dynamic>> queued = [];
  ClockHead? published;
  bool? lockedPublished;

  @override
  Future<List<Map<String, dynamic>>> drain() async {
    final out = List<Map<String, dynamic>>.of(queued);
    queued.clear();
    return out;
  }

  @override
  Future<void> publish(ClockHead head, {required bool locked}) async {
    published = head;
    lockedPublished = locked;
  }
}

Map<String, dynamic> tap(String action, String at) => {'action': action, 'at': at, 'tz': 'Africa/Nairobi'};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final t0 = DateTime(2026, 10, 16, 9, 0);

  group('BI26101528: the state machine', () {
    test('each state names its next action, the long-press is always clock out', () {
      expect(nextClockAction(ClockState.out), ClockAction.clockIn);
      expect(nextClockAction(ClockState.working), ClockAction.startBreak);
      expect(nextClockAction(ClockState.onBreak), ClockAction.endBreak);
      expect(ClockAction.clockIn.label, 'Clock in');
      expect(ClockAction.startBreak.label, 'Break');
      expect(ClockAction.endBreak.label, 'Back');
      expect(ClockAction.clockOut.label, 'Clock out');
      expect(ClockAction.endBreak.wire, 'back');
    });

    test('the journal order: a break needs an open day, back needs a break, in needs out', () {
      expect(clockAllowed(ClockState.out, ClockAction.clockIn), isTrue);
      expect(clockAllowed(ClockState.out, ClockAction.startBreak), isFalse);
      expect(clockAllowed(ClockState.out, ClockAction.clockOut), isFalse);
      expect(clockAllowed(ClockState.working, ClockAction.clockIn), isFalse);
      expect(clockAllowed(ClockState.working, ClockAction.startBreak), isTrue);
      expect(clockAllowed(ClockState.working, ClockAction.endBreak), isFalse);
      expect(clockAllowed(ClockState.working, ClockAction.clockOut), isTrue);
      expect(clockAllowed(ClockState.onBreak, ClockAction.endBreak), isTrue);
      expect(clockAllowed(ClockState.onBreak, ClockAction.clockOut), isTrue);
      expect(clockAfter(ClockAction.endBreak), ClockState.working);
      expect(clockAfter(ClockAction.startBreak), ClockState.onBreak);
    });

    test('net minutes count the running stretch only while working', () {
      var h = ClockHead(asOf: t0);
      h = h.afterTap(ClockAction.clockIn, t0);
      expect(h.workedNow(t0.add(const Duration(minutes: 90))), 90);
      h = h.afterTap(ClockAction.startBreak, t0.add(const Duration(minutes: 90)));
      expect(h.workedNow(t0.add(const Duration(minutes: 200))), 90); // the break does not count
      h = h.afterTap(ClockAction.endBreak, t0.add(const Duration(minutes: 200)));
      expect(h.workedNow(t0.add(const Duration(minutes: 230))), 120);
      h = h.afterTap(ClockAction.clockOut, t0.add(const Duration(minutes: 230)));
      expect(h.workedNow(t0.add(const Duration(minutes: 999))), 120);
    });

    test('the first clock in of a new day starts from zero', () {
      final yesterdayOut = ClockHead(state: ClockState.out, workedMinutes: 480, asOf: DateTime(2026, 10, 15, 17, 0));
      expect(yesterdayOut.afterTap(ClockAction.clockIn, t0).workedMinutes, 0);
      final sameDay = ClockHead(state: ClockState.out, workedMinutes: 240, asOf: DateTime(2026, 10, 16, 8, 0));
      expect(sameDay.afterTap(ClockAction.clockIn, t0).workedMinutes, 240);
    });

    test('the entry time carries the device offset', () {
      final s = clockStamp(DateTime(2026, 10, 16, 9, 5, 7));
      expect(s, matches(RegExp(r'^2026-10-16T09:05:07[+-]\d{2}:\d{2}$')));
    });

    test('a refusal names the rule', () {
      expect(clockRefusal(ClockState.out, ClockAction.startBreak), contains('open day'));
      expect(clockRefusal(ClockState.working, ClockAction.endBreak), contains('no break'));
    });
  });

  group('BI26101528: the service', () {
    Future<(ClockService, FakeBridge, ScriptedApi, dynamic, List<String>)> make(
      Map<String, Object> answers, {
      DateTime? now,
    }) async {
      final api = ScriptedApi(answers);
      final services = await buildTestServices(api);
      final bridge = FakeBridge();
      final refused = <String>[];
      final clock = ClockService(
        db: services.db,
        api: () => api,
        outbox: services.outbox,
        bridge: bridge,
        notifyRefusal: (r) async => refused.add(r),
        now: () => now ?? t0,
      );
      return (clock, bridge, api, services, refused);
    }

    test('offline taps from the tile are replayed through the outbox in order, with their own times', () async {
      final (clock, bridge, _, services, _) = await make({});
      bridge.queued.addAll([
        tap('in', '2026-10-16T08:00:00+03:00'),
        tap('break', '2026-10-16T10:00:00+03:00'),
        tap('back', '2026-10-16T10:15:00+03:00'),
      ]);
      final r = await clock.drainNative();
      expect(r.queued, 3);
      expect(r.dropped, 0);
      final rows = (await services.db.pendingOutbox()).where((x) => x['view'] == 'clock').toList();
      expect(rows.map((x) => x['label']), ['Clock in', 'Break', 'Back']);
      expect((await clock.head()).state, ClockState.working);
    });

    test('a native tap the head no longer allows is dropped, not queued', () async {
      final (clock, bridge, _, services, _) = await make({});
      bridge.queued.addAll([tap('in', '2026-10-16T08:00:00+03:00'), tap('in', '2026-10-16T08:01:00+03:00')]);
      final r = await clock.drainNative();
      expect(r.queued, 1);
      expect(r.dropped, 1);
      expect((await services.db.pendingOutbox()).where((x) => x['view'] == 'clock'), hasLength(1));
    });

    test('a tap in the app that the journal order refuses is answered with the rule and queues nothing', () async {
      final (clock, _, _, services, _) = await make({});
      final msg = await clock.tap(ClockAction.startBreak);
      expect(msg, contains('open day'));
      expect((await services.db.pendingOutbox()).where((x) => x['view'] == 'clock'), isEmpty);
      expect(await clock.tap(ClockAction.clockIn), isNull);
      expect((await services.db.pendingOutbox()).where((x) => x['view'] == 'clock'), hasLength(1));
    });

    test('the entry body is action, device time, timezone and source app', () async {
      final (clock, _, _, services, _) = await make({});
      await clock.tap(ClockAction.clockIn);
      final row = (await services.db.pendingOutbox()).singleWhere((x) => x['view'] == 'clock');
      expect(row['path'], '/api/ledger/time/entries');
      expect(row['body'], allOf(contains('"action":"in"'), contains('"source":"app"'), contains('"at":"2026-10-16T09:00:00')));
    });

    test("a refusal from ledger becomes one notification naming its rule, then the head is resynced", () async {
      final (clock, _, api, services, refused) = await make({
        '/api/ledger/time/balance': {'state': 'out', 'workedMinutes': 0},
      });
      await clock.tap(ClockAction.clockIn);
      final row = (await services.db.pendingOutbox()).singleWhere((x) => x['view'] == 'clock');
      await services.db.markOutbox(row['id'] as int, 'failed', 'A break needs an open day.');
      expect(await clock.announceRefusals(), 1);
      expect(refused, ['A break needs an open day.']);
      expect(api.asked.last, startsWith('/api/ledger/time/balance'));
      expect((await clock.head()).state, ClockState.out); // resynced from ledger
      // Announced once, not again.
      expect(await clock.announceRefusals(), 0);
      expect(refused, hasLength(1));
    });

    test('publishing gives the tile the head and the lock flag', () async {
      final (clock, bridge, _, _, _) = await make({});
      await clock.tap(ClockAction.clockIn);
      await clock.publish(locked: true);
      expect(bridge.published!.state, ClockState.working);
      expect(bridge.lockedPublished, isTrue);
    });
  });
}
