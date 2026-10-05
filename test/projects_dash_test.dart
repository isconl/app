import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/ui/views/projects_dash_model.dart';
import 'package:isconl/ui/views/projects_dashboard.dart';

void main() {
  test('portfolio splits by category from CATEGORY, TYPE or cat', () {
    final d = ProjectsDash.from([
      {'CATEGORY': 'Product'},
      {'TYPE': 'platform'},
      {'cat': 'practice'},
      {'CATEGORY': 'something else'},
    ]);
    expect(d.byCategory['Product'], 1);
    expect(d.byCategory['Platform'], 1);
    expect(d.byCategory['Practice'], 1);
    expect(d.byCategory['Other'], 1);
    expect(d.total, 4);
  });

  test('no projects gives zeros and no Other bucket', () {
    final d = ProjectsDash.from(const []);
    expect(d.total, 0);
    expect(d.byCategory.containsKey('Other'), false);
  });

  for (final w in [390.0, 1280.0]) {
    testWidgets('renders at $w px; unbacked tiles say so; no invented numbers', (t) async {
      t.view.physicalSize = Size(w, 1800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: ProjectsDashboard(dash: ProjectsDash.from([{'CATEGORY': 'product'}])),
          ),
        ),
      ));
      await t.pump();
      expect(t.takeException(), isNull);
      expect(find.text('booking not live yet'), findsOneWidget);
      expect(find.text('Needs the Slate counts'), findsNWidgets(2));
      expect(find.text('Needs the booking metrics'), findsOneWidget);
      expect(find.text('No data yet'), findsNWidgets(2));
    });
  }
}
