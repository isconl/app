import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/ui/status_chip.dart';

class _Fixed extends StatusChipSource {
  _Fixed(this.chip);
  final StatusChip? chip;
  final ValueNotifier<int> _n = ValueNotifier(0);
  @override
  Listenable get changes => _n;
  @override
  StatusChip? current(BuildContext context) => chip;
}

void main() {
  final now = DateTime(2026, 10, 1, 12);

  group('BI26092622: freshness text', () {
    test('offline wins, then queued writes, then age', () {
      expect(freshnessText(online: false, pending: 3, lastSync: now, now: now), 'offline');
      expect(freshnessText(online: true, pending: 3, lastSync: now, now: now), '3 queued');
      expect(freshnessText(online: true, pending: 0, lastSync: null, now: now), 'live');
      expect(freshnessText(online: true, pending: 0, lastSync: now.subtract(const Duration(seconds: 30)), now: now), 'live');
      expect(freshnessText(online: true, pending: 0, lastSync: now.subtract(const Duration(minutes: 2)), now: now), '2m ago');
      expect(freshnessText(online: true, pending: 0, lastSync: now.subtract(const Duration(hours: 5)), now: now), '5h ago');
      expect(freshnessText(online: true, pending: 0, lastSync: now.subtract(const Duration(days: 3)), now: now), '3d ago');
    });

    test('the backlog count sums every project row and is null before the first fetch', () {
      expect(backlogRowCount(null), isNull);
      expect(backlogRowCount({'projects': []}), isNull);
      expect(
        backlogRowCount({
          'projects': [
            {'project': 'a', 'rows': [{}, {}, {}]},
            {'project': 'b', 'rows': [{}]},
            {'project': 'c'},
          ]
        }),
        4,
      );
    });
  });

  group('BI26092622: the chip in the app bar', () {
    Future<void> pumpBar(WidgetTester tester, StatusChipSource? source) => tester.pumpWidget(
          MaterialApp(
            home: Scaffold(appBar: _bar(source)),
          ),
        );

    testWidgets('no source means no dot and no chip', (tester) async {
      await pumpBar(tester, null);
      expect(find.byKey(const Key('status-chip')), findsNothing);
      expect(find.textContaining('·'), findsNothing);
    });

    testWidgets('a chip renders after the title as a dot and small text, and tapping it calls back', (tester) async {
      var tapped = 0;
      await pumpBar(tester, _Fixed(StatusChip('3 queued', (_) => tapped++)));
      final text = tester.widget<Text>(find.byKey(const Key('status-chip')));
      expect(text.data, '  ·  3 queued');
      expect(text.style?.fontSize, 11);
      await tester.tap(find.byKey(const Key('status-chip')));
      expect(tapped, 1);
    });

    testWidgets('long text is cut at 18 characters with an ellipsis', (tester) async {
      await pumpBar(tester, _Fixed(StatusChip('abcdefghijklmnopqrstuvwxyz', (_) {})));
      final text = tester.widget<Text>(find.byKey(const Key('status-chip')));
      expect(text.data, '  ·  abcdefghijklmnopq…');
    });

    testWidgets('the selector prefers the specific chip and falls back when it has none', (tester) async {
      final fallback = _Fixed(StatusChip('live', (_) {}));
      await pumpBar(tester, ChipSelector(_Fixed(StatusChip('slate 298', (_) {})), fallback));
      expect(tester.widget<Text>(find.byKey(const Key('status-chip'))).data, '  ·  slate 298');
      await pumpBar(tester, ChipSelector(_Fixed(null), fallback));
      expect(tester.widget<Text>(find.byKey(const Key('status-chip'))).data, '  ·  live');
    });
  });
}

// ShellAppBar reads AppScope for the elapsed-time line, so the chip tests use the label directly
// inside a plain AppBar title row, the same widget the real bar embeds.
PreferredSizeWidget _bar(StatusChipSource? source) => AppBar(
      title: Row(
        children: [
          const Flexible(child: Text('Systems')),
          if (source != null) StatusChipLabel(source: source),
        ],
      ),
    );
