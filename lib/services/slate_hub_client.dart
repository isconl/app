import 'package:slate_ui/slate_ui.dart';

import '../api/client.dart';
import 'passkey_client.dart';

/// slate_ui's client, served through hub: the app never talks to slate and
/// holds no slate token. Routes follow the command centre canon section 3:
///   GET  /api/slate/sessions         -> { sessions: [...] }
///   POST /api/slate/commands         -> { id }
///   GET  /api/slate/commands/:id     -> { state: sent | delivered | acknowledged }
/// Parsing is tolerant of both snake_case and camelCase fields.
class HubSlateClient implements SlateClient {
  HubSlateClient(this.api);
  final ApiClient api;

  @override
  Future<List<SessionInfo>> sessions() async {
    final res = await api.getJson('/api/slate/sessions');
    final list = res is Map ? res['sessions'] : res;
    if (list is! List) return const [];
    return [for (final s in list) if (s is Map) parseSession(Map<String, dynamic>.from(s))];
  }

  @override
  Future<String> sendCommand(CommandDraft draft) async {
    final res = await api.postJson('/api/slate/commands', commandBody(draft));
    final id = res is Map ? res['id'] : null;
    if (id == null) throw ApiException(0, 'hub did not return a command id');
    return '$id';
  }

  @override
  Future<DeliveryState> deliveryState(String commandId) async {
    final res = await api.getJson('/api/slate/commands/$commandId');
    return parseState(res is Map ? res['state'] : null);
  }

  static SessionInfo parseSession(Map<String, dynamic> m) {
    T? pick<T>(String a, String b) {
      final v = m[a] ?? m[b];
      return v is T ? v : null;
    }

    final seen = m['last_seen'] ?? m['lastSeen'];
    final epoch = seen is num ? seen.toInt() : int.tryParse('$seen') ?? 0;
    return SessionInfo(
      id: '${m['id'] ?? m['session_id'] ?? m['sessionId'] ?? ''}',
      machine: '${m['machine'] ?? m['machine_id'] ?? 'unknown'}',
      kind: '${m['kind'] ?? ''}',
      model: pick<String>('model', 'model'),
      currentRow: pick<String>('current_row', 'currentRow'),
      currentRowTitle: pick<String>('current_row_title', 'currentRowTitle'),
      position: pick<num>('position', 'position')?.toInt(),
      total: pick<num>('total', 'of')?.toInt(),
      status: pick<String>('status', 'status'),
      lastSeen: DateTime.fromMillisecondsSinceEpoch(epoch * 1000, isUtc: true),
    );
  }

  static Map<String, dynamic> commandBody(CommandDraft d) => {
        'to': switch (d.target.scope) {
          TargetScope.session => {'session': d.target.session},
          TargetScope.kindOnMachine => {'kind': d.target.kind, 'machine': d.target.machine},
          TargetScope.everyone => {'everyone': true},
        },
        'message': d.message,
        'persistent': d.persistent,
        if (d.expiresIn != null) 'expires_in_seconds': d.expiresIn!.inSeconds,
        if (d.action != null) 'action': d.action!.name,
      };

  static DeliveryState parseState(Object? s) => switch ('$s') {
        'acknowledged' || 'acked' => DeliveryState.acknowledged,
        'delivered' => DeliveryState.delivered,
        _ => DeliveryState.sent,
      };
}

/// Passkey step-up for a command: hub issues assertion options for the
/// `stepup` purpose, the phone signs, hub verifies. One approval covers 15
/// minutes on hub's side, so a quick second command does not prompt again.
StepUp passkeyStepUp(ApiClient api, PasskeyClient passkeys) => (CommandDraft draft) async {
      final opts = await api.postJson('/api/auth/passkey/options', {'purpose': 'stepup'});
      if (opts is! Map || opts['available'] != true || opts['options'] is! Map) return false;
      final assertion = await passkeys.authenticate(Map<String, dynamic>.from(opts['options'] as Map));
      final res = await api.postJson(
          '/api/auth/passkey/verify', {'response': assertion, 'purpose': 'stepup'});
      return res is Map && res['ok'] == true;
    };
