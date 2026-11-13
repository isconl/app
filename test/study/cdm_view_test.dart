import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/study/cdm/cdm_model.dart';
import 'package:isconl/study/cdm/cdm_view.dart';

/// BI26092620: every v3 block kind draws, in a light and a dark theme, and the
/// edge cases (unknown kind, bad LaTeX, hidden answers, author-only content) behave.
///
/// These are structural checks rather than pixel goldens: the app's CI builds on
/// Linux and Windows runners, and pixel snapshots differ between them.
CdmDoc fixture() => CdmDoc.fromJsonString(File('test/fixtures/cdm_v3_module.json').readAsStringSync());

Future<void> pump(WidgetTester tester, CdmDoc doc, {Brightness brightness = Brightness.dark}) async {
  await tester.binding.setSurfaceSize(const Size(420, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(brightness: brightness),
    home: Scaffold(body: SingleChildScrollView(child: CdmView(doc))),
  ));
  await tester.pump();
}

void main() {
  for (final b in [Brightness.light, Brightness.dark]) {
    group('v3 fixture, ${b.name} theme', () {
      testWidgets('draws with no exception and every callout label shows', (tester) async {
        await pump(tester, fixture(), brightness: b);
        expect(tester.takeException(), isNull);
        for (final style in cdmCalloutStyles.values) {
          expect(find.text(style.label.toUpperCase()), findsWidgets, reason: style.label);
        }
      });

      testWidgets('every block carries its block id as a key', (tester) async {
        final doc = fixture();
        await pump(tester, doc, brightness: b);
        for (final n in doc.sections) {
          expect(find.byKey(ValueKey('cdm-${n.id}'), skipOffstage: false), findsOneWidget, reason: n.id);
        }
      });
    });
  }

  testWidgets('figures: a table, a typeset equation, charts, an image fallback and a map card', (tester) async {
    await pump(tester, fixture());
    expect(find.text('Month'), findsOneWidget);
    expect(find.text('Feb'), findsWidgets);
    expect(find.byType(Math), findsWidgets);
    expect(find.text('OUT BY MONTH'), findsOneWidget);
    expect(find.text('NET'), findsOneWidget);
    expect(find.text('SHARE'), findsOneWidget);
    expect(find.text('Figure 1. Inflows and outflows'), findsOneWidget);
    expect(find.text('Kisumu market'), findsOneWidget);
    expect(find.text('Open map'), findsOneWidget);
    expect(find.textContaining('OpenStreetMap'), findsOneWidget);
    expect(find.textContaining('SELECT month'), findsOneWidget);
  });

  testWidgets('a LaTeX parse error shows the source and does not crash', (tester) async {
    await pump(tester, fixture());
    expect(tester.takeException(), isNull);
    expect(find.text(r'\frac{a}{'), findsOneWidget);
  });

  testWidgets('a quiz group hides its answers until Reveal is tapped', (tester) async {
    await pump(tester, fixture());
    expect(find.text('CHECK YOURSELF'), findsOneWidget);
    expect(find.textContaining('ANSWER: February'), findsNothing);
    await tester.ensureVisible(find.text('Reveal'));
    await tester.tap(find.text('Reveal'));
    await tester.pump();
    expect(find.textContaining('ANSWER: February'), findsOneWidget);
    await tester.tap(find.text('Hide'));
    await tester.pump();
    expect(find.textContaining('ANSWER: February'), findsNothing);
  });

  testWidgets('author-only and truth-check content never reaches the reader', (tester) async {
    await pump(tester, fixture());
    expect(find.textContaining('AUTHOR ONLY NOTE'), findsNothing);
    expect(find.textContaining('HIDDEN CLAIM'), findsNothing);
    expect(find.textContaining('Learner-facing aside'), findsOneWidget);
  });

  testWidgets('an unknown block kind shows the update box, logs once, and the page still draws', (tester) async {
    resetCdmUnknownLog();
    final logs = <String>[];
    final old = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) => logs.add(m ?? '');

    final doc = CdmDoc.fromJson({
      'headline': 'x',
      'sections': [
        {'type': 'hologram'},
        {'type': 'hologram'},
        {'type': 'paragraph', 'text': 'still here'},
      ]
    });
    try {
      await pump(tester, doc);
    } finally {
      debugPrint = old; // restored before the framework's invariant check, not in a teardown
    }
    expect(find.text('This part needs an app update'), findsNWidgets(2));
    expect(find.text('still here'), findsOneWidget);
    expect(logs.where((l) => l.contains('hologram')), hasLength(1), reason: 'one kind logs once, not per block');
  });

  testWidgets('a callout of a kind this build does not know falls back to a plain note', (tester) async {
    final doc = CdmDoc.fromJson({
      'headline': 'x',
      'sections': [
        {'type': 'callout', 'kind': 'from_the_future', 'text': 'body text'},
      ]
    });
    await pump(tester, doc);
    expect(tester.takeException(), isNull);
    expect(find.text('NOTE'), findsOneWidget);
    expect(find.text('body text'), findsOneWidget);
  });
}
