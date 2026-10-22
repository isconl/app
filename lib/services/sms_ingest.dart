import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/client.dart';
import '../util/fmt.dart' as fmt;
import 'mpesa.dart';

/// Automatic SMS ingestion.
///
/// ARCHITECT's instruction: read his SMS, extract the context - M-Pesa movements and
/// the people in them - and keep the agent updated in every related aspect,
/// automatically, every time. He grants the permission on the device.
///
/// ─── HOW IT STAYS CORRECT ───────────────────────────────────────────────────
///
/// A ledger that double-counts is worse than one that is behind, so this is built
/// around idempotency rather than around speed:
///
///   * A HIGH-WATER MARK, kept in secure storage, is the only state. Every read
///     asks for messages newer than it. It advances ONLY after the agent has
///     accepted the batch, so a failure mid-flight re-reads rather than skips.
///   * The transaction code is the identity of a movement. The agent rejects a
///     code it already holds, so even a full re-read of the inbox cannot create a
///     second row for the same payment.
///   * The BODY of a message never becomes a ledger row on its own. It is parsed
///     into a typed event first, and an unrecognised shape is reported rather than
///     guessed at - see mpesa.dart.
///
/// ─── WHAT IT DOES NOT DO ────────────────────────────────────────────────────
///
/// It does not read anything that is not from M-Pesa. The platform query filters
/// by sender, the Dart side checks the sender again, and only M-Pesa messages are
/// ever sent anywhere. His actual conversations are not touched, not uploaded and
/// not parsed - and the app holds no SEND_SMS permission at all, so it cannot
/// ever send a message in his name.
class SmsIngest extends ChangeNotifier {
  SmsIngest(this._apiProvider);

  final ApiClient Function() _apiProvider;

  static const _channel = MethodChannel('isconl/platform');
  static const _markKey = 'isconl.sms.highwater';
  static const _storage = FlutterSecureStorage();

  bool granted = false;
  bool busy = false;
  String? lastError;

  /// Totals since install, for the settings surface. Reported rather than
  /// inferred so "is this working" has an answer that is not a vibe.
  int imported = 0;
  int skippedDuplicate = 0;
  int unparsedCount = 0;
  DateTime? lastRun;

  /// Messages that looked like M-Pesa and matched no known shape. Kept so the
  /// parser can be improved - a parser that silently drops what it does not
  /// understand can never be, because nobody learns what it missed.
  final List<String> unparsedSamples = [];

  Future<void> refreshPermission() async {
    try {
      granted = await _channel.invokeMethod<bool>('smsGranted') ?? false;
    } catch (_) {
      granted = false;   // not Android, or the channel is absent
    }
    notifyListeners();
  }

  /// Show the system sheet. Android answers by changing the permission state, so
  /// the result is read back rather than awaited through a callback.
  Future<bool> request() async {
    try {
      granted = await _channel.invokeMethod<bool>('requestSms') ?? false;
    } catch (_) {
      granted = false;
    }
    notifyListeners();
    return granted;
  }

  Future<int> _highWater() async {
    final v = await _storage.read(key: _markKey);
    return int.tryParse(v ?? '') ?? 0;
  }

  /// The first run has no mark. It reads 90 days rather than the whole inbox:
  /// far enough back to establish the current picture, short enough that a phone
  /// with years of messages does not spend a minute on its first sync.
  Future<int> _startFrom() async {
    final mark = await _highWater();
    if (mark > 0) return mark;
    return DateTime.now().subtract(const Duration(days: 90)).millisecondsSinceEpoch;
  }

  /// Read, parse, hand to the agent, then advance the mark.
  ///
  /// Safe to call on every sync and on every app resume: with nothing new it is
  /// one cheap platform call and no network.
  Future<int> run({int limit = 400}) async {
    // No SMS inbox on web at all - skip before touching the channel/storage,
    // rather than relying on refreshPermission()'s existing try/catch.
    if (kIsWeb) return 0;
    if (busy) return 0;
    await refreshPermission();
    if (!granted) return 0;

    busy = true;
    lastError = null;
    notifyListeners();

    var accepted = 0;
    try {
      final since = await _startFrom();
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>(
          'readSms', {'since': since, 'limit': limit});
      final rows = (res?['messages'] as List?) ?? const [];
      if (rows.isEmpty) {
        lastRun = DateTime.now();
        return 0;
      }

      final messages = rows
          .whereType<Map>()
          .map(SmsMessage.fromJson)
          .toList();
      final h = harvest(messages);

      unparsedCount += h.unparsed.length;
      for (final u in h.unparsed.take(5)) {
        if (unparsedSamples.length < 20) unparsedSamples.add(u.body);
      }

      if (h.events.isNotEmpty) {
        final out = await _apiProvider().postJson('/api/ingest/sms', {
          'events': h.events.map((e) => e.toJson()).toList(),
          'scanned': h.scanned,
          'unparsed': h.unparsed.length,
        });
        final m = fmt.m(out);
        accepted = fmt.i(m['imported']);
        skippedDuplicate += fmt.i(m['duplicates']);
        imported += accepted;
      }

      // The mark moves ONLY after the agent has taken the batch. A crash before
      // this line means the next run re-reads the same messages, which the
      // transaction code makes harmless. A mark advanced first would lose them.
      final newest = messages
          .map((m) => m.receivedAt.millisecondsSinceEpoch)
          .fold<int>(since, (a, b) => b > a ? b : a);
      if (newest > since) {
        await _storage.write(key: _markKey, value: newest.toString());
      }
      lastRun = DateTime.now();
    } on OfflineException {
      lastError = 'Offline - the messages are still on the phone and will import next time.';
    } on ApiException catch (e) {
      lastError = 'The agent refused the import: ${e.message}';
    } catch (e) {
      lastError = 'Could not read messages ($e).';
    } finally {
      busy = false;
      notifyListeners();
    }
    return accepted;
  }

  /// Forget the high-water mark so the next run re-reads 90 days.
  ///
  /// Safe by construction: the agent deduplicates on the transaction code, so a
  /// re-read reconciles rather than duplicates. Offered because "it missed
  /// something" needs a remedy that is not reinstalling the app.
  Future<void> resetMark() async {
    await _storage.delete(key: _markKey);
    notifyListeners();
  }
}
