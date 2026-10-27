import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/console/console_mode.dart';

import 'fakes.dart';

void main() {
  test('modes cycle Progress, Player, Recorder and back', () {
    expect(ConsoleMode.progress.next, ConsoleMode.player);
    expect(ConsoleMode.player.next, ConsoleMode.recorder);
    expect(ConsoleMode.recorder.next, ConsoleMode.progress);
    expect(ConsoleMode.progress.pillSuffix, isNull);
    expect(ConsoleMode.player.pillSuffix, 'Player');
    expect(ConsoleMode.recorder.pillSuffix, 'Recorder');
  });

  test('two quick taps fire once, and the count starts over', () {
    final d = DoubleTapDetector();
    final t0 = DateTime(2026, 10, 3, 9);
    expect(d.tap(t0), isFalse, reason: 'one tap does not fire');
    expect(d.tap(t0.add(const Duration(milliseconds: 200))), isTrue);
    expect(d.tap(t0.add(const Duration(milliseconds: 300))), isFalse, reason: 'a third tap starts a new run');
    expect(d.tap(t0.add(const Duration(milliseconds: 450))), isTrue);
  });

  test('a pause longer than the gap breaks the run', () {
    final d = DoubleTapDetector();
    final t0 = DateTime(2026, 10, 3, 9);
    expect(d.tap(t0), isFalse);
    expect(d.tap(t0.add(const Duration(milliseconds: 400))), isFalse, reason: 'too slow to be the second');
    expect(d.tap(t0.add(const Duration(milliseconds: 600))), isTrue);
  });

  test('the last mode is remembered and an unknown value falls back to Progress', () async {
    final kv = MemoryKv();
    final a = ConsoleModeController(kv);
    await a.restore();
    expect(a.mode, ConsoleMode.progress);
    final seen = <ConsoleMode>[];
    a.addListener(seen.add);
    await a.cycle();
    await a.cycle();
    expect(seen, [ConsoleMode.player, ConsoleMode.recorder]);

    final b = ConsoleModeController(kv);
    await b.restore();
    expect(b.mode, ConsoleMode.recorder);

    kv.data['console.mode'] = 'hologram';
    final c = ConsoleModeController(kv);
    await c.restore();
    expect(c.mode, ConsoleMode.progress);
  });
}
