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
