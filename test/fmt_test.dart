import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/services/updater.dart';
import 'package:isconl/util/fmt.dart' as fmt;

void main() {
  group('TSV sentinel handling', () {
    test("'-' is empty", () {
      expect(fmt.s('-'), '');
      expect(fmt.s(' - '), '');
      expect(fmt.s(null), '');
      expect(fmt.s('WSRU-42'), 'WSRU-42');
    });

    test('numbers parse defensively', () {
      expect(fmt.i('12'), 12);
      expect(fmt.i('x', 7), 7);
      expect(fmt.d('1,234.5'), 1234.5);
      expect(fmt.dOrNull('-'), null);
      expect(fmt.dOrNull(''), null);
      expect(fmt.dOrNull('88'), 88);
    });

    test('collections coerce safely', () {
      expect(fmt.lm('nope'), isEmpty);
      expect(fmt.lm([{'A': 1}, 'junk']).length, 1);
      expect(fmt.m(null), isEmpty);
    });
  });

  group('money (KES, arithmetic display only)', () {
    test('formats thousands', () {
      expect(fmt.money(12340), 'KES 12,340');
      expect(fmt.money(-500), '-KES 500');
      expect(fmt.money(null), 'KES 0');
    });
    test('compact form', () {
      expect(fmt.money(1500000, compact: true), 'KES 1.5M');
      expect(fmt.money(250000, compact: true), 'KES 250K');
    });
  });

  group('dates', () {
    test('daysUntil is calendar-based', () {
      final today = DateTime.now();
      expect(fmt.daysUntil(fmt.isoDate(today)), 0);
      expect(
          fmt.daysUntil(
              fmt.isoDate(today.add(const Duration(days: 3)))),
          3);
      expect(fmt.dueLabel(fmt.isoDate(today)), 'today');
    });
  });

  group('update version compare', () {
    test('orders semver', () {
      expect(UpdateService.compareVersions('0.0.2', '0.0.1') > 0, true);
      expect(UpdateService.compareVersions('0.1.0', '0.0.9') > 0, true);
      expect(UpdateService.compareVersions('1.0.0', '1.0.0'), 0);
      expect(UpdateService.compareVersions('0.0.1', '0.1.0') < 0, true);
    });
  });
}
