import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../api/client.dart';
import 'db.dart';
import 'module_ops.dart';

/// Queue of writes made while offline (or that failed in transit).
/// Drained FIFO on reconnect; the server then syncs the vault to OneDrive.
///
/// GATE-sensitive actions (approvals, Jira writes, deletes) are NEVER queued -
/// the constitution requires true server state for those, so callers must
/// check [SyncEngine.online] and refuse offline.
class OutboxService extends ChangeNotifier {
  OutboxService(this._db, this._api);

  final AppDb _db;
  final ApiClient Function() _api;

  /// Writes waiting to go. Refused ones are counted in [failed], not here.
  int pending = 0;
  /// BI26111402: writes the server answered "no" to; shown in the Outbox, retried only by hand.
  int failed = 0;
  bool draining = false;
  String? lastError;

  /// BI26101204: retire and restore actions waiting in the queue or refused, by module id, for the pending badge.
  Map<String, ModuleOp> moduleOps = const {};

  Future<void> refreshCount() async {
    pending = await _db.pendingCount();
    try {
      failed = await _db.failedCount();
    } catch (_) {}
    try {
      moduleOps = moduleOpsFromOutbox(await _db.outboxHistory(limit: 200));
    } catch (_) {
      // A badge is a convenience; the queue itself is unaffected.
    }
    notifyListeners();
  }

  /// Queue a write for later delivery.
  Future<void> enqueue({
    required String path,
    required Map<String, dynamic> body,
    required String label,
    required String view,
  }) async {
    await _db.enqueue(
        method: 'POST', path: path, body: body, label: label, view: view);
    await refreshCount();
  }

  /// Deliver everything pending. Returns the number delivered.
  Future<int> drain() async {
    if (draining) return 0;
    draining = true;
    try {
      await _db.retryFailedOnce('outbox_retry_failed_once_BI26111402');
      await _db.retryFailedOnce('outbox_retry_failed_once_BI26111590');
    } catch (_) {}
    lastError = null;
    notifyListeners();
    var delivered = 0;
    // BI26111590: one write the server cannot take must never hold up the rest. Before this, a 404 (hub's answer for
    // a part of iSconl not running on that server) read as "session expired" and stopped the whole drain at the
    // first item, so 500+ writes sat behind one forever. Now such an item is skipped (it stays pending for the next
    // pass) and the drain goes on. No answer at all (tunnel down) still stops the pass, keeping order.
    bool? sessionAlive;
    try {
      final items = await _db.pendingOutbox();
      for (final item in items) {
        final id = item['id'] as int;
        Map<String, dynamic> body;
        try {
          body = (jsonDecode(item['body'] as String) as Map)
              .cast<String, dynamic>();
        } catch (_) {
          await _db.markOutbox(id, 'failed', 'corrupt payload');
          continue;
        }
        try {
          await _api().postJson(item['path'] as String, body);
          await _db.markOutbox(id, 'sent');
          delivered++;
        } on OfflineException {
          lastError = 'offline';
          break; // stop draining, keep order
        } on ApiException catch (e) {
          if (e.status == 404 || isNotRunningHere(e)) {
            // Is the session really dead? Ask once per pass; only /api/state can prove it.
            sessionAlive ??= await _sessionAlive();
            if (sessionAlive == false) {
              lastError = 'session expired';
              break;
            }
            // The session is fine: this part of iSconl is not on the server. Keep it waiting and go on.
            await _db.markOutbox(id, 'pending', notRunningNote);
            continue;
          }
          if (e.transient) {
            // No answer from the server (tunnel, timeout, rate limit): it stays pending, in order, for the next pass.
            lastError = e.message;
            await _db.markOutbox(id, 'pending', e.message);
            break;
          }
          // The server answered no: keep it visible as failed, never retried on its own, and go on with the rest.
          await _db.markOutbox(id, 'failed', e.message);
        } catch (e) {
          // Not an answer at all (a socket error): the same as offline.
          lastError = '$e';
          await _db.markOutbox(id, 'pending', '$e');
          break;
        }
      }
      await _db.pruneSentOutbox();
    } finally {
      draining = false;
      await refreshCount();
    }
    return delivered;
  }

  /// BI26111590: the note on a write whose part of iSconl is not running on the server; it goes when that part is back.
  static const notRunningNote = 'waiting: that part of iSconl is not running on the server';

  /// Hub answers 503 {unavailable: true} for a write to an engine it does not run (hub 0.5.145+).
  static bool isNotRunningHere(ApiException e) =>
      e.status == 503 && e.message.toLowerCase().contains('not running');

  Future<bool> _sessionAlive() async {
    try {
      await _api().getJson('/api/state');
      return true;
    } on ApiException catch (e) {
      return !(e.status == 404 || e.status == 401);
    } catch (_) {
      return true; // no answer is not proof of a dead session
    }
  }

  Future<List<Map<String, dynamic>>> history() => _db.outboxHistory();

  Future<void> retry(int id) async {
    await _db.markOutbox(id, 'pending');
    await refreshCount();
  }

  Future<void> discard(int id) async {
    await _db.deleteOutbox(id);
    await refreshCount();
  }
}
