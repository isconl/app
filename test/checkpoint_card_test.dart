import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/api/client.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/theme.dart';
import 'package:isconl/ui/views/hub.dart';
import 'package:isconl/ui/widgets/checkpoint_card.dart';
import 'package:isconl/ui/widgets/common.dart' show Panel;

import 'support/test_services.dart';

const fixture = {
  'label': 'Afternoon checkpoint',
  'heading': 'Two things need you',
  'subhead': 'One review is overdue since Monday and the weekly brief is ready for your edit before Friday.',
  'status': '2 flagged · 5 open',
  'route': 'tasks',
};

void main() {
  Future<AppServices> pumpCard(WidgetTester tester, Object answer, {bool preset = true}) async {
    final api = ScriptedApi({'/api/checkpoint': answer});
    final services = (await tester.runAsync(() => buildTestServices(api)))!;
    if (preset && answer is Map<String, dynamic>) services.store.checkpoint.value = answer;
    await tester.pumpWidget(AppScope(services: services, child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: CheckpointCard())))));
    await tester.pump();
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 80)));
    await tester.pump();
    return services;
  }

  group('BI26092624: checkpoint card', () {
    testWidgets('the copy comes from the server and is styled as specified', (tester) async {
      await pumpCard(tester, Map<String, dynamic>.from(fixture));
      final label = tester.widget<Text>(find.byKey(const Key('checkpoint-label')));
      expect(label.data, 'AFTERNOON CHECKPOINT');
      expect(label.style?.letterSpacing, 1.2);
      expect(label.style?.color, C.greenBright);
      expect(label.style?.fontWeight, FontWeight.w600);
      final heading = tester.widget<Text>(find.byKey(const Key('checkpoint-heading')));
      expect(heading.data, 'Two things need you');
      expect(heading.style?.fontWeight, FontWeight.w600);
      expect(heading.style?.color, C.text);
      final sub = tester.widget<Text>(find.byKey(const Key('checkpoint-subhead')));
      expect(sub.style?.fontWeight, FontWeight.w400);
      expect(sub.style?.color, C.text2);
      expect(sub.maxLines, 2);
      final status = tester.widget<Text>(find.byKey(const Key('checkpoint-status')));
      expect(status.style, T.statusMono);
      expect(status.style?.fontSize, 11);
      expect(tester.widget<Container>(find.byKey(const Key('checkpoint-edge'))).color, C.green);
      expect(tester.getSize(find.byKey(const Key('checkpoint-edge'))).width, 3);
    });

    testWidgets('the callout has a subtle green tint over the panel, not the plain panel colour', (tester) async {
      await pumpCard(tester, Map<String, dynamic>.from(fixture));
      final panel = tester.widget<Panel>(find.byType(Panel));
      expect(panel.color, Color.alphaBlend(C.green.withAlpha(24), C.panel));
      expect(panel.color, isNot(C.panel));
    });

    testWidgets('a 404 with no cache hides the section entirely', (tester) async {
      await pumpCard(tester, ApiException(404, 'not found'), preset: false);
      expect(find.byKey(const Key('checkpoint-heading')), findsNothing);
      expect(find.byKey(const Key('checkpoint-edge')), findsNothing);
    });

    testWidgets('a missing subhead or status leaves those lines out, not blank', (tester) async {
      await pumpCard(tester, {'label': 'Morning checkpoint', 'heading': 'All clear today'});
      expect(find.byKey(const Key('checkpoint-heading')), findsOneWidget);
      expect(find.byKey(const Key('checkpoint-subhead')), findsNothing);
      expect(find.byKey(const Key('checkpoint-status')), findsNothing);
    });
  });

  group('BI26092624: on the Hub', () {
    testWidgets('the order is the date block, then the checkpoint, then the ring', (tester) async {
      final api = ScriptedApi({'/api/checkpoint': Map<String, dynamic>.from(fixture)});
      final services = (await tester.runAsync(() => buildTestServices(api)))!;
      services.store.checkpoint.value = Map<String, dynamic>.from(fixture);
      services.store.state.value = {
        'time': {'eqShort': '2026-5', 'sprintShort': 'W39', 'yearPct': 74},
        'tasks': [],
        'feed': [],
        'services': {},
      };
      await tester.pumpWidget(AppScope(services: services, child: const MaterialApp(home: Scaffold(body: HubView()))));
      await tester.pump();
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 120)));
      await tester.pump();
      final dateY = tester.getTopLeft(find.textContaining('2026').first).dy;
      final checkY = tester.getTopLeft(find.byKey(const Key('checkpoint-heading'))).dy;
      expect(checkY, greaterThan(dateY), reason: 'the checkpoint sits below the date block');
      expect(find.byKey(const Key('checkpoint-heading')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
      await tester.pump(const Duration(seconds: 2));
    });
  });
}
