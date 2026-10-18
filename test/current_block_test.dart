import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/ui/views/hub.dart';
import 'package:isconl/ui/views/spaced_review_view.dart' show ReviewCard;
import 'package:isconl/ui/widgets/block_card.dart';
import 'package:isconl/ui/widgets/vitals_card.dart';
import 'package:isconl/util/current_block.dart';

import 'support/test_services.dart';

/// The 15 Oct shape from pulse's GET /blocks: block names and times only.
Map<String, dynamic> blk(String id, String name, String start, String end, {bool current = false}) =>
    {'id': id, 'name': name, 'startClock': start, 'endClock': end, 'placeable': true, 'slots': 3, 'tasks': [], if (current) 'current': true};

List<Map<String, dynamic>> thursday() => [
      blk('BLK-PROT-THU', 'Protected', '05:00', '06:00'),
      blk('BLK-LEARN-THU', 'Learning', '06:00', '09:00'),
      blk('BLK-HOME-THU', 'Home', '18:00', '21:00'),
      blk('BLK-REST-THU', 'Rest', '21:00', '05:00'),
    ];

// Nairobi is UTC+3, so these are built in UTC.
DateTime nairobi(int h, int m) => DateTime.utc(2026, 10, 15, h - 3, m);

void main() {
  group('BI26101517: currentBlockId', () {
    test('the clock wins over a stale now.current.id (BI26101805)', () {
      final day = {
        'date': '2026-10-15',
        'blocks': thursday(),
        'now': {'current': {'id': 'BLK-PROT-THU'}}, // what was current when the snapshot was fetched
      };
      expect(currentBlockId(day, nairobi(5, 59)), 'BLK-PROT-THU');
      expect(currentBlockId(day, nairobi(6, 0)), 'BLK-LEARN-THU', reason: 'at 06:00 the next block, with no new fetch');
      expect(currentBlockId(day, nairobi(10, 0)), isNull, reason: 'between blocks, never the stale pick');
    });

    test('a flag marked current also loses to the clock (BI26101805)', () {
      final b = thursday()..[0] = blk('BLK-PROT-THU', 'Protected', '05:00', '06:00', current: true);
      expect(currentBlockId({'date': '2026-10-15', 'blocks': b}, nairobi(18, 30)), 'BLK-HOME-THU');
    });

    test('the server pick is used only when no block has usable times', () {
      final untimed = [
        {'id': 'A', 'name': 'A'},
        {'id': 'B', 'name': 'B'},
      ];
      expect(currentBlockId({'date': '2026-10-15', 'blocks': untimed, 'now': {'current': {'id': 'B'}}}, nairobi(10, 0)), 'B');
      final flagged = [
        {'id': 'A', 'name': 'A'},
        {'id': 'B', 'name': 'B', 'current': true},
      ];
      expect(currentBlockId({'date': '2026-10-15', 'blocks': flagged}, nairobi(10, 0)), 'B');
    });

    test('a phone set to UTC+0 still gets the Nairobi block (BI26101805)', () {
      final day = {'date': '2026-10-15', 'blocks': thursday()};
      // 06:30 UTC on the phone is 09:30 in Nairobi (between blocks); 03:30 UTC is 06:30 in Nairobi (Learning)
      expect(currentBlockId(day, DateTime.utc(2026, 10, 15, 6, 30)), isNull);
      expect(currentBlockId(day, DateTime.utc(2026, 10, 15, 3, 30)), 'BLK-LEARN-THU');
    });

    test('then the block flagged current, when nothing has times (legacy shape)', () {
      final b = [
        {'id': 'X', 'name': 'X', 'current': true},
      ];
      expect(currentBlockId({'date': '2026-10-15', 'blocks': b}, nairobi(10, 0)), 'X');
    });

    test('then the clock, in Nairobi time', () {
      final day = {'date': '2026-10-15', 'blocks': thursday()};
      expect(currentBlockId(day, nairobi(20, 36)), 'BLK-HOME-THU');
      expect(currentBlockId(day, nairobi(5, 30)), 'BLK-PROT-THU');
    });

    test('Rest wraps past midnight', () {
      final day = {'date': '2026-10-15', 'blocks': thursday()};
      expect(currentBlockId(day, nairobi(23, 0)), 'BLK-REST-THU');
      expect(currentBlockId(day, nairobi(2, 0)), 'BLK-REST-THU');
    });

    test('between blocks gives null, never the first block', () {
      final day = {'date': '2026-10-15', 'blocks': thursday()};
      expect(currentBlockId(day, nairobi(12, 0)), isNull);
    });

    test('a plan from another day is stale and gives null', () {
      final day = {'date': '2026-10-14', 'blocks': thursday(), 'now': {'current': {'id': 'BLK-HOME-THU'}}};
      expect(dayIsStale(day, nairobi(20, 36)), isTrue);
      expect(currentBlockId(day, nairobi(20, 36)), isNull);
    });

    test('the next block after now, wrapping to the first', () {
      final b = thursday();
      expect(nextBlockIndex(b, nairobi(12, 0)), 2);
      expect(nextBlockIndex(b, nairobi(21, 30)), 0);
    });
  });

  group('BI26101517: the Hub', () {
    Future<AppServices> pumpHub(WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 6000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final services = (await tester.runAsync(() => buildTestServices(ScriptedApi({}))))!;
      services.store.state.value = {
        'time': {'eqShort': '2026-5', 'sprintShort': 'W41', 'yearPct': 78},
        'tasks': [],
        'services': {},
      };
      // The day snapshot is dated by the real clock, so the test is stable whenever it runs.
      final nowNairobi = DateTime.now();
      services.store.day.value = {
        'date': nairobiDate(nowNairobi),
        'blocks': [
          blk('BLK-HOME-THU', 'Home', '00:00', '23:59', current: true),
          blk('BLK-PROT-THU', 'Protected', '00:00', '00:01'),
        ],
        'now': {'current': {'id': 'BLK-HOME-THU'}},
      };
      await tester.pumpWidget(AppScope(services: services, child: const MaterialApp(home: Scaffold(body: HubView()))));
      await tester.pump();
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 120)));
      await tester.pump();
      return services;
    }

    Future<void> teardown(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
      await tester.pump(const Duration(seconds: 2));
    }

    testWidgets('the now card shows Home, the real current block, not Protected', (tester) async {
      await pumpHub(tester);
      expect(find.text('NOW · Home'), findsOneWidget);
      expect(find.text('NOW · Protected'), findsNothing);
      await teardown(tester);
    });

    testWidgets('order: the block card, then the Review strip, then Vitals', (tester) async {
      await pumpHub(tester);
      final block = tester.getTopLeft(find.byType(BlockCard)).dy;
      final review = tester.getTopLeft(find.byType(ReviewCard)).dy;
      final vitals = tester.getTopLeft(find.byType(VitalsCard)).dy;
      expect(block, lessThanOrEqualTo(review));
      expect(review, lessThanOrEqualTo(vitals));
      await teardown(tester);
    });
  });
}
