import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/theme.dart';
import 'package:isconl/ui/widgets/common.dart';

/// BI26100405: one primary (green, bottom-right), any number of secondaries (small, grey, above it).
void main() {
  Widget host(FabStack stack) => MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: const SizedBox.expand(),
          floatingActionButton: stack,
          floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        ),
      );

  testWidgets('one green primary at bottom-right with grey secondaries stacked above it', (t) async {
    await t.pumpWidget(host(FabStack(
      primary: FabAction(icon: Icons.vertical_align_top_rounded, tooltip: 'Scroll to top', onPressed: () {}),
      secondary: [
        FabAction(icon: Icons.edit_note_rounded, tooltip: 'Notes', onPressed: () {}),
        FabAction(icon: Icons.receipt_long_rounded, tooltip: 'Receipt', onPressed: () {}),
      ],
    )));
    final fabs = t.widgetList<FloatingActionButton>(find.byType(FloatingActionButton)).toList();
    expect(fabs.length, 3);
    final green = fabs.where((f) => f.backgroundColor == C.green).toList();
    expect(green.length, 1, reason: 'exactly one primary green FAB');
    expect(fabs.where((f) => f.mini).length, 2, reason: 'secondaries are small');
    expect(fabs.where((f) => f.mini).every((f) => f.backgroundColor == C.surface), isTrue, reason: 'and grey');

    final primary = find.byKey(const Key('fab-primary'));
    final s0 = find.byKey(const Key('fab-secondary-0'));
    final s1 = find.byKey(const Key('fab-secondary-1'));
    final screen = t.view.physicalSize / t.view.devicePixelRatio;
    // Bottom-right: the primary sits in the right half and the bottom half of the screen.
    expect(t.getCenter(primary).dx, greaterThan(screen.width / 2));
    expect(t.getCenter(primary).dy, greaterThan(screen.height / 2));
    // Secondaries are above the primary, in order, on the same right edge.
    expect(t.getCenter(s0).dy, lessThan(t.getCenter(s1).dy));
    expect(t.getCenter(s1).dy, lessThan(t.getCenter(primary).dy));
    expect(t.getBottomRight(s0).dx, closeTo(t.getBottomRight(primary).dx, 0.5));
  });

  testWidgets('with no primary the secondaries stand alone, and a tap works', (t) async {
    var notes = 0;
    await t.pumpWidget(host(FabStack(
      secondary: [FabAction(icon: Icons.edit_note_rounded, tooltip: 'Notes', onPressed: () => notes++)],
    )));
    expect(find.byKey(const Key('fab-primary')), findsNothing);
    await t.tap(find.byKey(const Key('fab-secondary-0')));
    expect(notes, 1);
  });

  // The module view: scroll-to-top is the primary, notes is a secondary (read from the source,
  // so a later edit cannot quietly put a second green button back).
  test('the module view builds its floating buttons only through FabStack', () {
    final src = File('lib/ui/views/learning.dart').readAsStringSync();
    expect(src.contains('FabStack('), isTrue);
    expect(RegExp(r'\bCircleFab\(').hasMatch(src), isFalse, reason: 'no raw green FAB in the module view');
    expect(RegExp(r'FloatingActionButton\(').hasMatch(src), isFalse);
    final i = src.indexOf('FabStack(');
    final block = src.substring(i, i + 1600);
    expect(block.contains("tooltip: 'Scroll to top'"), isTrue);
    expect(block.indexOf('primary:') < block.indexOf('secondary:'), isTrue);
    expect(block.indexOf("tooltip: 'Scroll to top'") < block.indexOf('secondary:'), isTrue, reason: 'scroll-to-top is the primary');
    expect(block.indexOf("tooltip: 'Notes'") > block.indexOf('secondary:'), isTrue, reason: 'notes is secondary');
  });

  test('no screen builds two raw floating buttons of its own', () {
    for (final f in Directory('lib/ui/views').listSync().whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final n = RegExp(r'\bFloatingActionButton\(|\bCircleFab\(').allMatches(f.readAsStringSync()).length;
      expect(n <= 1, isTrue, reason: '${f.path} builds $n raw floating buttons; use FabStack');
    }
  });
}
