import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/util/equicycle.dart';

// The same positions hub web's tests assert, from a fixed table.
final _years = [
  EqYear(year: 2025, start: DateTime(2025, 6, 22), length: 364),
  EqYear(year: 2026, start: DateTime(2026, 6, 21), length: 364),
  EqYear(year: 2028, start: DateTime(2028, 6, 18), length: 371),
];

void main() {
  test('2026-10-01 is 26·C04·D19', () {
    final p = eq2Position(DateTime(2026, 10, 1), _years)!;
    expect(p.cycleKey, 'eq2:26-C04');
    expect(p.day, 19);
    expect(p.stillweek, false);
    expect(p.sprint, 8);
  });

  test('2026-06-20 is 25·C13·D28, the last day of the year before', () {
    final p = eq2Position(DateTime(2026, 6, 20), _years)!;
    expect(p.cycleKey, 'eq2:25-C13');
    expect(p.day, 28);
    expect(p.stillweek, false);
  });

  test('2026-10-11 is 26·C05·D01', () {
    final p = eq2Position(DateTime(2026, 10, 11), _years)!;
    expect(p.cycleKey, 'eq2:26-C05');
    expect(p.day, 1);
  });

  test('2029-06-20 is Stillweek day 4 of year 28, in a 371-day year', () {
    final p = eq2Position(DateTime(2029, 6, 20), _years)!;
    expect(p.year, 2028);
    expect(p.length, 371);
    expect(p.stillweek, true);
    expect(p.stillweekDay, 4);
    expect(p.cycleKey, 'eq2:28-C13');
  });

  test('cycle keys are zero padded', () {
    expect(eq2CycleKey(2026, 4), 'eq2:26-C04');
    expect(eq2CycleKey(2105, 13), 'eq2:05-C13');
  });

  test('a date no table covers is null, not a guess', () {
    expect(eq2Position(DateTime(2035, 1, 1), _years), isNull);
    expect(EquicycleYears.forTesting().positionFor(DateTime(2026, 10, 1)), isNull);
  });

  test('a year table parses from the API shape', () {
    final y = EqYear.fromJson({'year': 2026, 'start': '2026-06-21', 'end': '2027-06-19', 'length': 364, 'stillweek': null})!;
    expect(y.start, DateTime(2026, 6, 21));
    expect(y.length, 364);
    expect(EqYear.fromJson({'start': 'junk'}), isNull);
  });
}
