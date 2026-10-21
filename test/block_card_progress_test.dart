import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/theme.dart';
import 'package:isconl/ui/widgets/block_card.dart';

import 'support/test_services.dart';

void main() {
  group('BI26092625: block progress', () {
    test('the fraction is how far through the block now is, and null outside it or on bad clocks', () {
      DateTime at(int h, int m) => DateTime(2026, 10, 1, h, m);
      expect(blockProgress('08:00', '12:00', at(10, 0)), 0.5);
      expect(blockProgress('08:00', '12:00', at(8, 0)), 0.0);
      expect(blockProgress('08:00', '12:00', at(11, 0)), 0.75);
      expect(blockProgress('08:00', '12:00', at(12, 0)), isNull);
      expect(blockProgress('08:00', '12:00', at(7, 59)), isNull);
      expect(blockProgress('', '12:00', at(10, 0)), isNull);
      expect(blockProgress('8am', '12:00', at(10, 0)), isNull);
      expect(blockProgress('12:00', '08:00', at(10, 0)), isNull);
      expect(blockProgress('25:00', '26:00', at(10, 0)), isNull);
    });
  });

  group('BI26092625: block card details', () {
    Future<void> pump(WidgetTester tester, List<Map<String, dynamic>> blocks, {String? currentId}) async {
      final services = (await tester.runAsync(() => buildTestServices(ScriptedApi({}))))!;
      await tester.pumpWidget(AppScope(
        services: services,
        child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: BlockCard(blocks: blocks, currentId: currentId)))),
      ));
      await tester.pump();
    }

    testWidgets('the now block shows a progress bar in the block tone when its time range contains now', (tester) async {
      await pump(tester, [
        {'id': 'creator', 'name': 'Creator', 'axis': 'creator', 'startClock': '00:00', 'endClock': '23:59', 'placeable': true, 'slots': 3, 'tasks': []},
      ], currentId: 'creator');
      final bar = tester.widget<LinearProgressIndicator>(find.byKey(const Key('block-progress')));
      expect(bar.valueColor?.value, kBlockTones['creator']);
      expect(bar.value, isNotNull);
    });

    testWidgets('a block with no time range draws no bar', (tester) async {
      await pump(tester, [
        {'id': 'flex', 'name': 'Flex', 'axis': 'flex', 'placeable': true, 'slots': 3, 'tasks': []},
      ], currentId: 'flex');
      expect(find.byKey(const Key('block-progress')), findsNothing);
    });

    testWidgets('a personal block shows its note and no items', (tester) async {
      await pump(tester, [
        {'id': 'rest', 'name': 'Rest', 'axis': 'rest', 'placeable': false, 'note': 'Phone down, lights low.', 'tasks': []},
      ], currentId: 'rest');
      expect(find.text('Phone down, lights low.'), findsOneWidget);
      expect(find.text('Nothing placed here yet.'), findsNothing);
    });

    testWidgets('an overdue item shows its meta in red', (tester) async {
      await pump(tester, [
        {
          'id': 'innovator',
          'name': 'Innovator',
          'axis': 'innovator',
          'placeable': true,
          'slots': 3,
          'tasks': [
            {'id': 'T1', 'title': 'Late thing', 'due': '2020-01-01', 'priority': 'high'},
          ],
        },
      ], currentId: 'innovator');
      final meta = tester.widget<Text>(find.textContaining('overdue'));
      expect(meta.style?.color, C.red);
    });
  });
}
