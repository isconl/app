import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../api/client.dart';
import '../util/fmt.dart' as fmt;
import 'outbox.dart';
import 'store.dart';

enum SyncPhase { idle, waking, pulling, pushing }

/// Keeps the local mirror fresh and delivers queued writes.
///
/// Cycle on reconnect or "Sync now":
///   1. drain the outbox to the server
///   2. ask the server to push the vault to OneDrive (so offline edits land
///      in OneDrive promptly, not just on the server's own 60s timer)
///   3. pull fresh snapshots of every domain
class SyncEngine extends ChangeNotifier {
  SyncEngine(this._store, this._outbox, this._api);

  final Store _store;
  final OutboxService _outbox;
  final ApiClient Function() _api;

  bool online = true;
  SyncPhase phase = SyncPhase.idle;
  DateTime? lastFullSync;
  String? lastError;
  int newAlerts = 0;

  /// Raised after a sync discovers fresh high-priority notifications.
  void Function(List<Map<String, dynamic>> fresh)? onNewAlerts;

  Timer? _pollTimer;
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  final Set<String> _seenAlertIds = {};
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      final was = online;
      online = results.any((r) => r != ConnectivityResult.none);
      notifyListeners();
      if (!was && online) {
        // Connection came back: deliver queued work, then refresh.
        fullSync();
      }
    });
    Connectivity().checkConnectivity().then((results) {
      online = results.any((r) => r != ConnectivityResult.none);
      notifyListeners();
    });
    // Match the dashboard's 90s polling cadence for the core state.
    _pollTimer = Timer.periodic(const Duration(seconds: 90), (_) {
      if (online && phase == SyncPhase.idle) {
        _store.state.refresh();
        _refreshAlerts();
      }
    });
  }

  Future<void> _refreshAlerts() async {
    final ok = await _store.notifications.refresh();
    if (ok) _recountAlerts(raise: true);
  }

  void _recountAlerts({bool raise = false}) {
    final data = _store.notifications.value;
    final items = fmt.lm(fmt.m(data)['notifications']);
    final unseen =
        items.where((n) => fmt.s(n['STATUS']).toLowerCase() == 'new').toList();
    newAlerts = unseen.length;
    if (raise && onNewAlerts != null) {
      final fresh = unseen
          .where((n) =>
              !_seenAlertIds.contains(fmt.s(n['ID'])) &&
              fmt.s(n['SEVERITY']).toLowerCase() == 'high')
          .toList();
      if (fresh.isNotEmpty) onNewAlerts!(fresh);
    }
    for (final n in unseen) {
      _seenAlertIds.add(fmt.s(n['ID']));
    }
    notifyListeners();
  }

  /// Full cycle: push queued writes, nudge OneDrive, pull all domains.
  Future<void> fullSync({bool wake = false}) async {
    if (phase != SyncPhase.idle) return;
    lastError = null;
    try {
      if (wake) {
        phase = SyncPhase.waking;
        notifyListeners();
        await _api().health(cold: true);
      }

      phase = SyncPhase.pushing;
      notifyListeners();
      final delivered = await _outbox.drain();

      if (delivered > 0) {
        // Ask the server to sync the vault to OneDrive now.
        try {
          await _api().postJson('/api/vault/sync', {});
        } catch (_) {
          // Non-fatal: the server's own 60s loop will catch up.
        }
      }

      phase = SyncPhase.pulling;
      notifyListeners();
      var anyOk = false;
      for (final snap in _store.syncSet) {
        final ok = await snap.refresh();
        anyOk = anyOk || ok;
        if (!ok && snap.error == 'offline') break;
      }
      if (anyOk) {
        lastFullSync = DateTime.now();
        online = true;
        _recountAlerts(raise: true);
      } else {
        lastError = _store.state.error;
      }
    } finally {
      phase = SyncPhase.idle;
      notifyListeners();
    }
  }

  /// Cheap foreground refresh for one view's snapshot.
  Future<void> touch(Snapshot snap) async {
    await snap.hydrate();
    if (online) await snap.refresh();
  }

  String get statusLine {
    if (!online) {
      final queued = _outbox.pending;
      return queued > 0
          ? 'Offline · $queued change${queued == 1 ? '' : 's'} queued'
          : 'Offline · reading local mirror';
    }
    return switch (phase) {
      SyncPhase.waking => 'Waking the server…',
      SyncPhase.pushing => 'Delivering queued changes…',
      SyncPhase.pulling => 'Syncing…',
      SyncPhase.idle => lastFullSync == null
          ? 'Not synced yet'
          : 'Synced ${fmt.ago(lastFullSync!.toIso8601String())}',
    };
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _connSub?.cancel();
    super.dispose();
  }
}
