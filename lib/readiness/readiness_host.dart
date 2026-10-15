import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_scope.dart';
import '../data/db.dart';
import '../services/alerts.dart';
import 'readiness_controller.dart';
import 'readiness_view.dart';

/// Kits and trips live in the app's own database, so they are there with no signal.
class DbReadinessStore implements ReadinessStore {
  DbReadinessStore(this._db);
  final AppDb _db;

  @override
  Future<Object?> read(String key) async => (await _db.getSnapshot(key))?.$1 as Object?;

  @override
  Future<void> write(String key, Object value) => _db.putSnapshot(key, value);
}

/// Reminders go through the app's local notifications, which fire from the
/// device clock.
class AlertReminderScheduler implements ReminderScheduler {
  @override
  Future<void> schedule({required int id, required String title, required String body, required DateTime when, String? payload}) =>
      AlertService.instance.scheduleAt(id: id, title: title, body: body, when: when, payload: payload);

  @override
  Future<void> cancel(int id) => AlertService.instance.cancelId(id);
}

/// One controller for the life of the app, so a reminder tapped from the
/// notification tray and the screen opened from the drawer share their state.
ReadinessController? _shared;

ReadinessController readinessController(AppServices services) =>
    _shared ??= ReadinessController(store: DbReadinessStore(services.db), scheduler: AlertReminderScheduler());

/// The Readiness screen inside the app shell.
class ReadinessHost extends StatelessWidget {
  const ReadinessHost({super.key, this.tripId});
  final String? tripId;

  @override
  Widget build(BuildContext context) {
    final c = readinessController(AppScope.of(context));
    return ReadinessView(
      controller: c,
      initialTripId: tripId,
      launch: (uri) async {
        try {
          return await launchUrl(uri, mode: LaunchMode.externalApplication);
        } catch (_) {
          return false;
        }
      },
    );
  }
}
