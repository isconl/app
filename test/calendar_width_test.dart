import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/api/client.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/ui/views/calendar.dart';
import 'package:isconl/ui/widgets/common.dart';
import 'package:isconl/util/equicycle.dart';
import 'support/test_services.dart';

class _Api extends ApiClient {
  _Api() : super(baseUrl: 'http://test', token: 'test');
  @override
  Future<dynamic> getJson(String path, {bool cold = false, bool stored = true}) async => <String, dynamic>{};
}

void main() {
  testWidgets('iSignal cards span the width with the 14 px page gutter, like the other views', (t) async {
    t.view.physicalSize = const Size(400, 860);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final today = DateTime.now();
    EquicycleYears.instance.seedForTest([EqYear(year: today.year, start: DateTime(today.year, today.month, today.day).subtract(const Duration(days: 20)), length: 364)]);
    final services = (await t.runAsync(() => buildTestServices(_Api(), online: false)))!;
    services.store.calendar.value = {'events': <dynamic>[]};
    await t.pumpWidget(AppScope(services: services, child: const MaterialApp(home: Scaffold(body: CalendarView()))));
    for (var i = 0; i < 3; i++) { await t.pump(); await t.runAsync(() => Future.delayed(const Duration(milliseconds: 60))); }
    await t.pump();
    // BI26111592: the calendar card spans the width like every other view: the page gutter (14 px) once, not twice.
    final panels = find.byType(Panel).evaluate().toList();
    expect(panels, isNotEmpty);
    for (final e in panels) {
      final r = t.getRect(find.byWidget(e.widget));
      expect(r.left, 14.0);
      expect(r.right, 400.0 - 14.0);
    }
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });
}
