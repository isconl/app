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

// BI26100541: the same bar on menu views, w800 landing titles. BI26101519: title and code part on one row.
void main() {
  testWidgets('the title and the minified chip share one row at 360 px, with no overflow', (t) async {
    final services = (await t.runAsync(() => buildTestServices(ScriptedApi({}))))!;
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(AppScope(
      services: services,
      child: MaterialApp(home: Scaffold(appBar: ShellAppBar(title: 'Hub', chipSource: _Chip()))),
    ));
    await t.pump();
    expect(t.takeException(), isNull);
    final title = t.getRect(find.text('Hub'));
    final chip = t.getRect(find.byKey(const Key('status-chip')));
    // The chip is to the right of the title and its box sits inside the title's row, not under it.
    expect(chip.left, greaterThan(title.right));
    expect(chip.center.dy, inInclusiveRange(title.top, title.bottom));
    expect(t.widget<Text>(find.byKey(const Key('status-chip'))).data, 'reap · 23/28');
  });

  testWidgets('a long title is never cut for the code part: the code part drops out instead', (t) async {
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
    expect(t.takeException(), isNull);
    expect(t.widget<Text>(find.text(title)).overflow, TextOverflow.ellipsis);
    expect(find.byKey(const Key('status-chip')), findsNothing);
  });

  testWidgets('one cloud in the app bar for each sync state, and the update dot is on that same cloud', (t) async {
    Future<void> pump(SyncMark mark, {bool update = false}) => t.pumpWidget(MaterialApp(
          home: Scaffold(
            appBar: AppBar(actions: [SyncCloud(mark: mark, label: 'x', updateAvailable: update)]),
          ),
        ));
    for (final mark in SyncMark.values) {
      await pump(mark);
      final clouds = find.byWidgetPredicate((w) => w is Icon && (w.icon == Icons.cloud_outlined || w.icon == Icons.cloud_off_outlined));
      expect(clouds, findsOneWidget, reason: '$mark');
      expect(find.byKey(const Key('sync-update-dot')), findsNothing);
    }
    await pump(SyncMark.synced, update: true);
    expect(find.byKey(const Key('sync-update-dot')), findsOneWidget);
    expect(find.byIcon(Icons.cloud_outlined), findsOneWidget);
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
