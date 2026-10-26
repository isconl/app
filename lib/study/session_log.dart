import '../data/db.dart';
import '../data/outbox.dart';

class StudySessionRecord {
  const StudySessionRecord({
    this.id,
    required this.module,
    required this.startedAt,
    required this.endedAt,
    required this.fractionRead,
    required this.finished,
    required this.hour,
    this.blockName,
    this.energy,
    this.notNowReason,
  });

  final int? id;
  final String module;
  final DateTime startedAt;
  final DateTime endedAt;
  final double fractionRead;
  final bool finished;
  final int hour;
  final String? blockName;
  final int? energy;
  final String? notNowReason;

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'module': module,
        'started_at': startedAt.millisecondsSinceEpoch,
        'ended_at': endedAt.millisecondsSinceEpoch,
        'fraction_read': fractionRead,
        'finished': finished ? 1 : 0,
        'hour': hour,
        'block_name': blockName,
        'energy': energy,
        'not_now_reason': notNowReason,
      };

  factory StudySessionRecord.fromMap(Map<String, dynamic> m) => StudySessionRecord(
        id: m['id'] as int?,
        module: m['module'] as String,
        startedAt: DateTime.fromMillisecondsSinceEpoch(m['started_at'] as int),
        endedAt: DateTime.fromMillisecondsSinceEpoch(m['ended_at'] as int),
        fractionRead: (m['fraction_read'] as num).toDouble(),
        finished: (m['finished'] as int) == 1,
        hour: m['hour'] as int,
        blockName: m['block_name'] as String?,
        energy: m['energy'] as int?,
        notNowReason: m['not_now_reason'] as String?,
      );
}

class StudySessionLog {
  StudySessionLog(this._db, {this.outbox});
  final AppDb _db;
  final OutboxService? outbox;

  Future<void> logSession(StudySessionRecord session) async {
    await _db.insertStudySession(session.toMap());
    try {
      await outbox?.enqueue(
        path: '/api/study/sessions',
        body: {
          'module': session.module,
          'started_at': session.startedAt.toIso8601String(),
          'ended_at': session.endedAt.toIso8601String(),
          'fraction_read': session.fractionRead,
          'finished': session.finished,
          'hour': session.hour,
          'block_name': session.blockName,
          'energy': session.energy,
          'not_now_reason': session.notNowReason,
        },
        label: 'Study session: ${session.module}',
        view: 'study',
      );
    } catch (_) {}
  }

  Future<List<StudySessionRecord>> getSessions() async {
    final rows = await _db.getStudySessions();
    return rows.map(StudySessionRecord.fromMap).toList();
  }

  Future<int> count() async => _db.getStudySessionCount();

  Future<void> seedTestSessions(int count) async {
    final now = DateTime.now();
    for (var i = 0; i < count; i++) {
      final s = StudySessionRecord(
        module: 'course-$i/lesson.md',
        startedAt: now.subtract(Duration(hours: count - i)),
        endedAt: now.subtract(Duration(hours: count - i, minutes: -20)),
        fractionRead: 1.0,
        finished: true,
        hour: (now.hour - i) % 24,
        blockName: 'focus',
        energy: 7,
      );
      await _db.insertStudySession(s.toMap());
    }
    try {
      await outbox?.enqueue(
        path: '/api/study/sessions',
        body: {
          'action': 'seed',
          'count': count,
          'seeded_at': now.toIso8601String(),
        },
        label: 'Seed $count study sessions',
        view: 'study',
      );
    } catch (_) {}
  }
}
