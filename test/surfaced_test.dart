import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/theme.dart';
import 'package:isconl/ui/views/surfaced.dart';

List<Map<String, dynamic>> items() => [
      {'ID': 'S1', 'TITLE': 'Rent is due', 'BODY': 'Pay before Friday', 'ORIGIN': 'ledger', 'STATUS': 'new', 'CREATED_AT': '2026-10-14', 'VIEW': 'task', 'REF': 'T9'},
      {'ID': 'S2', 'TITLE': 'Review the plan', 'BODY': '-', 'ORIGIN': 'slate', 'STATUS': 'seen', 'CREATED_AT': '2026-10-13', 'VIEW': '-', 'REF': '-'},
      {'ID': 'S3', 'TITLE': 'Check the course', 'BODY': 'x' * 300, 'ORIGIN': 'study', 'STATUS': 'new', 'CREATED_AT': '2026-10-12', 'VIEW': 'study', 'REF': 'c1'},
    ];

Widget host(List<Map<String, dynamic>> list, {List<String>? updates, List<String>? opened, bool fail = false}) => MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: SurfacedView(
          items: list,
          update: (id, status) async {
            if (fail) throw Exception('The agent said no');
            updates?.add('$id:$status');
          },
          onOpen: (ctx, view, ref) => opened?.add('$view:$ref'),
        ),
      ),
    );

void main() {
  testWidgets('lists the items with a count, unread dots and trimmed bodies', (t) async {
    await t.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(host(items()));
    expect(find.text('3 items'), findsOneWidget);
    expect(find.text('Rent is due'), findsOneWidget);
    expect(find.text('Pay before Friday'), findsOneWidget);
    expect(find.byKey(const Key('unread-dot')), findsNWidgets(2));
    expect(find.textContaining('...'), findsOneWidget);
    expect(find.byKey(const Key('seen-S2')), findsNothing); // already seen
  });

  testWidgets('Mark seen updates at once and tells the agent', (t) async {
    await t.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final updates = <String>[];
    await t.pumpWidget(host(items(), updates: updates));
    await t.tap(find.byKey(const Key('seen-S1')));
    await t.pumpAndSettle();
    expect(updates, ['S1:seen']);
    expect(find.byKey(const Key('seen-S1')), findsNothing);
    expect(find.byKey(const Key('unread-dot')), findsOneWidget);
  });

  testWidgets('Dismiss asks first, and Keep it changes nothing', (t) async {
    await t.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final updates = <String>[];
    await t.pumpWidget(host(items(), updates: updates));
    await t.tap(find.byKey(const Key('dismiss-S2')));
    await t.pumpAndSettle();
    expect(find.text('Dismiss this?'), findsOneWidget);
    await t.tap(find.text('Keep it'));
    await t.pumpAndSettle();
    expect(updates, isEmpty);
    expect(find.text('Review the plan'), findsOneWidget);
    await t.tap(find.byKey(const Key('dismiss-S2')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('dismiss-confirm')));
    await t.pumpAndSettle();
    expect(updates, ['S2:dismissed']);
    expect(find.text('Review the plan'), findsNothing);
    expect(find.text('2 items'), findsOneWidget);
  });

  testWidgets('opening a new item marks it seen and goes to what it points at', (t) async {
    await t.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final updates = <String>[];
    final opened = <String>[];
    await t.pumpWidget(host(items(), updates: updates, opened: opened));
    await t.tap(find.byKey(const Key('surfaced-S1')));
    await t.pumpAndSettle();
    expect(updates, ['S1:seen']);
    expect(opened, ['task:T9']);
  });

  testWidgets('an already seen item opens without another update; one with no target goes nowhere', (t) async {
    await t.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final updates = <String>[];
    final opened = <String>[];
    await t.pumpWidget(host(items(), updates: updates, opened: opened));
    await t.tap(find.byKey(const Key('surfaced-S2'))); // seen, no VIEW or REF
    await t.pumpAndSettle();
    expect(updates, isEmpty);
    expect(opened, isEmpty);
  });

  testWidgets('a refused update puts the row back and says why', (t) async {
    await t.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(host(items(), fail: true));
    await t.tap(find.byKey(const Key('seen-S1')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('seen-S1')), findsOneWidget);
    expect(find.textContaining('The agent said no'), findsOneWidget);
  });

  testWidgets('an empty list says so', (t) async {
    await t.pumpWidget(host(const []));
    expect(find.text('Nothing surfaced right now'), findsOneWidget);
    expect(find.text('0 items'), findsOneWidget);
  });
}
