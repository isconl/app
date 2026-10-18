import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/theme.dart';
import 'package:isconl/ui/widgets/common.dart';

/// PI26100503: the shell's Assistant is the one green primary on every tab; a screen's own add button
/// is a ViewFab (small, nav-green, above it), never a green FloatingActionButton of its own.
void main() {
  test('no view under lib/ui/views builds its own green FloatingActionButton', () {
    final offenders = <String>[];
    for (final f in Directory('lib/ui/views').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      if (RegExp(r'FloatingActionButton\s*\(').hasMatch(src) ||
          RegExp(r'CircleFab\s*\(').hasMatch(src)) {
        offenders.add(f.path);
      }
    }
    expect(offenders, isEmpty, reason: 'use ViewFab or FabStack, not a raw green FAB');
  });

  testWidgets('ViewFab is small, nav-green and clear of the 56dp Assistant button', (t) async {
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: Stack(children: [ViewFab(icon: Icons.add_rounded, tooltip: 'Add', onPressed: () {})]),
        floatingActionButton: CircleFab(icon: const Icon(Icons.chat), onPressed: () {}, heroTag: 'fab_chat'),
      ),
    ));
    final assistant = t.getRect(find.byKey(const Key('view-fab')).evaluate().isEmpty
        ? find.byType(CircleFab)
        : find.byType(CircleFab));
    final view = t.getRect(find.byKey(const Key('view-fab')));
    final fab = t.widget<FloatingActionButton>(find.descendant(of: find.byKey(const Key('view-fab')), matching: find.byType(FloatingActionButton)).evaluate().isEmpty ? find.byKey(const Key('view-fab')) : find.byKey(const Key('view-fab')));
    expect(fab.mini, isTrue);
    expect(fab.backgroundColor, NavTint.bg);
    expect(view.bottom, lessThanOrEqualTo(assistant.top), reason: 'does not overlap the Assistant');
  });
}
