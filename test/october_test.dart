import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/services/october.dart';
import 'package:isconl/ui/widgets/october_ring_card.dart';

class FakeOctober implements OctoberApi {
  FakeOctober(this.json);
  Object? json;
  int calls = 0;
  @override
  Future<OctoberProgress> progress() async {
    calls++;
    return OctoberProgress.parse(json);
  }
}

Map<String, dynamic> feed({int day = 15, String last = '2026-10-14T20:00:00Z', double next = 8}) => {
      'available': true,
      'total_gb': 100,
      'migrated_gb': {'working': 20, 'vault': 10, 'archive_cold': 18},
      'duplicates_removed_gb': 6,
      'folders_decided': 31,
      'folders_total': 57,
      'chunks_done': 6,
      'last_chunk_at': last,
      'day_n': day,
      'days_total': 28,
      'next_chunk': {'gb': next, 'minutes_estimate': 25},
    };

void main() {
  test('parse: counts, share and the line', () {
    final p = OctoberProgress.parse(feed());
    expect(p.movedGb, 48);
    expect(p.share, closeTo(0.48, 1e-9));
    expect(p.line, '48 GB moved · 6 GB of duplicates gone · 31 of 57 folders decided');
    expect(OctoberProgress.parse({'available': false}).available, false);
    expect(OctoberProgress.parse(null).available, false);
  });

  test('nudge only after two days without a chunk, never after the month', () {
    final now = DateTime.utc(2026, 10, 16, 21);
    expect(OctoberProgress.parse(feed()).needsChunk(now), true);
    expect(OctoberProgress.parse(feed(last: '2026-10-16T12:00:00Z')).needsChunk(now), false);
    expect(OctoberProgress.parse(feed(day: 30)).needsChunk(now), false);
    expect(OctoberProgress.parse(feed(next: 0)).needsChunk(now), false);
  });

  testWidgets('shows the ring, the day from the feed and the line', (t) async {
    final api = FakeOctober(feed());
    await t.pumpWidget(MaterialApp(home: Scaffold(body: OctoberRingCard(api: api, poll: false, now: () => DateTime.utc(2026, 10, 15, 9)))));
    await t.pumpAndSettle();
    expect(find.text('Day 15 of 28'), findsOneWidget);
    expect(find.textContaining('48 GB moved'), findsOneWidget);
    expect(find.byKey(const Key('october-next')), findsNothing);
  });

  testWidgets('hides with no feed, and shows the summary after the last day', (t) async {
    final api = FakeOctober({'available': false});
    await t.pumpWidget(MaterialApp(home: Scaffold(body: OctoberRingCard(api: api, poll: false))));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('october-ring')), findsNothing);
    api.json = feed(day: 29);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: OctoberRingCard(key: const Key('again'), api: api, poll: false))));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('october-summary')), findsOneWidget);
    expect(find.textContaining('Before: 100 GB'), findsOneWidget);
  });

  testWidgets('polls every five minutes', (t) async {
    final api = FakeOctober(feed());
    await t.pumpWidget(MaterialApp(home: Scaffold(body: OctoberRingCard(api: api))));
    await t.pump();
    expect(api.calls, 1);
    await t.pump(const Duration(minutes: 5, seconds: 1));
    expect(api.calls, 2);
    api.json = feed(day: 16);
    await t.pump(const Duration(minutes: 5));
    await t.pump();
    expect(find.text('Day 16 of 28'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}
