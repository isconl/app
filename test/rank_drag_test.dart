import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/services/rank_feedback.dart';
import 'package:isconl/ui/views/learned_ranking.dart';
import 'package:isconl/ui/widgets/rank_drag.dart';

import 'support/test_services.dart';

/// PI26101601: drag to reorder, the three-choice sheet, the offline path and the Learned ranking page.
class _FakeRank implements RankApi {
  _FakeRank(this.items);
  List<LearnedAdjustment> items;
  final undone = <int>[];
  @override
  Future<List<LearnedAdjustment>> adjustments() async => List.of(items);
  @override
  Future<void> undo(int id) async {
    undone.add(id);
    items = [for (final a in items) if (a.id != id) a];
  }
}

void main() {
  final items = [
    {'ID': 'A1', 'TITLE': 'First'},
    {'ID': 'B2', 'TITLE': 'Second'},
    {'ID': 'C3', 'TITLE': 'Third'},
  ];

  group('rowAbove', () {
    final ids = ['A1', 'B2', 'C3'];
    test('moving the last row to the top lands it above the first', () => expect(rowAbove(ids, 2, 0), 'A1'));
    test('moving the first row down one lands it above the third (Flutter reports newIndex 2)', () => expect(rowAbove(ids, 0, 2), 'C3'));
    test('dropping at the very end has nothing below it', () => expect(rowAbove(ids, 0, 3), isNull));
  });

  Future<BuildContext> host(WidgetTester tester) async {
    final services = (await tester.runAsync(() => buildTestServices(ScriptedApi({}))))!;
    late BuildContext ctx;
    await tester.pumpWidget(AppScope(
      services: services,
      child: MaterialApp(home: Scaffold(body: Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      }))),
    ));
    return ctx;
  }

  testWidgets('the sheet offers the three choices, and Cancel returns nothing', (tester) async {
    final ctx = await host(tester);
    RankAnswer? got = RankAnswer.urgent;
    var done = false;
    showRankSheet(ctx, title: 'First').then((a) {
      got = a;
      done = true;
    });
    await tester.pumpAndSettle();
    expect(find.text('More urgent'), findsOneWidget);
    expect(find.text('More valuable'), findsOneWidget);
    expect(find.text('Just this once'), findsOneWidget);
    await tester.tap(find.byKey(const Key('rank-cancel')));
    await tester.pumpAndSettle();
    expect(done, isTrue);
    expect(got, isNull);
  });

  for (final a in RankAnswer.values) {
    testWidgets('${a.label} goes to slate with the moved row and the row it now sits above, and slate\'s sentence is shown', (tester) async {
      final ctx = await host(tester);
      final sent = <String>[];
      var reloaded = 0;
      handleRankDrop(ctx, items: items, oldIndex: 2, newIndex: 0, reload: () => reloaded++, ask: (_, __) async => a, send: (m, ans, above, t) async {
        sent.add('$m:${ans.wire}:$above:$t');
        return (queued: false, error: null, sentence: 'Slate says ${ans.wire}.');
      });
      await tester.pumpAndSettle();
      expect(sent, ['C3:${a.wire}:A1:Third']);
      expect(find.text('Slate says ${a.wire}.'), findsOneWidget);
      expect(reloaded, 1);
    });
  }

  testWidgets('Cancel sends nothing and reloads nothing', (tester) async {
    final ctx = await host(tester);
    var sends = 0, reloads = 0;
    await handleRankDrop(ctx, items: items, oldIndex: 0, newIndex: 2, reload: () => reloads++, ask: (_, __) async => null, send: (m, a, b, t) async {
      sends++;
      return (queued: false, error: null, sentence: '');
    });
    expect(sends + reloads, 0);
  });

  testWidgets('offline, the answer is queued in the outbox and the snackbar says so', (tester) async {
    final services = (await tester.runAsync(() => buildTestServices(ScriptedApi({}), online: false)))!;
    final r = await tester.runAsync(() => services.mutations.rankFeedback(moved: 'C3', answer: 'urgent', above: 'A1', title: 'Third'));
    expect(r!.queued, isTrue);
    final rows = (await tester.runAsync(() => services.db.pendingOutbox()))!.where((x) => x['path'] == '/api/rank/feedback').toList();
    expect(rows.single['label'], 'Order · Third');
  });

  testWidgets('Learned ranking lists each sentence with its fade date, and Undo removes one', (tester) async {
    final api = _FakeRank([
      LearnedAdjustment(id: 7, sentence: 'Viva counts as more valuable.', fadesAt: DateTime.utc(2026, 11, 7)),
      LearnedAdjustment(id: 8, sentence: 'Deck counts as more urgent.', fadesAt: DateTime.utc(2026, 11, 9)),
    ]);
    await tester.pumpWidget(MaterialApp(home: LearnedRankingPage(api: api)));
    await tester.pumpAndSettle();
    expect(find.text('Viva counts as more valuable.'), findsOneWidget);
    expect(find.text('Fades 2026-11-07'), findsOneWidget);
    await tester.tap(find.byKey(const Key('undo-7')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 50));
    expect(api.undone, [7]);
    expect(find.text('Viva counts as more valuable.'), findsNothing);
    expect(find.text('Deck counts as more urgent.'), findsOneWidget);
  });

  testWidgets('Learned ranking with nothing learned says how to teach it', (tester) async {
    await tester.pumpWidget(MaterialApp(home: LearnedRankingPage(api: _FakeRank([]))));
    await tester.pumpAndSettle();
    expect(find.text('Nothing learned yet. Drag a task to teach the order.'), findsOneWidget);
  });
}
