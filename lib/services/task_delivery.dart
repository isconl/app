import '../api/client.dart';

/// A person a task can be delivered to (the console's /api/tasks/recipients).
class Recipient {
  const Recipient(this.name, this.role);
  final String name;
  final String role;
}

/// One file a task produced, as /api/tasks/deliverables lists it.
class Deliverable {
  const Deliverable({
    required this.name,
    required this.source,
    this.role = '',
    this.bytes = 0,
    this.webUrl = '',
    this.onedrive,
    this.stale = false,
    this.rel = '',
  });
  final String name;

  /// The path the document routes take (open, replace, share). Empty when the hub gave none.
  final String rel;

  /// `linked` (attached, certain) or `found` (the search's best guess).
  final String source;
  final String role;
  final int bytes;
  final String webUrl;
  final bool? onedrive;
  final bool stale;

  bool get isGuess => source != 'linked';
}

class TaskDocs {
  const TaskDocs({this.all = const [], this.noteText = '', this.noteSubject = '', this.dead = 0});
  final List<Deliverable> all;
  final String noteText;
  final String noteSubject;
  final int dead;
}

/// Whether the task has what it needs, from /api/tasks/coverage.
class TaskCoverage {
  const TaskCoverage({required this.covered, this.gaps = const [], this.superior = false});
  final bool covered;
  final List<String> gaps;
  final bool superior;
}

/// The console's task routes, through hub. Delivery writes are online only: they
/// record an outward handover, so they are never queued behind the user's back.
abstract class TaskDeliveryClient {
  Future<List<Recipient>> recipients();
  Future<TaskDocs> deliverables(String taskId);
  Future<String> note(String taskId);
  Future<TaskCoverage?> coverage(String taskId);

  /// Creates the work-record deliverable for a task that has none. Returns its name.
  Future<String> provision(String taskId);

  /// Repairs every link on the board. Returns a plain sentence.
  Future<String> relink();

  Future<void> setDelivery(String taskId, String delivery);
  Future<void> recordSend(String taskId, {required String sentTo, required String sentVia, required String sentAt, String note = ''});
}

class HubTaskDeliveryClient implements TaskDeliveryClient {
  HubTaskDeliveryClient(this.api);
  final ApiClient api;

  static Map<String, dynamic> _m(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  static List<dynamic> _l(Object? v) => v is List ? v : const [];

  static void _ok(Object? res) {
    final m = _m(res);
    if (m['success'] != true) throw ApiException(0, '${m['error'] ?? 'The agent refused that.'}');
  }

  @override
  Future<List<Recipient>> recipients() async => [
        for (final r in _l(_m(await api.getJson('/api/tasks/recipients'))['recipients']))
          if (r is Map) Recipient('${r['name'] ?? ''}', '${r['role'] ?? ''}'),
      ];

  static Deliverable parseDeliverable(Map<String, dynamic> d) => Deliverable(
        name: '${d['name'] ?? ''}',
        source: '${d['source'] ?? ''}',
        role: '${d['role'] ?? ''}',
        bytes: (d['bytes'] as num?)?.toInt() ?? 0,
        webUrl: '${d['webUrl'] ?? ''}',
        onedrive: d['onedrive'] is bool ? d['onedrive'] as bool : null,
        stale: d['stale'] == true,
        rel: '${d['rel'] ?? d['path'] ?? ''}',
      );

  @override
  Future<TaskDocs> deliverables(String taskId) async {
    final d = _m(await api.getJson('/api/tasks/deliverables?taskId=${Uri.encodeQueryComponent(taskId)}'));
    final list = _l(d['all'] ?? d['deliverables']);
    final note = _m(d['note']);
    return TaskDocs(
      all: [for (final x in list) if (x is Map) parseDeliverable(Map<String, dynamic>.from(x))],
      noteText: '${note['text'] ?? ''}',
      noteSubject: '${note['subject'] ?? ''}',
      dead: _l(d['dead']).length,
    );
  }

  @override
  Future<String> note(String taskId) async {
    final n = _m(_m(await api.getJson('/api/tasks/note?taskId=${Uri.encodeQueryComponent(taskId)}'))['note']);
    final text = '${n['text'] ?? ''}';
    if (text.isEmpty) throw ApiException(0, 'No note resolved for this task');
    final subject = '${n['subject'] ?? ''}';
    return subject.isEmpty ? text : '$subject\n\n$text';
  }

  @override
  Future<TaskCoverage?> coverage(String taskId) async {
    final d = _m(await api.getJson('/api/tasks/coverage'));
    for (final t in _l(d['tasks'])) {
      if (t is Map && '${t['id']}' == taskId) {
        return TaskCoverage(
          covered: t['covered'] == true,
          gaps: [for (final g in _l(t['gaps'])) '$g'],
          superior: t['superior'] == true,
        );
      }
    }
    return null;
  }

  @override
  Future<String> provision(String taskId) async {
    final d = _m(await api.postJson('/api/tasks/coverage/provision', {'taskId': taskId}));
    _ok(d);
    return '${d['name'] ?? 'the deliverable'}';
  }

  @override
  Future<String> relink() async {
    final d = _m(await api.postJson('/api/tasks/deliverables/relink', {}));
    _ok(d);
    final r = d['repaired'] ?? 0;
    return '$r task${r == 1 ? '' : 's'} relinked, ${d['adopted'] ?? 0} adopted, ${d['dropped'] ?? 0} dead links dropped';
  }

  @override
  Future<void> setDelivery(String taskId, String delivery) async =>
      _ok(await api.postJson('/api/tasks/delivery', {'id': taskId, 'delivery': delivery}));

  @override
  Future<void> recordSend(String taskId,
          {required String sentTo, required String sentVia, required String sentAt, String note = ''}) async =>
      _ok(await api.postJson('/api/tasks/delivery', {
        'id': taskId,
        'delivery': 'sent',
        'sentTo': sentTo,
        'sentVia': sentVia,
        'sentAt': sentAt,
        'note': note,
      }));
}

/// The console's delivery vocabulary for a task row.
String deliveryStateOf(Map<String, dynamic> task) {
  final d = '${task['DELIVERY'] ?? ''}';
  if (d.isNotEmpty && d != '-') return d;
  return '${task['STATUS'] ?? ''}' == 'review' ? 'drafted' : '-';
}

const deliveryLabels = {'-': 'Not started', 'drafted': 'Drafted', 'reviewed': 'Reviewed', 'sent': 'Sent'};

const sendVias = ['email', 'whatsapp', 'jira', 'teams', 'in person', 'shared drive', 'other'];
