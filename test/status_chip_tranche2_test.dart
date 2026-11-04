import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/api/client.dart';
import 'package:isconl/ui/status_chip.dart';
import 'package:isconl/util/equicycle.dart';

import 'support/test_services.dart';

class _Api extends ApiClient {
  _Api() : super(baseUrl: 'http://test', token: 'test');
}

final _years = [
  EqYear(year: 2025, start: DateTime(2025, 6, 22), length: 364),
  EqYear(year: 2026, start: DateTime(2026, 6, 21), length: 364),
  EqYear(year: 2028, start: DateTime(2028, 6, 18), length: 371),
];

Map<String, dynamic> ops(List<bool> running) => {
      'groups': {
        'isconl': [for (final (i, r) in running.indexed) {'service': 's$i', 'running': r, 'exists': true}],
      },
    };

void main() {
  group('BI26100125: the cycle chip (Command)', () {
    test('cycle word in lower case and the day of 28', () {
      expect(cycleChipText(eq2Position(DateTime(2026, 10, 1), _years)), 'reap · 19/28');
      expect(cycleChipText(eq2Position(DateTime(2026, 6, 21), _years)), 'plant · 1/28');
      expect(cycleChipText(eq2Position(DateTime(2026, 6, 20), _years)), 'audit · 28/28');
    });

    test('Stillweek shows its day; no table shows no chip', () {
      expect(cycleChipText(eq2Position(DateTime(2029, 6, 20), _years)), 'stillweek · 4');
      expect(cycleChipText(eq2Position(DateTime(2035, 1, 1), _years)), isNull);
    });

    testWidgets('the source reads the cached table, makes no call, and opens Compass', (t) async {
      final titles = <String>[];
      final src = CycleChipSource((c, title, page) => titles.add(title),
          years: EquicycleYears.forTesting(_years), clock: () => DateTime(2026, 10, 1, 9));
      late StatusChip chip;
      await t.pumpWidget(MaterialApp(home: Builder(builder: (c) {
        chip = src.current(c)!;
        return const SizedBox();
      })));
      expect(chip.text, 'reap · 19/28');
      await t.pumpWidget(MaterialApp(home: Builder(builder: (c) {
        chip.onTap(c);
        return const SizedBox();
      })));
      expect(titles, ['Compass']);
    });

    testWidgets('no table yet means no cycle chip', (t) async {
      final src = CycleChipSource((c, title, page) {}, years: EquicycleYears.forTesting(), clock: () => DateTime(2026, 10, 1));
      StatusChip? chip = StatusChip('x', (_) {});
      await t.pumpWidget(MaterialApp(home: Builder(builder: (c) {
        chip = src.current(c);
        return const SizedBox();
      })));
      expect(chip, isNull);
    });
  });

  group('BI26100125: the ops chip (Systems > Ops)', () {
    test('vm ok when every engine is up, vm N down otherwise, nothing before a status', () {
      expect(opsChipText(ops([true, true, true])), 'vm ok');
      expect(opsChipText(ops([true, false, false])), 'vm 2 down');
      expect(opsChipText(null), isNull);
      expect(opsChipText({'groups': {}}), isNull);
    });

    testWidgets('the source reads the cached ops snapshot and opens Ops', (t) async {
      final services = (await t.runAsync(() => buildTestServices(_Api(), online: false)))!;
      final titles = <String>[];
      final src = OpsChipSource(services, (c, title, page) => titles.add(title));
      StatusChip? chip;
      Future<void> pumpWith() => t.pumpWidget(MaterialApp(home: Builder(builder: (c) {
            chip = src.current(c);
            return const SizedBox();
          })));
      await pumpWith();
      expect(chip, isNull); // nothing cached yet: no call, no chip
      services.store.opsStatus.value = ops([true, false]);
      await pumpWith();
      expect(chip!.text, 'vm 1 down');
      await t.pumpWidget(MaterialApp(home: Builder(builder: (c) {
        chip!.onTap(c);
        return const SizedBox();
      })));
      expect(titles, ['Ops']);
    });
  });
}
