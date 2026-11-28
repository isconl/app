import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/theme.dart';
import 'package:isconl/ui/widgets/as_of_line.dart';
import 'package:isconl/util/freshness.dart';

void main() {
  final now = DateTime(2026, 10, 16, 12, 0);

  group('BI26101521: the freshness rules', () {
    test('the budgets', () {
      expect(freshnessBudgetFor('day'), const Duration(minutes: 15));
      expect(freshnessBudgetFor('checkpoint'), const Duration(minutes: 30));
      expect(freshnessBudgetFor('signals'), const Duration(minutes: 30));
      expect(freshnessBudgetFor('orientation'), const Duration(minutes: 30));
      expect(freshnessBudgetFor('vitals'), const Duration(minutes: 60));
      expect(freshnessBudgetFor('finance'), const Duration(hours: 24));
      expect(freshnessBudgetFor('october'), const Duration(hours: 24));
      expect(freshnessBudgetFor('anything else'), const Duration(hours: 6));
    });

    test('fresh: as of the fetch clock, no stale flag', () {
      final r = asOfFor(key: 'day', fetchedAt: DateTime(2026, 10, 16, 11, 50), now: now)!;
      expect(r.text, 'as of 11:50');
      expect(r.stale, isFalse);
    });

    test('past budget: stale with the age', () {
      final r = asOfFor(key: 'day', fetchedAt: DateTime(2026, 10, 16, 9, 0), now: now)!;
      expect(r.text, 'stale: 3 h');
      expect(r.stale, isTrue);
      expect(asOfFor(key: 'checkpoint', fetchedAt: DateTime(2026, 10, 16, 11, 0), now: now)!.text, 'stale: 1 h');
      expect(asOfFor(key: 'finance', fetchedAt: DateTime(2026, 10, 14, 11, 0), now: now)!.text, 'stale: 2 d');
    });

    test('a fresh fetch of an old source is stale: the 25 Sep tasks case', () {
      final r = asOfFor(key: 'checkpoint', fetchedAt: DateTime(2026, 10, 16, 11, 55), sourceDate: DateTime(2026, 9, 25), now: now)!;
      expect(r.text, 'source last changed 25 Sep');
      expect(r.stale, isTrue);
    });

    test('a plan dated another day is stale even when fetched a minute ago', () {
      final r = asOfFor(key: 'day', fetchedAt: DateTime(2026, 10, 16, 11, 59), sourceDate: DateTime(2026, 10, 15), now: now)!;
      expect(r.text, 'source last changed 15 Oct');
      expect(r.stale, isTrue);
      final today = asOfFor(key: 'day', fetchedAt: DateTime(2026, 10, 16, 11, 59), sourceDate: DateTime(2026, 10, 16), now: now)!;
      expect(today.stale, isFalse);
    });

    test('a source three days old is fine; nothing fetched yet gives no line', () {
      expect(asOfFor(key: 'checkpoint', fetchedAt: DateTime(2026, 10, 16, 11, 55), sourceDate: DateTime(2026, 10, 13), now: now)!.stale, isFalse);
      expect(asOfFor(key: 'day', fetchedAt: null, now: now), isNull);
    });
  });

  group('BI26101521: the line on screen', () {
    Future<void> pump(WidgetTester t, {required DateTime fetchedAt, DateTime? source, String key = 'checkpoint', VoidCallback? onTap}) =>
        t.pumpWidget(MaterialApp(
          home: Scaffold(
            body: AsOfText(snapshotKey: key, fetchedAt: fetchedAt, sourceDate: source, onTap: onTap, now: () => now),
          ),
        ));

    testWidgets('fresh is the quiet colour', (t) async {
      await pump(t, fetchedAt: DateTime(2026, 10, 16, 11, 50));
      final text = t.widget<Text>(find.text('as of 11:50'));
      expect(text.style?.color, C.text3);
    });

    testWidgets('past budget is amber with the age', (t) async {
      await pump(t, fetchedAt: DateTime(2026, 10, 16, 8, 0));
      final text = t.widget<Text>(find.text('stale: 4 h'));
      expect(text.style?.color, C.amber);
    });

    testWidgets('a stale source date is amber and says so', (t) async {
      await pump(t, fetchedAt: DateTime(2026, 10, 16, 11, 55), source: DateTime(2026, 9, 25));
      final text = t.widget<Text>(find.text('source last changed 25 Sep'));
      expect(text.style?.color, C.amber);
    });

    testWidgets('a tap runs the refresh', (t) async {
      var taps = 0;
      await pump(t, fetchedAt: DateTime(2026, 10, 16, 11, 50), onTap: () => taps++);
      await t.tap(find.byKey(const Key('as-of-checkpoint')));
      expect(taps, 1);
    });
  });
}
