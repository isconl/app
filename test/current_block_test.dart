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
    test('reads now.current.id first', () {
      final day = {
        'date': '2026-10-15',
        'blocks': thursday(),
        'now': {'current': {'id': 'BLK-HOME-THU'}},
      };
      expect(currentBlockId(day, nairobi(10, 0)), 'BLK-HOME-THU');
    });

    test('then the block flagged current', () {
      final b = thursday()..[2] = blk('BLK-HOME-THU', 'Home', '18:00', '21:00', current: true);
      expect(currentBlockId({'date': '2026-10-15', 'blocks': b}, nairobi(10, 0)), 'BLK-HOME-THU');
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
          blk('BLK-PROT-THU', 'Protected', '00:00', '00:01'),
          blk('BLK-HOME-THU', 'Home', '00:00', '23:59', current: true),
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
