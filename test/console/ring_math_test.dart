
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/console/ring_math.dart';

void main() {
  const c = Offset(100, 100);

  test('the ring starts at 12 o\'clock and runs clockwise', () {
    expect(angleFraction(const Offset(100, 0), c), closeTo(0.0, 1e-9));
    expect(angleFraction(const Offset(200, 100), c), closeTo(0.25, 1e-9)); // 3 o'clock
    expect(angleFraction(const Offset(100, 200), c), closeTo(0.5, 1e-9)); // 6 o'clock
    expect(angleFraction(const Offset(0, 100), c), closeTo(0.75, 1e-9)); // 9 o'clock
    expect(angleFraction(const Offset(99, 0), c), greaterThan(0.99));
  });

  test('a drag across 12 o\'clock lands on the nearest end, not the opposite one', () {
    expect(unwrapDrag(0.97, 0.02), 1.0);
    expect(unwrapDrag(0.03, 0.98), 0.0);
    expect(unwrapDrag(0.40, 0.45), 0.45);
    expect(unwrapDrag(0.10, 0.55), 0.55, reason: 'a 0.45 jump is a real move, not a wrap');
  });

  test('a ring fraction maps proportionally onto the track and back', () {
    const total = Duration(minutes: 40);
    expect(positionForFraction(0.5, total), const Duration(minutes: 20));
    expect(positionForFraction(1.4, total), total, reason: 'clamped to the end');
    expect(positionForFraction(-0.2, total), Duration.zero);
    expect(fractionOfPosition(const Duration(minutes: 10), total), 0.25);
    expect(fractionOfPosition(const Duration(minutes: 1), Duration.zero), 0);
  });

  test('the recording clock makes one lap per ten minutes and counts them', () {
    expect(lapCount(const Duration(minutes: 9, seconds: 59)), 0);
    expect(lapCount(const Duration(minutes: 10)), 1);
    expect(lapCount(const Duration(minutes: 25)), 2);
    expect(lapFraction(const Duration(minutes: 5)), 0.5);
    expect(lapFraction(const Duration(minutes: 12)), closeTo(0.2, 1e-9));
  });

  test('clock text', () {
    expect(clock(const Duration(minutes: 12, seconds: 40)), '12:40');
    expect(clock(const Duration(seconds: 5)), '00:05');
    expect(clock(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
    expect(clock(const Duration(seconds: -4)), '00:00');
  });
}
