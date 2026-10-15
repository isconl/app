import 'package:flutter/foundation.dart';

import 'readiness_model.dart';

/// Where kits and trips are kept (the app's own database).
abstract class ReadinessStore {
  Future<Object?> read(String key);
  Future<void> write(String key, Object value);
}

/// Schedules the local notifications. The real one is backed by
/// flutter_local_notifications and fires from the device clock, so it needs no
/// signal; tests record the calls.
abstract class ReminderScheduler {
  Future<void> schedule({required int id, required String title, required String body, required DateTime when, String? payload});
  Future<void> cancel(int id);
}

/// A small FNV-1a hash, so an item or trip id always maps to the same
/// notification id (Dart's String.hashCode is not stable across runs).
int stableId(String s, {required int base, required int range}) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0x7fffffff;
  }
  return base + h % range;
}

int itemReminderId(String itemId) => stableId(itemId, base: 20000, range: 20000);
int tripAlarmId(String tripId) => stableId(tripId, base: 40000, range: 10000);

/// The state behind the Readiness screens: three kits and the trip cards, with
/// every change saved at once and every reminder rescheduled from it.
class ReadinessController extends ChangeNotifier {
  ReadinessController({required ReadinessStore store, required ReminderScheduler scheduler, DateTime Function()? now})
      : _store = store,
        _scheduler = scheduler,
        _now = now ?? DateTime.now;

  final ReadinessStore _store;
  final ReminderScheduler _scheduler;
  final DateTime Function() _now;

  static const _kitsKey = 'readiness.kits.v1';
  static const _tripsKey = 'readiness.trips.v1';

  List<Kit> kits = defaultKits();
  List<Trip> trips = [];
  bool loaded = false;

  Future<void> load() async {
    try {
      final k = await _store.read(_kitsKey);
      if (k is List) {
        final parsed = [for (final e in k) if (Kit.fromJson(e) case final kit?) kit];
        // Keep the three kits even if an older save lacked one.
        final byId = {for (final x in parsed) x.id: x};
        kits = [for (final d in defaultKits()) byId[d.id] ?? d];
      }
      final t = await _store.read(_tripsKey);
      if (t is List) trips = [for (final e in t) if (Trip.fromJson(e) case final trip?) trip];
    } catch (_) {
      // Nothing saved yet, or unreadable: start with the defaults.
    }
    loaded = true;
    notifyListeners();
    await rescheduleAll();
  }

  Future<void> _saveKits() => _store.write(_kitsKey, [for (final k in kits) k.toJson()]);
  Future<void> _saveTrips() => _store.write(_tripsKey, [for (final t in trips) t.toJson()]);

  Kit kit(String id) => kits.firstWhere((k) => k.id == id);

  // ---- kits ----

  Future<void> addItem(String kitId, String name, {DateTime? expiry}) async {
    final n = name.trim();
    if (n.isEmpty) return;
    final item = KitItem(id: '${kitId}_${_now().microsecondsSinceEpoch}', name: n, expiry: expiry);
    kit(kitId).items.add(item);
    await _saveKits();
    await _scheduleItem(item);
    notifyListeners();
  }

  Future<void> setPacked(String kitId, String itemId, bool packed) async {
    kit(kitId).items.firstWhere((i) => i.id == itemId).packed = packed;
    await _saveKits();
    notifyListeners();
  }

  Future<void> setExpiry(String kitId, String itemId, DateTime? expiry) async {
    final item = kit(kitId).items.firstWhere((i) => i.id == itemId);
    item.expiry = expiry;
    await _saveKits();
    await _scheduleItem(item);
    notifyListeners();
  }

  Future<void> removeItem(String kitId, String itemId) async {
    kit(kitId).items.removeWhere((i) => i.id == itemId);
    await _saveKits();
    await _scheduler.cancel(itemReminderId(itemId));
    notifyListeners();
  }

  /// Everything that has expired or expires within 14 days, soonest first.
  List<({Kit kit, KitItem item, int days})> get attention {
    final now = _now();
    final out = <({Kit kit, KitItem item, int days})>[];
    for (final k in kits) {
      for (final i in k.items) {
        if (i.needsAttention(now)) out.add((kit: k, item: i, days: i.daysLeft(now)!));
      }
    }
    out.sort((a, b) => a.days.compareTo(b.days));
    return out;
  }

  Future<void> _scheduleItem(KitItem item) async {
    final id = itemReminderId(item.id);
    final at = item.reminderAt;
    if (at == null) {
      await _scheduler.cancel(id);
      return;
    }
    // A reminder already in the past would never fire; if the item is inside its
    // window today, remind in a minute so the reader is not left unwarned.
    final now = _now();
    final when = at.isAfter(now) ? at : (item.needsAttention(now) ? now.add(const Duration(minutes: 1)) : null);
    if (when == null) {
      await _scheduler.cancel(id);
      return;
    }
    await _scheduler.schedule(
      id: id,
      title: '${item.name} expires soon',
      body: item.daysLeft(now)! < 0
          ? '${item.name} has expired. Replace it before your next trip.'
          : '${item.name} expires on ${formatDate(item.expiry!)}. Replace it in time.',
      when: when,
      payload: 'readiness:kits',
    );
  }

  // ---- trips ----

  Future<Trip> createTrip({
    required String where,
    String who = '',
    required DateTime start,
    required DateTime returnBy,
    DateTime? alarmAt,
    String callWho = '',
    String notes = '',
    String sharePhone = '',
  }) async {
    final trip = Trip(
      id: 'trip_${_now().microsecondsSinceEpoch}',
      where: where.trim(),
      who: who.trim(),
      start: start,
      returnBy: returnBy,
      // Default: an hour after the planned return.
      alarmAt: alarmAt ?? returnBy.add(const Duration(hours: 1)),
      callWho: callWho,
      notes: notes,
      sharePhone: sharePhone,
    );
    trips.insert(0, trip);
    await _saveTrips();
    await _scheduleTrip(trip);
    notifyListeners();
    return trip;
  }

  Trip trip(String id) => trips.firstWhere((t) => t.id == id);

  Future<void> update(Trip t) async {
    await _saveTrips();
    await _scheduleTrip(t);
    notifyListeners();
  }

  /// "I'm back": the alarm is cancelled and the trip is closed.
  Future<void> markBack(String id) async {
    final t = trip(id);
    t.backAt = _now();
    await _saveTrips();
    await _scheduler.cancel(tripAlarmId(id));
    notifyListeners();
  }

  /// Records that the card was shared (the reader pressed Share) and returns the
  /// WhatsApp link, or null if the trip has no usable number.
  Future<Uri?> share(String id, {bool overdue = false}) async {
    final t = trip(id);
    final msg = overdue ? t.overdueMessage(_now()) : t.message();
    final link = whatsappLink(t.sharePhone, msg);
    if (link != null) {
      t.sharedAt = _now();
      await _saveTrips();
      notifyListeners();
    }
    return link;
  }

  Future<void> deleteTrip(String id) async {
    trips.removeWhere((t) => t.id == id);
    await _saveTrips();
    await _scheduler.cancel(tripAlarmId(id));
    notifyListeners();
  }

  Future<void> _scheduleTrip(Trip t) async {
    final id = tripAlarmId(t.id);
    if (t.isBack || !t.alarmAt.isAfter(_now())) {
      await _scheduler.cancel(id);
      return;
    }
    await _scheduler.schedule(
      id: id,
      title: 'Not back yet: ${t.where}',
      body: 'You have not checked in. Tap to send your contact the message.',
      when: t.alarmAt,
      payload: 'trip:${t.id}',
    );
  }

  /// After a restart: every reminder is set again from what is saved, because
  /// scheduled notifications do not always survive a reboot.
  Future<void> rescheduleAll() async {
    for (final k in kits) {
      for (final i in k.items) {
        await _scheduleItem(i);
      }
    }
    for (final t in trips) {
      await _scheduleTrip(t);
    }
  }
}
