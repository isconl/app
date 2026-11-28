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


  // ---- rows, decisions, blockers, matrix, today (command centre canon section 3) ----

  static Map<String, dynamic> _m(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  static List<dynamic> _l(Object? v, String key) {
    final x = v is Map ? v[key] : v;
    return x is List ? x : const [];
  }

  static RowSummary parseRow(Map<String, dynamic> m) => RowSummary(
        id: '${m['id'] ?? ''}',
        project: '${m['project'] ?? ''}',
        type: '${m['type'] ?? ''}',
        title: '${m['title'] ?? ''}',
        status: '${m['effectiveStatus'] ?? m['status'] ?? ''}',
        priority: (m['priority'] as num?)?.toInt(),
        claimedBy: (m['claimedBySession'] ?? m['claimedBy']) as String?,
        gate: m['gate'] as String?,
        subset: m['subset'] as String?,
      );

  static RowDetail parseDetail(Map<String, dynamic> m) {
    final r = parseRow(m);
    return RowDetail(
      id: r.id,
      project: r.project,
      type: r.type,
      title: r.title,
      status: r.status,
      body: '${m['body'] ?? ''}',
      priority: r.priority,
      claimedBy: r.claimedBy,
      gate: r.gate,
      subset: r.subset,
    );
  }

  static BlockerInfo parseBlocker(Map<String, dynamic> m) {
    final at = m['raised_at'] ?? m['raisedAt'];
    final epoch = at is num ? at.toInt() : int.tryParse('$at') ?? 0;
    return BlockerInfo(
      id: '${m['id'] ?? ''}',
      row: '${m['row'] ?? ''}',
      kind: '${m['class'] ?? m['kind'] ?? ''}',
      need: '${m['need'] ?? ''}',
      raisedAt: DateTime.fromMillisecondsSinceEpoch(epoch * 1000, isUtc: true),
    );
  }

  static MatrixData parseMatrix(Object? res) {
    final m = _m(res);
    final types = [for (final t in _l(m, 'types')) '$t'];
    final cells = <String, Map<String, int>>{};
    _m(m['projects']).forEach((p, v) {
      cells[p] = {for (final e in _m(v).entries) e.key: (e.value as num?)?.toInt() ?? 0};
    });
    return MatrixData(types: types, cells: cells);
  }

  static TodayData parseToday(Object? res) {
    final m = _m(res);
    return TodayData(
      closedToday: (m['closed_today'] as num?)?.toInt() ?? 0,
      weeklyDailyAverage: (m['weekly_daily_average'] as num?)?.toDouble() ?? 0,
      inFlight: (m['in_flight'] as num?)?.toInt() ?? 0,
    );
  }

  String _row(String project, String id) => '/api/slate/rows/${Uri.encodeComponent(project)}/${Uri.encodeComponent(id)}';

  @override
  Future<List<RowSummary>> rows({String? type, String? project}) async {
    final q = [if (type != null) 'type=$type', if (project != null) 'project=${Uri.encodeQueryComponent(project)}'];
    final res = await api.getJson('/api/slate/rows${q.isEmpty ? '' : '?${q.join('&')}'}');
    return [for (final r in _l(res, 'rows')) parseRow(_m(r))];
  }

  @override
  Future<RowDetail> row(String id, String project) async {
    final res = _m(await api.getJson(_row(project, id)));
    return parseDetail(_m(res['row'] ?? res));
  }

  @override
  Future<void> claimRow(String id, String project) async => api.postJson('${_row(project, id)}/claim', {});

  @override
  Future<void> closeRow(String id, String project, String note) async =>
      api.postJson('${_row(project, id)}/close', {'note': note});

  @override
  Future<void> editRow(String id, String project, {String? title, String? body}) async =>
      api.postJson('${_row(project, id)}/edit', {'title': ?title, 'body': ?body});

  @override
  Future<List<RowSummary>> decisions() async =>
      [for (final r in _l(await api.getJson('/api/slate/decisions'), 'decisions')) parseRow(_m(r))];

  @override
  Future<void> answerDecision(String id, String project, String answer) async =>
      api.postJson('${_row(project, id)}/answer', {'answer': answer});

  @override
  Future<List<RowSummary>> brainstorms() async =>
      [for (final r in _l(await api.getJson('/api/slate/brainstorms'), 'brainstorms')) parseRow(_m(r))];

  @override
  Future<List<BlockerInfo>> blockers() async =>
      [for (final b in _l(await api.getJson('/api/slate/blockers'), 'blockers')) parseBlocker(_m(b))];

  @override
  Future<void> clearBlocker(String id, String evidence) async =>
      api.postJson('/api/slate/blockers/${Uri.encodeComponent(id)}/clear', {'evidence': evidence});

  @override
  Future<MatrixData> matrix() async => parseMatrix(await api.getJson('/api/slate/matrix'));

  @override
  Future<TodayData> today() async => parseToday(await api.getJson('/api/slate/today'));
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

/// Passkey step-up for a row write: the same assertion, with the sentence
/// being approved so hub can audit it.
WriteStepUp passkeyWriteStepUp(ApiClient api, PasskeyClient passkeys) => (String summary) async {
      final opts = await api.postJson('/api/auth/passkey/options', {'purpose': 'stepup', 'summary': summary});
      if (opts is! Map || opts['available'] != true || opts['options'] is! Map) return false;
      final assertion = await passkeys.authenticate(Map<String, dynamic>.from(opts['options'] as Map));
      final res = await api.postJson(
          '/api/auth/passkey/verify', {'response': assertion, 'purpose': 'stepup', 'summary': summary});
      return res is Map && res['ok'] == true;
    };