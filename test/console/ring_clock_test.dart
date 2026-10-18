import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/ui/widgets/context_ring_card.dart';

import 'test_services.dart';

/// BI26101805: the console ring follows the live Nairobi clock. It used to recalculate only when the day snapshot
/// changed, and read the phone's own timezone.
void main() {
  setUpAll(initSqfliteForTests);

  Map<String, dynamic> day() => {
        'blocks': [
          {'id': 'A', 'name': 'Alpha', 'start': 9 * 60, 'end': 10 * 60},
          {'id': 'B', 'name': 'Beta', 'start': 10 * 60, 'end': 11 * 60},
        ],
      };

  // Nairobi is UTC+3. A phone set to UTC reports the UTC wall clock, which is what these return.
  DateTime nairobiAt(int h, int m) => DateTime.utc(2026, 10, 18, h - 3, m);

  Future<void> pump(WidgetTester tester, DateTime Function() clock) async {
    final services = (await tester.runAsync(() => buildTestServices()))!;
    services.store.dayBlock.value = day();
    await tester.pumpWidget(AppScope(
      services: services,
      child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ContextRingCard(clock: clock)))),
    ));
    await tester.pump();
  }

  testWidgets('at 09:59 Alpha is current; at 10:00 Beta, with no new fetch, once the timer runs', (tester) async {
    var now = nairobiAt(9, 59);
    await pump(tester, () => now);
    expect(find.text('ALPHA'), findsOneWidget);
    expect(find.text('BETA'), findsNothing);

    now = nairobiAt(10, 0);
    await tester.pump(const Duration(seconds: 31)); // the ring's own 30-second tick
    expect(find.text('BETA'), findsOneWidget);
    expect(find.text('ALPHA'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a phone on UTC+0 still shows the Nairobi block', (tester) async {
    // 06:30 UTC is 09:30 in Nairobi: Alpha. Read as the phone's own clock it would be 06:30, no block at all.
    await pump(tester, () => nairobiAt(9, 30));
    expect(find.text('ALPHA'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the timer stops when the card goes away', (tester) async {
    await pump(tester, () => nairobiAt(9, 30));
    await tester.pumpWidget(const SizedBox());
    // a periodic timer left running would fail the test binding's pending-timer check
    await tester.pump(const Duration(seconds: 61));
  });
}
