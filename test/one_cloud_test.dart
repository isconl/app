import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/ui/shell.dart';

import 'support/test_services.dart';

/// 28 Oct 2026 (Sconl: "why do we still have two cloud icons instead of one? have it fixed across the whole app"):
/// the app bar draws exactly one sync cloud, even when a screen hands it another.
void main() {
  testWidgets('the app bar shows one sync cloud even when a screen passes its own', (tester) async {
    final services = (await tester.runAsync(() => buildTestServices(ScriptedApi({}))))!;
    await tester.pumpWidget(AppScope(
      services: services,
      child: MaterialApp(
        home: Scaffold(
          appBar: ShellAppBar(title: 'Study', showBrand: true, actions: const [SyncIndicator()], onMenu: () {}),
          body: const SizedBox(),
        ),
      ),
    ));
    await tester.pump();
    expect(find.byType(SyncIndicator), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
  });
}
