import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../api/client.dart';
import 'db.dart';

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

  int pending = 0;
  bool draining = false;
  String? lastError;

  Future<void> refreshCount() async {
    pending = await _db.pendingCount();
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
    lastError = null;
    notifyListeners();
    var delivered = 0;
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
          if (e.status == 404 && e.authSuspect) {
            lastError = 'session expired';
            break;
          }
          // Rejected by the server: keep it visible as failed, move on.
          await _db.markOutbox(id, 'failed', e.message);
        } catch (e) {
          await _db.markOutbox(id, 'failed', '$e');
        }
      }
      await _db.pruneSentOutbox();
    } finally {
      draining = false;
      await refreshCount();
    }
    return delivered;
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
