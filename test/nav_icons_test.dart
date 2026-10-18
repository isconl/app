// BI26101809: the bottom tabs wear Sconl's own icons.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/theme.dart';
import 'package:isconl/ui/shell.dart';
import 'package:isconl/ui/widgets/nav_bar.dart';

void main() {
  test('Channels, Projects, Personal and Systems use the new assets; Command keeps its glyph', () {
    final items = bottomNavItems();
    expect(items.map((i) => i.label), ['Command', 'Channels', 'Projects', 'Personal', 'Systems']);
    expect(items[0].svgAsset, isNull);
    expect(items.sublist(1).map((i) => i.svgAsset), [
      'assets/icons/nav/channels.svg',
      'assets/icons/nav/projects.svg',
      'assets/icons/nav/personal.svg',
      'assets/icons/nav/systems.svg',
    ]);
  });

  test('every icon exists as a single-path SVG and as its PNG, and the folder is declared in pubspec', () {
    for (final n in ['channels', 'projects', 'personal', 'systems']) {
      final svg = File('assets/icons/nav/$n.svg').readAsStringSync();
      expect('<path'.allMatches(svg).length, 1, reason: '$n is one path');
      expect(svg, contains('viewBox="0 0 512 512"'));
      expect(File('assets/icons/nav/$n.png').existsSync(), isTrue, reason: '$n.png kept beside it');
    }
    expect(File('pubspec.yaml').readAsStringSync(), contains('- assets/icons/nav/'));
    expect(File('assets/icons/nav_projects.svg').existsSync(), isFalse, reason: 'the old icon is gone');
  });

  testWidgets('the bar draws the four SVGs, dim at rest and the nav green when selected', (t) async {
    Future<void> pump(int index) => t.pumpWidget(MaterialApp(
          home: Scaffold(bottomNavigationBar: PillNavBar(index: index, onSelect: (_) {}, items: bottomNavItems())),
        ));
    await pump(0);
    final pics = find.byType(SvgPicture);
    expect(pics, findsNWidgets(4));
    ColorFilter? filterOf(int i) => t.widget<SvgPicture>(pics.at(i)).colorFilter;
    final dim = ColorFilter.mode(C.text3, BlendMode.srcIn);
    final green = ColorFilter.mode(C.greenBright, BlendMode.srcIn);
    // at rest: dim
    for (var i = 0; i < 4; i++) {
      expect(filterOf(i), dim, reason: 'tab ${i + 1} at rest');
    }
    await pump(1);
    await t.pump();
    expect(filterOf(0), green, reason: 'Channels selected');
    expect(filterOf(1), dim);
  });
}
