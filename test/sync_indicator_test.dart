import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/theme.dart';
import 'package:isconl/ui/shell.dart' show ShellAppBar, SyncIndicator;
import 'package:isconl/ui/widgets/common.dart' show StatusDot;

import 'support/test_services.dart';

Future<AppServices> _services(WidgetTester tester, {bool online = true, int queued = 0}) async {
  final services = (await tester.runAsync(() => buildTestServices(ScriptedApi({}), online: online)))!;
  for (var i = 0; i < queued; i++) {
    await tester.runAsync(() => services.outbox.enqueue(path: '/api/x$i', body: {}, label: 'x$i', view: 'v'));
  }
  return services;
}

Future<void> _pump(WidgetTester tester, AppServices services) async {
  await tester.pumpWidget(AppScope(
    services: services,
    child: MaterialApp(
      home: Scaffold(appBar: ShellAppBar(title: 'Command', onMenu: () {})),
    ),
  ));
  await tester.pump();
}

Color? _cloudColor(WidgetTester tester) => tester.widget<Icon>(find.byIcon(Icons.cloud_outlined)).color;

void main() {
  group('BI26100539: one stroked cloud in the app bar', () {
    testWidgets('idle with an empty outbox: one green cloud, no dot, no second indicator', (tester) async {
      final services = await _services(tester);
      await _pump(tester, services);
      expect(find.byType(SyncIndicator), findsOneWidget);
      expect(find.byIcon(Icons.cloud_outlined), findsOneWidget);
      expect(_cloudColor(tester), C.green);
      expect(find.byType(StatusDot), findsNothing);
    });

    testWidgets('one waiting item turns the cloud yellow and no count badge is drawn', (tester) async {
      final services = await _services(tester, queued: 1);
      await _pump(tester, services);
      expect(_cloudColor(tester), C.amber);
      expect(find.text('1'), findsNothing);
      expect(find.bySemanticsLabel('1 waiting to sync'), findsOneWidget);
    });

    testWidgets('offline shows the muted cloud-off and the tap says how many wait', (tester) async {
      final services = await _services(tester, online: false, queued: 3);
      await _pump(tester, services);
      expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
      expect(find.byIcon(Icons.cloud_outlined), findsNothing);
      await tester.tap(find.byType(SyncIndicator));
      await tester.pump();
      expect(find.text('3 waiting to sync'), findsOneWidget);
    });

    testWidgets('the semantics label reads All synced when nothing waits', (tester) async {
      final services = await _services(tester);
      await _pump(tester, services);
      expect(find.bySemanticsLabel('All synced'), findsOneWidget);
    });
  });
}
