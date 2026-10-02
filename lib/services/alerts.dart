import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../util/fmt.dart' as fmt;

/// System notifications for high-severity agent alerts discovered on sync.
/// No web implementation is registered for this plugin, so it stays quietly
/// unready there rather than throwing into main.dart's fire-and-forget init().
class AlertService {
  AlertService._();
  static final AlertService instance = AlertService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> init() async {
    if (_ready || kIsWeb) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
        const InitializationSettings(android: android));
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
      );
    }
  }
}
