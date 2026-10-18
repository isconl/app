import 'dart:convert';

import 'package:flutter/services.dart';

import '../api/client.dart';
import '../data/db.dart';
import '../data/outbox.dart';
import '../util/fmt.dart' as fmt;

/// BI26101528: one-tap clock for the work-hours book (ledger BL26101409).
///
/// The quick-settings tile and the home-screen widget (Kotlin, `ClockStore`) queue each tap at once with the device
/// time and never touch the network. This file is the app's half: the same state machine, the hand-over of those
/// queued taps into the outbox in order, the cached journal head they draw from, and the refusal path when ledger
/// rejects a sequence rule.

enum ClockState { out, working, onBreak }

enum ClockAction { clockIn, startBreak, endBreak, clockOut }

extension ClockActionWords on ClockAction {
  /// The word ledger takes.
  String get wire => switch (this) {
        ClockAction.clockIn => 'in',
        ClockAction.startBreak => 'break',
        ClockAction.endBreak => 'back',
        ClockAction.clockOut => 'out',
      };

  String get label => switch (this) {
        ClockAction.clockIn => 'Clock in',
        ClockAction.startBreak => 'Break',
        ClockAction.endBreak => 'Back',
        ClockAction.clockOut => 'Clock out',
      };

  static ClockAction? fromWire(String? w) => switch (w) {
        'in' => ClockAction.clockIn,
        'break' => ClockAction.startBreak,
        'back' => ClockAction.endBreak,
        'out' => ClockAction.clockOut,
        _ => null,
      };
}

/// The action a tap on the tile does: Clock in, then Break, then Back, and so on. A long-press is always [ClockAction.clockOut].
ClockAction nextClockAction(ClockState s) => switch (s) {
      ClockState.out => ClockAction.clockIn,
      ClockState.working => ClockAction.startBreak,
      ClockState.onBreak => ClockAction.endBreak,
    };

/// The order the journal allows.
bool clockAllowed(ClockState s, ClockAction a) => switch (a) {
      ClockAction.clockIn => s == ClockState.out,
      ClockAction.startBreak => s == ClockState.working,
      ClockAction.endBreak => s == ClockState.onBreak,
      ClockAction.clockOut => s == ClockState.working || s == ClockState.onBreak,
    };

ClockState clockAfter(ClockAction a) => switch (a) {
      ClockAction.clockIn || ClockAction.endBreak => ClockState.working,
      ClockAction.startBreak => ClockState.onBreak,
      ClockAction.clockOut => ClockState.out,
    };

String clockStateWord(ClockState s) => switch (s) {
      ClockState.out => 'Clocked out',
      ClockState.working => 'Working',
      ClockState.onBreak => 'On break',
    };

/// The sentence for an entry the journal's order does not allow, naming the rule.
String clockRefusal(ClockState s, ClockAction a) => switch (a) {
      ClockAction.clockIn => "You are already clocked in, so there is no day to start.",
      ClockAction.startBreak => s == ClockState.onBreak ? 'You are already on a break.' : 'A break needs an open day: clock in first.',
      ClockAction.endBreak => 'There is no break to end.',
      ClockAction.clockOut => 'You are not clocked in, so there is nothing to clock out of.',
    };

ClockState? clockStateFromWord(String? w) => switch ((w ?? '').toLowerCase()) {
      'working' || 'in' || 'open' => ClockState.working,
      'break' || 'on_break' || 'onbreak' || 'paused' => ClockState.onBreak,
      'out' || 'closed' || 'clocked_out' => ClockState.out,
      _ => null,
    };

/// The journal head: where the day stands, and the net minutes worked as of [asOf].
class ClockHead {
  const ClockHead({this.state = ClockState.out, this.workedMinutes = 0, required this.asOf});
  final ClockState state;
  final int workedMinutes;
  final DateTime asOf;

  /// Net minutes, counting the running stretch while the state is working.
  int workedNow(DateTime now) =>
      state == ClockState.working ? workedMinutes + now.difference(asOf).inMinutes.clamp(0, 24 * 60) : workedMinutes;

  ClockHead afterTap(ClockAction a, DateTime at) {
    final worked = workedNow(at);
    final newDay = state == ClockState.out && (asOf.year != at.year || asOf.month != at.month || asOf.day != at.day);
    return ClockHead(state: clockAfter(a), workedMinutes: a == ClockAction.clockIn && newDay ? 0 : worked, asOf: at);
  }

  Map<String, dynamic> toJson() => {'state': state.name, 'worked': workedMinutes, 'asOf': asOf.millisecondsSinceEpoch};

  factory ClockHead.fromJson(dynamic v) {
    final m = fmt.m(v);
    return ClockHead(
      state: ClockState.values.firstWhere((s) => s.name == fmt.s(m['state']), orElse: () => ClockState.out),
      workedMinutes: fmt.i(m['worked']),
      asOf: DateTime.fromMillisecondsSinceEpoch(fmt.i(m['asOf'])),
    );
  }
}

/// `2026-10-16T09:30:00+03:00`: the device clock with its offset, as the entry's time.
String clockStamp(DateTime t) {
  final off = t.timeZoneOffset;
  final m = off.inMinutes.abs();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year.toString().padLeft(4, '0')}-${two(t.month)}-${two(t.day)}T${two(t.hour)}:${two(t.minute)}:${two(t.second)}'
      '${off.isNegative ? '-' : '+'}${two(m ~/ 60)}:${two(m % 60)}';
}

/// The tile and widget's side of the channel. A phone with no tile (web, desktop, tests) answers nothing.
class ClockBridge {
  ClockBridge({MethodChannel? channel}) : _c = channel ?? const MethodChannel('isconl/clock');
  final MethodChannel _c;

  /// The taps queued natively since the last call, oldest first; the native list is emptied.
  Future<List<Map<String, dynamic>>> drain() async {
    try {
      final raw = await _c.invokeMethod<String>('drain');
      if (raw == null || raw.isEmpty) return const [];
      return fmt.lm(jsonDecode(raw));
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  Future<void> publish(ClockHead head, {required bool locked}) async {
    try {
      await _c.invokeMethod('publish', {'json': jsonEncode({...head.toJson(), 'locked': locked})});
    } on MissingPluginException {
      // No tile on this platform.
    } on PlatformException {
      // The surfaces just stay as they were.
    }
  }
}

typedef RefusalNotifier = Future<void> Function(String rule);

class ClockService {
  ClockService({
    required this.db,
    required this.api,
    required this.outbox,
    ClockBridge? bridge,
    this.notifyRefusal,
    DateTime Function()? now,
  })  : bridge = bridge ?? ClockBridge(),
        _now = now ?? DateTime.now;

  final AppDb db;
  final ApiClient Function() api;
  final OutboxService outbox;
  final ClockBridge bridge;
  final RefusalNotifier? notifyRefusal;
  final DateTime Function() _now;

  static const _headKey = 'clock.head.v1';
  static const _refusedKey = 'clock.refused.v1';
  static const entriesPath = '/api/ledger/time/entries';
  static const balancePath = '/api/ledger/time/balance?period=day';

  Future<ClockHead> head() async {
    try {
      final v = (await db.getSnapshot(_headKey))?.$1;
      if (v != null) return ClockHead.fromJson(v);
    } catch (_) {}
    return ClockHead(asOf: _now());
  }

  Future<void> _saveHead(ClockHead h) async {
    try {
      await db.putSnapshot(_headKey, h.toJson());
    } catch (_) {}
  }

  /// Queues one entry through the outbox, in order, with the device time, and moves the head. Null when it was
  /// queued; otherwise the sentence naming the rule it breaks (nothing is queued then).
  Future<String?> tap(ClockAction action, {DateTime? at}) async {
    final when = at ?? _now();
    final h = await head();
    if (!clockAllowed(h.state, action)) return clockRefusal(h.state, action);
    await outbox.enqueue(
      path: entriesPath,
      body: {'action': action.wire, 'at': clockStamp(when), 'tz': when.timeZoneName, 'source': 'app'},
      label: action.label,
      view: 'clock',
    );
    await _saveHead(h.afterTap(action, when));
    return null;
  }

  /// Takes over the taps the tile and widget queued, in order. A tap the head no longer allows is dropped (the
  /// journal order wins), and the count of those is returned second.
  Future<({int queued, int dropped})> drainNative() async {
    var queued = 0, dropped = 0;
    for (final t in await bridge.drain()) {
      final a = ClockActionWords.fromWire(fmt.s(t['action']));
      final at = DateTime.tryParse(fmt.s(t['at']));
      if (a == null || at == null) continue;
      final h = await head();
      if (!clockAllowed(h.state, a)) {
        dropped++;
        continue;
      }
      await outbox.enqueue(
        path: entriesPath,
        body: {'action': a.wire, 'at': fmt.s(t['at']), 'tz': fmt.s(t['tz']), 'source': 'app'},
        label: a.label,
        view: 'clock',
      );
      await _saveHead(h.afterTap(a, at));
      queued++;
    }
    return (queued: queued, dropped: dropped);
  }

  /// Gives the tile and widget the head and the lock flag.
  Future<void> publish({required bool locked}) async => bridge.publish(await head(), locked: locked);

  /// Asks ledger where the day stands and takes that as the head. Quiet when offline.
  Future<bool> resync() async {
    try {
      final res = fmt.m(await api().getJson(balancePath));
      final state = clockStateFromWord(fmt.s(res['state'] ?? res['status']));
      if (state == null) return false;
      final worked = fmt.i(res['workedMinutes'] ?? res['netMinutes'] ?? res['net']);
      await _saveHead(ClockHead(state: state, workedMinutes: worked, asOf: _now()));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// After the outbox has been drained: one notification naming the rule for each entry ledger refused that has not
  /// been announced, then a resync of the head. Returns how many were announced.
  Future<int> announceRefusals() async {
    var last = 0;
    try {
      last = fmt.i(fmt.m((await db.getSnapshot(_refusedKey))?.$1)['id']);
    } catch (_) {}
    var announced = 0;
    var newest = last;
    final history = await outbox.history();
    for (final row in history.reversed) {
      final id = fmt.i(row['id']);
      if (id <= last || fmt.s(row['view']) != 'clock' || fmt.s(row['status']) != 'failed') continue;
      final rule = fmt.s(row['error']).isEmpty ? 'The work-hours book refused that entry.' : fmt.s(row['error']);
      await notifyRefusal?.call(rule);
      announced++;
      if (id > newest) newest = id;
    }
    if (newest > last) {
      try {
        await db.putSnapshot(_refusedKey, {'id': newest});
      } catch (_) {}
    }
    if (announced > 0) await resync();
    return announced;
  }

  /// The whole pass the app runs when it comes to the front: take native taps, deliver, announce refusals, publish.
  Future<void> pass({required bool locked}) async {
    await drainNative();
    try {
      await outbox.drain();
    } catch (_) {}
    await announceRefusals();
    await publish(locked: locked);
  }
}
