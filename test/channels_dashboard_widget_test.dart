import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/ui/views/channels_dash_model.dart';
import 'package:isconl/ui/views/channels_dashboard.dart';

void main() {
  final dash = ChannelsDash.from(
    now: DateTime(2026, 10, 3, 12),
    feed: [
      {'CHANNEL': 'gmail', 'RECEIVED_AT': DateTime(2026, 10, 3, 9).toIso8601String(), 'STATUS': 'new', 'DIRECTION': 'in', 'BODY': 'hi'},
    ],
    jiraIssues: [
      {'status': 'In Progress'},
      {'status': 'Done'},
    ],
    buffer: {
      'queue': [
        {'text': 'Launch post'}
      ]
    },
  );

  for (final w in [390.0, 1280.0]) {
    testWidgets('renders at $w px without overflow and opens sub-tabs', (t) async {
      t.view.physicalSize = Size(w, 1600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final opened = <String>[];
      await t.pumpWidget(MaterialApp(
        home: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(14), child: ChannelsDashboard(dash: dash, onOpenView: opened.add))),
      ));
      await t.pump();
      expect(t.takeException(), isNull);
      expect(find.text('UNREAD'), findsOneWidget);
      expect(find.text('Launch post'), findsOneWidget);
      await t.tap(find.text('KANBAN'));
      await t.tap(find.text('BUFFER, NEXT UP'));
      expect(opened, ['jira', 'social']);
    });
  }

  testWidgets('the pinned summary reads in one line', (t) async {
    await t.pumpWidget(MaterialApp(home: Scaffold(body: ChannelsSummaryBar(dash: dash, visible: true))));
    expect(find.text('1 unread  ·  oldest 3 h  ·  1 in progress'), findsOneWidget);
  });
}
