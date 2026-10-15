import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/readiness/readiness_controller.dart';
import 'package:isconl/readiness/readiness_model.dart';
import 'package:isconl/readiness/readiness_view.dart';

class MemStore implements ReadinessStore {
  final data = <String, Object>{};
  @override
  Future<Object?> read(String key) async => data[key];
  @override
  Future<void> write(String key, Object value) async => data[key] = value;
}

class Scheduled {
  Scheduled(this.id, this.title, this.body, this.when, this.payload);
  final int id;
  final String title;
  final String body;
  final DateTime when;
  final String? payload;
}

class FakeScheduler implements ReminderScheduler {
  final live = <int, Scheduled>{};
  @override
  Future<void> schedule({required int id, required String title, required String body, required DateTime when, String? payload}) async =>
      live[id] = Scheduled(id, title, body, when, payload);
  @override
  Future<void> cancel(int id) async => live.remove(id);
}

final _t0 = DateTime(2026, 10, 15, 8);

ReadinessController _c([MemStore? s, FakeScheduler? sch, DateTime Function()? now]) =>
    ReadinessController(store: s ?? MemStore(), scheduler: sch ?? FakeScheduler(), now: now ?? () => _t0);

void main() {
  group('model', () {
    test('a reminder is 14 days before expiry at 09:00', () {
      final i = KitItem(id: 'a', name: 'ORS', expiry: DateTime(2026, 12, 31));
      expect(i.reminderAt, DateTime(2026, 12, 17, 9));
      expect(KitItem(id: 'b', name: 'Rope').reminderAt, isNull);
    });

    test('attention means within 14 days or already expired', () {
      final i = KitItem(id: 'a', name: 'ORS', expiry: DateTime(2026, 10, 29));
      expect(i.daysLeft(_t0), 14);
      expect(i.needsAttention(_t0), isTrue);
      expect(KitItem(id: 'b', name: 'x', expiry: DateTime(2026, 10, 30)).needsAttention(_t0), isFalse);
      expect(KitItem(id: 'c', name: 'x', expiry: DateTime(2026, 10, 1)).daysLeft(_t0), -14);
    });

    test('a trip is overdue only after its alarm time and while not back', () {
      final t = Trip(id: 't', where: 'Mt Kenya', start: _t0, returnBy: _t0.add(const Duration(hours: 8)), alarmAt: _t0.add(const Duration(hours: 9)));
      expect(t.isOverdue(_t0.add(const Duration(hours: 9))), isFalse);
      expect(t.isOverdue(_t0.add(const Duration(hours: 9, minutes: 1))), isTrue);
      t.backAt = _t0.add(const Duration(hours: 10));
      expect(t.isOverdue(_t0.add(const Duration(days: 2))), isFalse);
    });

    test('the share message carries where, when, the alarm time and the contact', () {
      final t = Trip(
        id: 't', where: 'Mt Kenya', who: 'Sconl and Amina', start: DateTime(2026, 10, 16, 6), returnBy: DateTime(2026, 10, 17, 16),
        alarmAt: DateTime(2026, 10, 17, 18), callWho: 'Mountain rescue +254700000000', notes: 'Sirimon route',
      );
      final m = t.message();
      expect(m, contains('Trip card: Mt Kenya'));
      expect(m, contains('Who: Sconl and Amina'));
      expect(m, contains('Leaving: 16 Oct 06:00'));
      expect(m, contains('raise the alarm'));
      expect(m, contains('Mountain rescue +254700000000'));
      expect(m, contains('Sirimon route'));
    });

    test('whatsapp link needs a usable number and encodes the text', () {
      expect(whatsappLink('abc', 'hi'), isNull);
      final u = whatsappLink('+254 700 000 000', 'Back by 5 & safe')!;
      expect(u.host, 'wa.me');
      expect(u.path, '/254700000000');
      expect(u.queryParameters['text'], 'Back by 5 & safe');
    });

    test('trips and kits survive a round trip through JSON', () {
      final t = Trip(id: 't', where: 'Coast', start: DateTime(2026, 10, 16, 6), returnBy: DateTime(2026, 10, 16, 18), alarmAt: DateTime(2026, 10, 16, 19), sharePhone: '+254711');
      final back = Trip.fromJson(t.toJson())!;
      expect(back.where, 'Coast');
      expect(back.alarmAt, t.alarmAt);
      expect(back.sharePhone, '+254711');
      final k = Kit(id: 'trek', name: 'Trek', items: [KitItem(id: 'i', name: 'ORS', packed: true, expiry: DateTime(2027, 1, 5))]);
      final kb = Kit.fromJson(k.toJson())!;
      expect(kb.items.single.packed, isTrue);
      expect(kb.items.single.expiry, DateTime(2027, 1, 5));
      expect(Trip.fromJson({'id': ''}), isNull);
    });

    test('templates fill the place only, never a phone number', () {
      for (final t in tripTemplates) {
        expect(RegExp(r'\d{6,}').hasMatch('${t.where} ${t.hint}'), isFalse);
      }
    });
  });

  group('controller', () {
    test('three kits start empty; adding an item with an expiry schedules its reminder', () async {
      final sch = FakeScheduler();
      final c = _c(null, sch);
      await c.load();
      expect(c.kits.map((k) => k.id), ['trek', 'carry', 'house']);
      expect(c.kits.every((k) => k.items.isEmpty), isTrue);
      await c.addItem('trek', 'Water tablets', expiry: DateTime(2027, 3, 31));
      final item = c.kit('trek').items.single;
      final s = sch.live[itemReminderId(item.id)]!;
      expect(s.when, DateTime(2027, 3, 17, 9));
      expect(s.title, 'Water tablets expires soon');
      await c.setExpiry('trek', item.id, null);
      expect(sch.live, isEmpty);
    });

    test('an item already inside its window reminds in a minute, an expired one says so', () async {
      final sch = FakeScheduler();
      final c = _c(null, sch);
      await c.load();
      await c.addItem('carry', 'Batteries', expiry: DateTime(2026, 10, 20));
      final s = sch.live.values.single;
      expect(s.when, _t0.add(const Duration(minutes: 1)));
      await c.addItem('carry', 'Old ORS', expiry: DateTime(2026, 10, 1));
      expect(sch.live.values.any((x) => x.body.contains('has expired')), isTrue);
      expect(c.attention.first.item.name, 'Old ORS'); // soonest first
    });

    test('a trip created offline schedules the nudge at its alarm time, and "I am back" cancels it', () async {
      final sch = FakeScheduler();
      final c = _c(null, sch);
      await c.load();
      final t = await c.createTrip(where: 'Mt Kenya', start: DateTime(2026, 10, 16, 6), returnBy: DateTime(2026, 10, 17, 16));
      final n = sch.live[tripAlarmId(t.id)]!;
      expect(n.when, DateTime(2026, 10, 17, 17)); // an hour after the planned return by default
      expect(n.payload, 'trip:${t.id}');
      await c.markBack(t.id);
      expect(sch.live, isEmpty);
      expect(c.trip(t.id).isBack, isTrue);
    });

    test('everything is saved and rescheduled after a restart', () async {
      final store = MemStore();
      final c1 = _c(store);
      await c1.load();
      await c1.addItem('house', 'Torch', expiry: DateTime(2027, 6, 1));
      await c1.createTrip(where: 'Coast', start: DateTime(2026, 10, 16, 6), returnBy: DateTime(2026, 10, 16, 18));
      final sch = FakeScheduler();
      final c2 = _c(store, sch);
      await c2.load();
      expect(c2.kit('house').items.single.name, 'Torch');
      expect(c2.trips.single.where, 'Coast');
      expect(sch.live.length, 2);
    });

    test('sharing needs a number, records the time, and the overdue text differs', () async {
      final c = _c();
      await c.load();
      final t = await c.createTrip(where: 'Coast', start: DateTime(2026, 10, 16, 6), returnBy: DateTime(2026, 10, 16, 18));
      expect(await c.share(t.id), isNull);
      expect(c.trip(t.id).sharedAt, isNull);
      c.trip(t.id).sharePhone = '+254700111222';
      final u = await c.share(t.id);
      expect(u!.queryParameters['text'], contains('Trip card: Coast'));
      expect(c.trip(t.id).sharedAt, isNotNull);
      final o = await c.share(t.id, overdue: true);
      expect(o!.queryParameters['text'], contains('I am overdue'));
    });

    test('notification ids are stable across runs', () {
      expect(itemReminderId('trek_1'), itemReminderId('trek_1'));
      expect(itemReminderId('trek_1'), inInclusiveRange(20000, 39999));
      expect(tripAlarmId('trip_1'), inInclusiveRange(40000, 49999));
    });
  });

  group('screens', () {
    Widget host(ReadinessController c, {List<Uri>? opened, bool ok = true, DateTime Function()? now}) => MaterialApp(
          home: Scaffold(
            body: ReadinessView(
              controller: c,
              now: now ?? () => _t0,
              launch: (u) async {
                opened?.add(u);
                return ok;
              },
              pickDateTime: (ctx, initial) async => initial,
              pickDate: (ctx, initial) async => DateTime(2027, 1, 20),
            ),
          ),
        );

    testWidgets('three kits, add an item with an expiry, tick it packed', (t) async {
      final c = _c();
      await t.pumpWidget(host(c));
      await t.pumpAndSettle();
      expect(find.text('Trek pack'), findsOneWidget);
      expect(find.text('Everyday carry and car kit'), findsOneWidget);
      expect(find.text('House kit'), findsOneWidget);
      await t.tap(find.byKey(const Key('add-trek')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('item-name')), 'ORS sachets');
      await t.tap(find.byKey(const Key('item-expiry')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('item-save')));
      await t.pumpAndSettle();
      expect(find.text('ORS sachets'), findsOneWidget);
      expect(find.textContaining('Expires 20 Jan 2027'), findsOneWidget);
      final item = c.kit('trek').items.single;
      await t.tap(find.byKey(Key('item-${item.id}')));
      await t.pumpAndSettle();
      expect(c.kit('trek').items.single.packed, isTrue);
      expect(find.text('1 of 1 packed'), findsOneWidget);
    });

    testWidgets('a perishable inside 14 days shows the attention box', (t) async {
      final c = _c();
      await c.load();
      await c.addItem('house', 'Torch batteries', expiry: DateTime(2026, 10, 25));
      await t.pumpWidget(host(c));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('kit-attention')), findsOneWidget);
      expect(find.textContaining('Torch batteries (House kit) expires in 10 days'), findsOneWidget);
    });

    testWidgets('a trip card is made from a template, saved, and shared by WhatsApp', (t) async {
      await t.binding.setSurfaceSize(const Size(420, 1600));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final c = _c();
      final opened = <Uri>[];
      await t.pumpWidget(host(c, opened: opened));
      await t.pumpAndSettle();
      await t.tap(find.text('Trips'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('new-trip')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('template-Mt Kenya')));
      await t.pump();
      expect(find.byKey(const Key('template-hint')), findsOneWidget);
      await t.enterText(find.byKey(const Key('trip-call')), 'Mountain rescue +254700000000');
      await t.enterText(find.byKey(const Key('trip-phone')), '+254711222333');
      await t.ensureVisible(find.byKey(const Key('trip-save')));
      await t.tap(find.byKey(const Key('trip-save')));
      await t.pumpAndSettle();
      expect(c.trips.single.where, 'Mt Kenya');
      await t.tap(find.byKey(Key('trip-${c.trips.single.id}')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('share-trip')));
      await t.pumpAndSettle();
      expect(opened.single.host, 'wa.me');
      expect(opened.single.queryParameters['text'], contains('Mountain rescue +254700000000'));
      expect(find.textContaining('Shared'), findsWidgets);
    });

    testWidgets('a trip with no number says so instead of opening nothing', (t) async {
      final c = _c();
      await c.load();
      final trip = await c.createTrip(where: 'Coast', start: DateTime(2026, 10, 16, 6), returnBy: DateTime(2026, 10, 16, 18));
      await t.pumpWidget(MaterialApp(home: TripScreen(controller: c, tripId: trip.id, launch: (_) async => true, now: () => _t0)));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('share-trip')));
      await t.pumpAndSettle();
      expect(find.text('Add a WhatsApp number to this trip first.'), findsOneWidget);
    });

    testWidgets('past the alarm time the overdue banner offers the resend; I am back clears it', (t) async {
      final c = _c();
      await c.load();
      final trip = await c.createTrip(where: 'Mt Kenya', start: DateTime(2026, 10, 16, 6), returnBy: DateTime(2026, 10, 16, 18), sharePhone: '+254700111222');
      final late = DateTime(2026, 10, 16, 20);
      final opened = <Uri>[];
      await t.pumpWidget(MaterialApp(
        home: TripScreen(controller: c, tripId: trip.id, launch: (u) async {
          opened.add(u);
          return true;
        }, now: () => late),
      ));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('overdue-banner')), findsOneWidget);
      await t.ensureVisible(find.byKey(const Key('resend-overdue')));
      await t.tap(find.byKey(const Key('resend-overdue')));
      await t.pumpAndSettle();
      expect(opened.single.queryParameters['text'], contains('I am overdue'));
      await t.ensureVisible(find.byKey(const Key('im-back')));
      await t.tap(find.byKey(const Key('im-back')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('overdue-banner')), findsNothing);
      expect(find.byKey(const Key('back-safe')), findsOneWidget);
    });

    testWidgets('the return time must be after the start', (t) async {
      await t.binding.setSurfaceSize(const Size(420, 1600));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final c = _c();
      await t.pumpWidget(MaterialApp(
        home: NewTripScreen(controller: c, pickDateTime: (ctx, i) async => DateTime(2020), now: () => _t0),
      ));
      await t.enterText(find.byKey(const Key('trip-where')), 'Somewhere');
      await t.tap(find.byKey(const Key('trip-return')));
      await t.pump();
      await t.ensureVisible(find.byKey(const Key('trip-save')));
      await t.tap(find.byKey(const Key('trip-save')));
      await t.pump();
      expect(find.byKey(const Key('trip-error')), findsOneWidget);
      expect(c.trips, isEmpty);
    });
  });
}
