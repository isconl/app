import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/ui/shell.dart';
import 'package:isconl/ui/status_chip.dart';
import 'package:isconl/ui/widgets/brand.dart';
import 'package:isconl/ui/widgets/common.dart';

import 'support/test_services.dart';

class _Chip extends StatusChipSource {
  final ValueNotifier<int> _n = ValueNotifier(0);
  @override
  Listenable get changes => _n;
  @override
  StatusChip? current(BuildContext context) => StatusChip('reap · 23/28', (_) {});
}

// BI26100541: chips under the title, the same bar on menu views, w800 landing titles.
void main() {
  testWidgets('a long page title is not cut short and the chip sits on the line below it', (t) async {
    final services = (await t.runAsync(() => buildTestServices(ScriptedApi({}))))!;
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    const title = 'A rather long page title';
    await t.pumpWidget(AppScope(
      services: services,
      child: MaterialApp(home: Scaffold(appBar: ShellAppBar(title: title, chipSource: _Chip()))),
    ));
    await t.pump();
    final titleText = t.widget<Text>(find.text(title));
    expect(titleText.overflow, TextOverflow.ellipsis);
    expect(t.takeException(), isNull);
    // The title is whole (its box is as wide as its text needs) and the chip is below it.
    expect(t.getBottomLeft(find.text(title)).dy, lessThanOrEqualTo(t.getTopLeft(find.byKey(const Key('status-chip'))).dy + 1));
    expect(t.widget<Text>(find.byKey(const Key('status-chip'))).data, 'reap · 23/28');
  });

  testWidgets('a view opened from the menu wears the same bar: logo, title, chips, cloud', (t) async {
    final services = (await t.runAsync(() => buildTestServices(ScriptedApi({}))))!;
    await t.pumpWidget(AppScope(
      services: services,
      child: const MaterialApp(home: SecondaryScreen(title: 'Journal', child: SizedBox())),
    ));
    await t.pump();
    expect(find.byType(BrandMark), findsOneWidget);
    expect(find.text('Journal'), findsOneWidget);
    expect(find.byKey(const Key('status-chip')), findsOneWidget);
    expect(find.byType(SyncIndicator), findsOneWidget);
  });

  testWidgets('the app bar holds exactly one sync mark', (t) async {
    final services = (await t.runAsync(() => buildTestServices(ScriptedApi({}))))!;
    await t.pumpWidget(AppScope(
      services: services,
      child: const MaterialApp(home: Scaffold(appBar: ShellAppBar(title: 'Hub'))),
    ));
    await t.pump();
    expect(find.byType(SyncIndicator), findsOneWidget);
    expect(find.byType(StatusDot), findsNothing);
  });
}
