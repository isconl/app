/// BI26100138: keeps the Android home-screen widget's snapshot current.
///
/// Listens to the day blocks and the calendar, and whenever either changes (a sync, an offline edit, the app
/// coming to the foreground) rebuilds the snapshot and hands it to MainActivity, which stores it and redraws
/// the widget. Android only; a no-op everywhere else.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../app_scope.dart';
import 'home_widget_snapshot.dart';
import 'platform.dart';

class HomeWidgetBridge with WidgetsBindingObserver {
  HomeWidgetBridge._(this._services);

  static HomeWidgetBridge? _instance;

  /// The setting that hides item titles on the widget, kept in the snapshot store.
  static const hideTitlesKey = 'widget.hideTitles';

  final AppServices _services;
  Timer? _debounce;
  String? _lastJson;

  /// Starts the bridge once per app. Safe to call again.
  static void start(AppServices services) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android || _instance != null) return;
    final b = _instance = HomeWidgetBridge._(services);
    services.store.day.addListener(b.schedule);
    services.store.calendar.addListener(b.schedule);
    WidgetsBinding.instance.addObserver(b);
    // The calendar is not in every screen's path; make sure its cached copy is loaded for the widget.
    unawaited(services.store.calendar.hydrate());
    unawaited(services.store.day.hydrate());
    b.schedule();
  }

  /// Pushes a fresh snapshot now, for example after the hide-titles setting changes.
  static Future<void> refreshNow() async => _instance?._push();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed || state == AppLifecycleState.paused) schedule();
  }

  void schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), _push);
  }

  Future<void> _push() async {
    try {
      final hide = (await _services.db.getSnapshot(hideTitlesKey))?.$1 == true;
      final snap = buildWidgetSnapshot(
        day: _services.store.day.value,
        calendar: _services.store.calendar.value,
        now: DateTime.now(),
        hideTitles: hide,
      );
      // `written` changes every time; compare without it so an unchanged day doesn't redraw the widget.
      final key = jsonEncode({...snap, 'written': 0});
      if (key == _lastJson) return;
      _lastJson = key;
      await PlatformBridge.instance.updateWidget(jsonEncode(snap));
    } catch (_) {
      // The widget is a convenience; a failed refresh shows the previous snapshot.
    }
  }
}
