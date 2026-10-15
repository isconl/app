import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

import '../util/fmt.dart' as fmt;

/// BI26100138: what the Android home-screen widget shows, built here and handed to the native side as one small
/// JSON string. The widget never calls the network.
///
/// Privacy, enforced in [buildWidgetSnapshot] and not left to the widget: a task tagged finance, health or similar is
/// never the "next item", no message content is read, and a setting can hide the next item's title altogether
/// (a widget cannot tell whether the screen is locked, so "hide" means always).
class WidgetSnapshot {
  const WidgetSnapshot({this.block = '', this.blockLeft = '', this.next = '', this.asOf = ''});
  final String block;
  final String blockLeft;
  final String next;
  final String asOf;

  Map<String, String> toJson() => {'block': block, 'blockLeft': blockLeft, 'next': next, 'asOf': asOf};
}

/// Tags whose tasks never appear on the widget.
const widgetPrivateTags = {'finance', 'money', 'health', 'medical', 'vitals', 'therapy', 'tax', 'bank'};

bool _isPrivate(Map<String, dynamic> t) {
  final tag = fmt.s(t['TAG']).toLowerCase();
  return widgetPrivateTags.contains(tag);
}

String _clock(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

int? _minutes(String hhmm) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(hhmm.trim());
  return m == null ? null : int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
}

/// The current block and the next item due, from the day plan and the task list.
WidgetSnapshot buildWidgetSnapshot({
  required Map<String, dynamic> day,
  required List<Map<String, dynamic>> tasks,
  required DateTime now,
  bool hideNext = false,
}) {
  final blocks = fmt.lm(day['blocks']);
  final currentId = fmt.s(day['currentId'] ?? fmt.m(day['now'])['id']);
  Map<String, dynamic>? current;
  for (final b in blocks) {
    if (currentId.isNotEmpty && fmt.s(b['id']) == currentId) current = b;
  }

  var blockName = '';
  var left = '';
  if (current != null) {
    blockName = fmt.s(current['name']);
    final end = _minutes(fmt.s(current['endClock']));
    if (end != null) {
      final mins = end - (now.hour * 60 + now.minute);
      left = mins <= 0 ? 'ending now' : (mins >= 60 ? '${mins ~/ 60} h ${mins % 60} min left' : '$mins min left');
    }
  }

  final today = fmt.isoDate(now);
  String? bestDue;
  String bestTitle = '';
  for (final t in tasks) {
    final status = fmt.s(t['STATUS']).toLowerCase();
    if (status == 'done' || status == 'archived' || status == 'deleted') continue;
    if (_isPrivate(t)) continue;
    final due = fmt.s(t['DUE_DATE']);
    if (due.isEmpty || due == '-' || due.compareTo(today) < 0) continue;
    if (bestDue == null || due.compareTo(bestDue) < 0) {
      bestDue = due;
      bestTitle = fmt.s(t['TITLE']);
    }
  }
  var next = '';
  if (bestDue != null) {
    final when = bestDue == today ? 'today' : bestDue;
    next = hideNext ? 'An item is due $when' : '$bestTitle, due $when';
  }

  return WidgetSnapshot(block: blockName, blockLeft: left, next: next, asOf: _clock(now));
}

/// Hands the snapshot to the native widget. A no-op off Android and when the channel is missing.
class HomeWidgetBridge {
  HomeWidgetBridge._();
  static final HomeWidgetBridge instance = HomeWidgetBridge._();
  static const _channel = MethodChannel('isconl/platform');

  String _last = '';

  /// Forces the next [push] to write even if nothing but the time changed.
  void forget() => _last = '';

  Future<void> push(WidgetSnapshot s) async {
    if (kIsWeb) return;
    final json = jsonEncode(s.toJson());
    // asOf changes every minute; skip a write when only that changed.
    final key = jsonEncode({...s.toJson(), 'asOf': ''});
    if (key == _last) return;
    try {
      await _channel.invokeMethod<bool>('updateWidget', {'json': json});
      _last = key;
    } catch (_) {
      // No widget host (desktop, tests): nothing to update.
    }
  }

  /// "capture", "voice" or "today" when the app was opened from the widget or a shortcut (cold start).
  Future<String?> pendingAction() async {
    if (kIsWeb) return null;
    try {
      return await _channel.invokeMethod<String>('getWidgetAction');
    } catch (_) {
      return null;
    }
  }
}
