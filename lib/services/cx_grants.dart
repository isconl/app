import '../api/client.dart';
import 'passkey_client.dart';

/// A session asking to read the journal (cx canon section 3). It carries a
/// name, a machine and a reason, never any journal text.
class GrantRequest {
  const GrantRequest({
    required this.id,
    required this.session,
    required this.machine,
    required this.reason,
    this.limit = const Duration(hours: 2),
  });

  final String id;
  final String session;
  final String machine;
  final String reason;

  /// The longest a grant can last; shown on the sheet so approval is informed.
  final Duration limit;
}

/// An approved grant that is still live.
class LiveGrant {
  const LiveGrant({
    required this.id,
    required this.session,
    required this.machine,
    required this.expiresAt,
    required this.reads,
  });

  final String id;
  final String session;
  final String machine;
  final DateTime expiresAt;
  final int reads;

  Duration timeLeft(DateTime now) {
    final d = expiresAt.difference(now);
    return d.isNegative ? Duration.zero : d;
  }
}

/// The phone's side of the journal read grants, through hub only:
///   GET  /api/cx/grants/pending        -> { grants: [...] }
///   GET  /api/cx/grants                -> { grants: [...] } live ones
///   POST /api/cx/grants/:id/approve    { response }   passkey assertion
///   POST /api/cx/grants/:id/refuse
///   POST /api/cx/grants/:id/revoke
abstract class CxGrantsClient {
  Future<GrantRequest?> request(String id);
  Future<List<LiveGrant>> live();

  /// Approves with a passkey. Returns false when the phone's prompt was not
  /// completed, in which case nothing was sent.
  Future<bool> approve(String id);
  Future<void> refuse(String id);
  Future<void> revoke(String id);
}

class HubCxGrantsClient implements CxGrantsClient {
  HubCxGrantsClient(this.api, this.passkeys);
  final ApiClient api;
  final PasskeyClient passkeys;

  static Map<String, dynamic> _m(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  static String _path(String id) => '/api/cx/grants/${Uri.encodeComponent(id)}';

  static GrantRequest parseRequest(Map<String, dynamic> m) => GrantRequest(
        id: '${m['id'] ?? ''}',
        session: '${m['session'] ?? ''}',
        machine: '${m['machine'] ?? ''}',
        reason: '${m['reason'] ?? ''}',
        limit: Duration(seconds: (m['limit_seconds'] as num?)?.toInt() ?? 7200),
      );

  static LiveGrant parseLive(Map<String, dynamic> m) {
    final at = m['expires_at'] ?? m['expiresAt'];
    final epoch = at is num ? at.toInt() : int.tryParse('$at') ?? 0;
    return LiveGrant(
      id: '${m['id'] ?? ''}',
      session: '${m['session'] ?? ''}',
      machine: '${m['machine'] ?? ''}',
      expiresAt: DateTime.fromMillisecondsSinceEpoch(epoch * 1000, isUtc: true),
      reads: (m['reads'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<GrantRequest?> request(String id) async {
    final res = _m(await api.getJson('/api/cx/grants/pending'));
    final list = res['grants'];
    if (list is! List) return null;
    for (final g in list) {
      final r = parseRequest(_m(g));
      if (r.id == id) return r;
    }
    return null;
  }

  @override
  Future<List<LiveGrant>> live() async {
    final res = _m(await api.getJson('/api/cx/grants'));
    final list = res['grants'];
    return list is List ? [for (final g in list) parseLive(_m(g))] : const [];
  }

  @override
  Future<bool> approve(String id) async {
    final opts = _m(await api.postJson('/api/auth/passkey/options', {'purpose': 'cx-grant', 'grant': id}));
    if (opts['available'] != true || opts['options'] is! Map) return false;
    final assertion = await passkeys.authenticate(_m(opts['options']));
    final res = _m(await api.postJson('${_path(id)}/approve', {'response': assertion}));
    return res['ok'] == true;
  }

  @override
  Future<void> refuse(String id) async => api.postJson('${_path(id)}/refuse', {});

  @override
  Future<void> revoke(String id) async => api.postJson('${_path(id)}/revoke', {});
}
