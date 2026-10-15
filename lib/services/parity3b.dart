import '../api/client.dart';

/// BI26101212: five routes the console has and the app lacked, through hub.

/// The pre-written nudge for a decision that has been pending too long.
class ChaseDraft {
  const ChaseDraft({
    required this.id,
    required this.by,
    required this.date,
    required this.to,
    required this.channel,
    required this.body,
    this.checks = const [],
  });
  final String id;
  final String by;
  final String date;
  final String to;
  final String channel;
  final String body;

  /// Things to check before sending: what was found in the text, and what to say about it.
  final List<({String found, String say})> checks;
}

class BlockAdherence {
  const BlockAdherence({required this.day, required this.name, required this.loggedMinutes, required this.sessionCount, this.adherencePct});
  final String day;
  final String name;
  final double loggedMinutes;
  final int sessionCount;

  /// Share of the logged time that was on purpose; null when the block has no purpose set.
  final int? adherencePct;
}

class Adherence {
  const Adherence({required this.days, required this.perBlock, required this.recommendations});
  final int days;
  final List<BlockAdherence> perBlock;
  final List<String> recommendations;

  /// Only blocks that were actually worked: the console hides the rest.
  List<BlockAdherence> get touched => [for (final b in perBlock) if (b.sessionCount > 0) b];
}

abstract class Parity3bApi {
  Future<ChaseDraft> chase(String decisionId);

  /// "Different angle": asks for a fresh draft. Read it again with [chase].
  Future<void> rechase(String decisionId);

  /// Stops counting a key date. Nothing else is touched.
  Future<void> deleteDate(String id);

  Future<Adherence> adherence({int days = 7});

  /// The day's theme phrase, or null when there is none.
  Future<String?> themeDay();

  /// Runs the notification sweep. Returns how many new notices it raised.
  Future<int> sweep();
}

class HubParity3bApi implements Parity3bApi {
  HubParity3bApi(this.api);
  final ApiClient api;

  static Map<String, dynamic> _m(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  static List<dynamic> _l(Object? v) => v is List ? v : const [];

  @override
  Future<ChaseDraft> chase(String decisionId) async {
    final d = _m(await api.getJson('/api/decisions/chase?id=${Uri.encodeQueryComponent(decisionId)}'));
    if (d['success'] != true) throw ApiException(0, '${d['error'] ?? 'Not available'}');
    final dec = _m(d['decision']);
    final draft = _m(d['draft']);
    return ChaseDraft(
      id: '${dec['id'] ?? decisionId}',
      by: '${dec['by'] ?? ''}',
      date: '${dec['date'] ?? ''}',
      to: '${draft['to'] ?? ''}',
      channel: '${draft['channel'] ?? ''}',
      body: '${draft['body'] ?? ''}',
      checks: [
        for (final c in _l(draft['checks']))
          if (c is Map) (found: '${c['found'] ?? ''}', say: '${c['say'] ?? ''}'),
      ],
    );
  }

  @override
  Future<void> rechase(String decisionId) async {
    await api.postJson('/api/decisions/chase', {'id': decisionId});
  }

  @override
  Future<void> deleteDate(String id) async {
    final d = _m(await api.postJson('/api/dates/delete', {'id': id}));
    // The console ignores the body and reloads; a refusal here is still worth saying.
    if (d['success'] == false) throw ApiException(0, '${d['error'] ?? 'Refused'}');
  }

  static Adherence parseAdherence(Object? res) {
    final a = _m(res);
    if (a['error'] != null && a['perBlock'] == null) throw ApiException(0, '${a['error']}');
    return Adherence(
      days: (a['days'] as num?)?.toInt() ?? 7,
      perBlock: [
        for (final b in _l(a['perBlock']))
          if (b is Map)
            BlockAdherence(
              day: '${b['day'] ?? ''}',
              name: '${b['name'] ?? ''}',
              loggedMinutes: (b['loggedMinutes'] as num?)?.toDouble() ?? 0,
              sessionCount: (b['sessionCount'] as num?)?.toInt() ?? 0,
              adherencePct: (b['adherencePct'] as num?)?.round(),
            ),
      ],
      recommendations: [for (final r in _l(a['recommendations'])) '$r'],
    );
  }

  @override
  Future<Adherence> adherence({int days = 7}) async => parseAdherence(await api.getJson('/api/planning/adherence?days=$days'));

  @override
  Future<String?> themeDay() async {
    final p = _m(await api.getJson('/api/theme-day'))['phrase'];
    return (p is String && p.trim().isNotEmpty) ? p.trim() : null;
  }

  @override
  Future<int> sweep() async {
    final d = _m(await api.postJson('/api/notifications/sweep', {}));
    return (d['raised'] as num?)?.toInt() ?? 0;
  }
}

/// The toast the console shows after a sweep.
String sweepMessage(int raised) =>
    raised > 0 ? '$raised new notice${raised == 1 ? '' : 's'}' : 'Nothing new. Everything is already noticed.';
