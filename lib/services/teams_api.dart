import '../api/client.dart';

/// The console's team routes (teams/member, member/remove, work, work/move), through
/// hub. Each write answers `{success, error?}`; a refusal becomes an exception with
/// the server's own sentence.
abstract class TeamsClient {
  /// Adds a member (no `id`) or edits one (with `id`).
  Future<void> saveMember(Map<String, dynamic> member);

  /// Marks a member as left: their open work returns to the board, their reports move up.
  Future<void> removeMember(String id);

  /// Adds a work item (no `id`) or edits one (with `id`; this is how work moves between people).
  Future<void> saveWork(Map<String, dynamic> work);

  /// Moves work along its lifecycle: queued, active, blocked (with a note), finished, signed.
  /// Returns `signedBy` when the move was a sign-off.
  Future<String?> moveWork(String id, String to, {String? note});
}

class HubTeamsClient implements TeamsClient {
  HubTeamsClient(this.api);
  final ApiClient api;

  static Map<String, dynamic> _ok(Object? res) {
    final m = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
    if (m['success'] != true) throw ApiException(0, '${m['error'] ?? 'The agent refused that.'}');
    return m;
  }

  @override
  Future<void> saveMember(Map<String, dynamic> member) async =>
      _ok(await api.postJson('/api/teams/member', member));

  @override
  Future<void> removeMember(String id) async => _ok(await api.postJson('/api/teams/member/remove', {'id': id}));

  @override
  Future<void> saveWork(Map<String, dynamic> work) async => _ok(await api.postJson('/api/teams/work', work));

  @override
  Future<String?> moveWork(String id, String to, {String? note}) async {
    final r = _ok(await api.postJson('/api/teams/work/move', {'id': id, 'to': to, if (note != null) 'note': note}));
    return r['signedBy'] == null ? null : '${r['signedBy']}';
  }
}

/// The work item as the reassign call must send it: every field the console's work
/// form sends, so changing only the owner leaves the rest as it was.
Map<String, dynamic> workToSave(Map<String, dynamic> w, String teamId, {String? memberId}) => {
      'id': '${w['id']}',
      'teamId': teamId,
      'title': '${w['title'] ?? ''}',
      'why': '${w['why'] ?? ''}',
      'memberId': memberId ?? '${w['memberId'] ?? ''}',
      'due': '${w['due'] ?? ''}',
      'doneMeans': '${w['doneMeans'] ?? ''}',
      'effortDays': (w['effortDays'] is num && (w['effortDays'] as num) > 0) ? w['effortDays'] : 1,
    };

/// The body for adding or editing a member, with the console's field names.
Map<String, dynamic> memberToSave({
  String? id,
  required String teamId,
  required String name,
  String role = '',
  String reportsTo = '',
  String personId = '',
  String forcePrimary = '',
  String forceSecondary = '',
  bool isArchitect = false,
}) =>
    {
      if (id != null) 'id': id,
      'teamId': teamId,
      'name': name.trim(),
      'role': role.trim(),
      'reportsTo': reportsTo,
      'personId': personId.trim(),
      'forcePrimary': forcePrimary,
      'forceSecondary': forceSecondary,
      'isArchitect': isArchitect,
    };

/// The statuses a work item can be moved to from where it is, with the button label.
List<({String to, String label})> workMoves(String status) => switch (status) {
      'queued' => [(to: 'active', label: 'Start'), (to: 'blocked', label: 'Block')],
      'active' => [(to: 'finished', label: 'Finish'), (to: 'blocked', label: 'Block')],
      'blocked' => [(to: 'queued', label: 'Unblock')],
      'finished' => [(to: 'signed', label: 'Sign')],
      _ => const [],
    };

/// The surfaced-task update the console sends: `new`, `seen` or `dismissed`.
Future<void> updateSurfaced(ApiClient api, String id, String status) async {
  final res = await api.postJson('/api/surfaced-tasks/update', {'id': id, 'status': status});
  final m = res is Map ? res : const {};
  if (m['success'] != true) throw ApiException(0, '${m['error'] ?? 'Refused'}');
}
