import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/theme.dart';
import 'package:isconl/ui/views/codex.dart';
import 'package:isconl/ui/views/learning.dart';
import 'package:isconl/ui/widgets/sub_tabs.dart';

import 'support/test_services.dart';

void main() {
  group('BI26101519: SubTabs', () {
    testWidgets('renders the codex colours, with no blue, and the selection moves', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: const Scaffold(
          body: SubTabs(
            keyPrefix: 'demo',
            labels: ['One', 'Two', 'Three'],
            children: [Text('body one'), Text('body two'), Text('body three')],
          ),
        ),
      ));
      final bar = tester.widget<TabBar>(find.byKey(const ValueKey('demo-tabs')));
      expect(bar.labelColor, C.greenBright);
      expect(bar.indicatorColor, C.greenBright);
      expect(bar.unselectedLabelColor, C.text3);
      expect(bar.dividerColor, C.border);
      expect(bar.isScrollable, isFalse);
      expect(find.text('body one'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('demo-tab-two')));
      await tester.pumpAndSettle();
      expect(find.text('body two'), findsOneWidget);
      expect(find.text('body one'), findsNothing);
    });

    testWidgets('onChanged reports the chosen index', (tester) async {
      final seen = <int>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SubTabs(
            keyPrefix: 'demo',
            labels: const ['A', 'B'],
            onChanged: seen.add,
            children: const [Text('a'), Text('b')],
          ),
        ),
      ));
      await tester.tap(find.byKey(const ValueKey('demo-tab-b')));
      await tester.pumpAndSettle();
      expect(seen, [1]);
    });

    testWidgets('Codex keeps its three tabs and its colours on the shared widget', (tester) async {
      final services = (await tester.runAsync(() => buildTestServices(ScriptedApi({}))))!;
      await tester.pumpWidget(AppScope(services: services, child: const MaterialApp(home: Scaffold(body: CodexView()))));
      await tester.pump();
      final bar = tester.widget<TabBar>(find.byKey(const ValueKey('codex-tabs')));
      expect(bar.labelColor, C.greenBright);
      expect(bar.unselectedLabelColor, C.text3);
      for (final t in CodexView.tabs) {
        expect(find.descendant(of: find.byKey(const ValueKey('codex-tabs')), matching: find.text(t)), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
      await tester.pump(const Duration(seconds: 2));
    });
  });

  group('BI26101519: Study tabs', () {
    testWidgets('Map, Campus, Tracks in that order, Campus selected on a fresh store, Tracks shows the track cards', (tester) async {
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final services = (await tester.runAsync(() => buildTestServices(ScriptedApi({}))))!;
      services.store.learning.value = {
        'courses': [
          {'ID': 'c1', 'TITLE': 'Course One', 'GROUP_ID': 'g1', 'lessons': <dynamic>[]},
        ],
        'groups': [
          {'id': 'g1', 'label': 'Track One'},
        ],
      };
      await tester.pumpWidget(AppScope(services: services, child: const MaterialApp(home: Scaffold(body: LearningView()))));
      await tester.pump();
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 150)));
      await tester.pump();

      final labels = [
        for (final k in ['study-tab-map', 'study-tab-campus', 'study-tab-tracks'])
          tester.widget<Tab>(find.byKey(ValueKey(k))).text,
      ];
      expect(labels, ['Map', 'Campus', 'Tracks']);
      final bar = tester.widget<TabBar>(find.byKey(const ValueKey('study-tabs')));
      expect(bar.controller!.index, 1);
      // Campus is showing, so no track card yet.
      expect(find.byType(TrackCard), findsNothing);

      await tester.tap(find.byKey(const ValueKey('study-tab-tracks')));
      await tester.pumpAndSettle();
      expect(find.byType(TrackCard), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
      await tester.pump(const Duration(seconds: 2));
    });
  });
}
