import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../util/fmt.dart' as fmt;

/// System notifications for high-severity agent alerts discovered on sync.
/// No web implementation is registered for this plugin, so it stays quietly
/// unready there rather than throwing into main.dart's fire-and-forget init().
class AlertService {
  AlertService._();
  static final AlertService instance = AlertService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// BI26100143: opens the Day close screen when its notification is tapped.
  void Function()? onDayClose;
  static const dayClosePayload = 'day-close';

  /// cx canon section 3: a read-grant request opens the approval sheet. Payload is cx-grant:<id>.
  void Function(String id)? onGrant;
  static const grantPayloadPrefix = 'cx-grant:';

  /// BI26100707: a missed check-in nudge opens that trip card. Payload is `trip:` plus the trip id.
  void Function(String id)? onTrip;
  static const tripPayloadPrefix = 'trip:';
  static const _dayCloseBase = 9100;
  static const _dayCloseSlots = 16;

  Future<void> init() async {
    if (_ready || kIsWeb) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    tzdata.initializeTimeZones();
    await _plugin.initialize(
      const InitializationSettings(android: android),
      onDidReceiveNotificationResponse: (r) {
        if (r.payload == dayClosePayload) onDayClose?.call();
        final p = r.payload ?? '';
        if (p.startsWith(grantPayloadPrefix)) onGrant?.call(p.substring(grantPayloadPrefix.length));
        if (p.startsWith(tripPayloadPrefix)) onTrip?.call(p.substring(tripPayloadPrefix.length));
      },
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    _ready = true;
  }

  Future<void> showAgentAlerts(List<Map<String, dynamic>> fresh) async {
    if (!_ready) return;
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'isconl_alerts',
        'Agent alerts',
        channelDescription: 'High-priority notices from the iSconl agent',
        importance: Importance.high,
        priority: Priority.high,
        color: Color.fromARGB(255, 0x3F, 0xB9, 0x50),
      ),
    );
    for (final n in fresh.take(3)) {
      final id = fmt.s(n['ID']).hashCode & 0x7fffffff;
      await _plugin.show(
        id,
        fmt.s(n['TITLE']).isEmpty ? 'iSconl' : fmt.s(n['TITLE']),
        fmt.truncate(fmt.s(n['BODY']), 180),
        details,
        payload: fmt.s(n['KIND']) == 'cx_grant' ? '$grantPayloadPrefix${fmt.s(n['GRANT_ID'])}' : null,
      );
    }
  }

  /// BI26100143: one notification per day at the review time for the next
  /// few days (rescheduled whenever the settings or the counts change). Each
  /// is a one-shot so a skipped weekend is simply not scheduled.
  Future<void> scheduleDayClose(List<DateTime> times, String body) async {
    if (!_ready) return;
    for (var i = 0; i < _dayCloseSlots; i++) {
      await _plugin.cancel(_dayCloseBase + i);
    }
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'isconl_dayclose',
        'Day close',
        channelDescription: 'The end-of-day review',
        importance: Importance.defaultImportance,
        color: Color.fromARGB(255, 0x3F, 0xB9, 0x50),
      ),
    );
    var i = 0;
    for (final t in times.take(_dayCloseSlots)) {
      await _plugin.zonedSchedule(
        _dayCloseBase + i++,
        'Close the day',
        body,
        tz.TZDateTime.from(t, tz.UTC),
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: dayClosePayload,
      );
    }
  }

  /// BI26100707: one local notification at [when] on the device clock, so a kit
  /// expiry reminder or a missed check-in nudge needs no signal. Scheduling the
  /// same [id] again replaces the earlier one.
  Future<void> scheduleAt({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
  }) async {
    if (!_ready) return;
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'isconl_readiness',
        'Readiness',
        channelDescription: 'Kit expiry reminders and missed check-in nudges',
        importance: Importance.max,
        priority: Priority.high,
        color: Color.fromARGB(255, 0xD2, 0x99, 0x22),
      ),
    );
    await _plugin.cancel(id);
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(when, tz.UTC),
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: payload,
    );
  }

  Future<void> cancelId(int id) async {
    if (!_ready) return;
    await _plugin.cancel(id);
  }

  Future<void> cancelDayClose() async {
    if (!_ready) return;
    for (var i = 0; i < _dayCloseSlots; i++) {
      await _plugin.cancel(_dayCloseBase + i);
    }
  }
}
