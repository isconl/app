import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/api/client.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/ui/views/calendar.dart';
import 'package:isconl/util/cycle_theme_bus.dart';
import 'package:isconl/util/equicycle.dart';

import 'support/test_services.dart';

/// BI26101811: the calendar reads the cycle theme from /api/cycle-theme, the store the web console reads, and reads it
/// again when compass changes it.
class _Api extends ApiClient {
  _Api() : super(baseUrl: 'http://test', token: 'test');
  String theme = 'Mend';
  final asked = <String>[];
  @override
  Future<dynamic> getJson(String path, {bool cold = false}) async {
    asked.add(path);
    if (path.startsWith('/api/cycle-theme')) return {'theme': theme};
    return <String, dynamic>{};
  }
}

void main() {
  testWidgets('a theme changed in compass shows in the calendar without a restart', (t) async {
    t.view.physicalSize = const Size(1100, 1600);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final today = DateTime.now();
    EquicycleYears.instance.seedForTest([EqYear(year: today.year, start: DateTime(today.year, today.month, today.day).subtract(const Duration(days: 20)), length: 364)]);
    final api = _Api();
    final services = (await t.runAsync(() => buildTestServices(api, online: false)))!;
    services.store.calendar.value = {'events': <dynamic>[]};
    await t.pumpWidget(AppScope(services: services, child: const MaterialApp(home: Scaffold(body: CalendarView()))));
    for (var i = 0; i < 3; i++) {
      await t.pump();
      await t.runAsync(() => Future.delayed(const Duration(milliseconds: 60)));
    }
    await t.pump();
    expect(api.asked.where((p) => p.startsWith('/api/cycle-theme')).length, 1);
    expect(find.textContaining('Mend'), findsWidgets);

    api.theme = 'Scale'; // compass saved a new word
    CycleThemeBus.instance.changed();
    for (var i = 0; i < 3; i++) {
      await t.pump();
      await t.runAsync(() => Future.delayed(const Duration(milliseconds: 60)));
    }
    await t.pump();
    expect(api.asked.where((p) => p.startsWith('/api/cycle-theme')).length, 2, reason: 'fetched again');
    expect(find.textContaining('Scale'), findsWidgets);
    expect(find.textContaining('Mend'), findsNothing);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });
}
