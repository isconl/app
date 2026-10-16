import 'dart:async';
import 'dart:io' show Platform;

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:workmanager/workmanager.dart';

import '../api/client.dart';
import '../app_scope.dart';
import '../data/db.dart';
import '../data/modules.dart';
import '../data/store.dart';
import '../util/fmt.dart' as fmt;
import 'alerts.dart';
import 'close_feed.dart';
import 'prefetch.dart';
import 'session.dart';

/// BI26100140: the periodic background task and the foreground trigger around
/// [Prefetcher]. Android only; the web build and desktop do nothing.
const prefetchUniqueName = 'isconl.prefetch.periodic';
const prefetchTaskName = 'isconl.prefetch';

bool get _supported => !kIsWeb && Platform.isAndroid;

Future<bool> _warm(String url) async {
  try {
    await DefaultCacheManager().downloadFile(url);
    return true;
  } catch (_) {
    return false;
  }
}

List<Map<String, dynamic>> _coursesOf(dynamic learning) => fmt.lm(fmt.m(learning)['courses']);

/// True on an unmetered connection (Wi-Fi or ethernet) with the phone charging.
Future<bool> wifiAndCharging() async {
  try {
    final net = await Connectivity().checkConnectivity();
    final unmetered = net.contains(ConnectivityResult.wifi) || net.contains(ConnectivityResult.ethernet);
    if (!unmetered) return false;
    final s = await Battery().batteryState;
    return s == BatteryState.charging || s == BatteryState.full;
  } catch (_) {
    return false;
  }
}

/// The background entry point WorkManager starts in a fresh isolate. Its
/// constraints (unmetered network, charging) are enforced by Android before it
/// runs, so the gate here is a formality.
@pragma('vm:entry-point')
void prefetchDispatcher() {
  Workmanager().executeTask((task, input) async {
    // BI26101529: WorkManager has one dispatcher per app, so the slate-close poll shares this one.
    if (task == closeFeedTaskName) return runCloseFeedBackground();
    try {
      final db = await AppDb.open();
      final session = SessionService();
      await session.load();
      ApiClient apiOf() => session.api;
      final store = Store(db, apiOf);
      final modules = ModuleLibrary(db, store, apiOf);
      await modules.load();
      await store.learning.refresh();
      await Prefetcher(
        modules: LibraryPrefetchModules(modules),
        courses: () async => _coursesOf(store.learning.value),
        store: DbPrefetchStore(db),
        onUnmeteredAndCharging: wifiAndCharging,
        baseUrl: () => apiOf().baseUrl,
        token: () => apiOf().token,
        warmImage: _warm,
      ).run();
    } catch (_) {
      // Swallowed on purpose: the next period tries again, and a thrown error
      // here would only make WorkManager retry in a tight loop.
    }
    return true;
  });
}

/// Registers the background task when prefetch is on, and cancels it when it is off.
/// Call once at start and whenever the toggle changes.
Future<void> syncPrefetchSchedule(PrefetchSettings settings) async {
  if (!_supported) return;
  try {
    final wm = Workmanager();
    await wm.initialize(prefetchDispatcher);
    if (settings.enabled) {
      await wm.registerPeriodicTask(
        prefetchUniqueName,
        prefetchTaskName,
        frequency: const Duration(hours: 6),
        constraints: Constraints(networkType: NetworkType.unmetered, requiresCharging: true),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      );
    } else {
      await wm.cancelByUniqueName(prefetchUniqueName);
    }
  } catch (_) {
    // No WorkManager (tests, unsupported device): the foreground pass still works.
  }
}

/// BI26101529: the background poll of the slate close feed, every 15 minutes (Android's minimum) on any
/// network. On when the "Slate closes" switch is on, cancelled when it is off.
const closeFeedUniqueName = 'isconl.closefeed.periodic';
const closeFeedTaskName = 'isconl.closefeed';

Future<void> syncCloseFeedSchedule(bool enabled) async {
  if (!_supported) return;
  try {
    final wm = Workmanager();
    await wm.initialize(prefetchDispatcher);
    if (enabled) {
      await wm.registerPeriodicTask(
        closeFeedUniqueName,
        closeFeedTaskName,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      );
    } else {
      await wm.cancelByUniqueName(closeFeedUniqueName);
    }
  } catch (_) {
    // No WorkManager (tests, unsupported device): the foreground poll still works.
  }
}

/// The background entry for [closeFeedTaskName]: its own database, session and notifier, one poll with no wait.
Future<bool> runCloseFeedBackground() async {
  try {
    final db = await AppDb.open();
    final session = SessionService();
    await session.load();
    await AlertService.instance.init();
    final feed = CloseFeed(api: () => session.api, db: db, notify: AlertService.instance.showSlateCloses);
    await feed.pollOnce(wait: 0);
  } catch (_) {
    // Swallowed on purpose: the next period tries again.
  }
  return true;
}

/// A pass while the app is open, for when the phone is already on Wi-Fi and
/// plugged in. Never awaited by the UI.
Future<PrefetchResult?> prefetchNow(AppServices s) async {
  if (!_supported) return null;
  try {
    final store = DbPrefetchStore(s.db);
    return await Prefetcher(
      modules: LibraryPrefetchModules(s.modules),
      courses: () async => _coursesOf(s.store.learning.value),
      store: store,
      onUnmeteredAndCharging: wifiAndCharging,
      baseUrl: () => s.api.baseUrl,
      token: () => s.api.token,
      warmImage: _warm,
    ).run();
  } catch (_) {
    return null;
  }
}
