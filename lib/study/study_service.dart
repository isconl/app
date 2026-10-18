// The Study screen's pick (BI26101604): builds the scorer's inputs from what is already on the phone and ranks every
// module offline. No network call on this path. Until the generated study index (1/5) is served, the cards come from the
// `learning` snapshot (every course's lessons with their local status), which is the degraded thin index the row asks
// for; once the cache holds a good index, that wins.
import 'dart:convert';

import '../data/db.dart';
import 'pick/index_cache.dart';
import 'pick/models.dart';
import 'pick/profile.dart';
import 'pick/scorer.dart';
import 'pick/study_hash.dart';

/// Stores the study index in the app's snapshot table (a blob per key).
class SnapshotIndexStore implements StudyIndexStore {
  SnapshotIndexStore(this._db);
  final AppDb _db;
  @override
  Future<String?> read(String key) async {
    final r = await _db.getSnapshot(key);
    final v = r?.$1;
    return v is Map ? v['t'] as String? : null;
  }

  @override
  Future<void> write(String key, String value) => _db.putSnapshot(key, {'t': value});

  @override
  Future<void> delete(String key) => _db.putSnapshot(key, {'t': ''});
}

class StudyPickResult {
  const StudyPickResult(this.pick, {this.degraded = false, this.notice, this.titles = const {}});
  final StudyPick pick;
  final bool degraded;
  final String? notice;

  /// card id (`course/file`) -> lesson title, for display.
  final Map<String, String> titles;
}

/// `course/file` is the card id; a track is the course's group.
String cardId(String course, String file) => '$course/$file';

class StudyPickService {
  StudyPickService(this._db, {DateTime Function()? clock, this.bytesOf}) : _clock = clock ?? DateTime.now;
  final AppDb _db;
  final DateTime Function() _clock;

  /// Size in bytes of a downloaded module, when known: the thin index estimates reading minutes from it.
  final int? Function(String course, String file)? bytesOf;

  static const _wordsPerMinuteBytes = 1100; // about 200 words a minute at 5.5 bytes a word
  static const _defaultMinutes = 20;

  /// [learning] is the decoded `learning` snapshot (`{courses: [{ID, GROUP_ID, lessons: [{file, title, status}]}]}`).
  Future<StudyPickResult> pick(Map<String, dynamic> learning, {int? minutesUntilNextBlock, String? nextBlockLabel, int? energy}) async {
    final now = _clock();
    final titles = <String, String>{};
    final thin = <ModuleCard>[];
    final progress = <String, Progress>{};
    final tracks = <String, double>{};
    final courses = (learning['courses'] as List? ?? const []).whereType<Map>();
    for (final c in courses) {
      final course = (c['ID'] ?? c['id'] ?? '').toString();
      final track = (c['GROUP_ID'] ?? course).toString();
      for (final l in (c['lessons'] as List? ?? const []).whereType<Map>()) {
        final file = (l['file'] ?? '').toString();
        if (course.isEmpty || file.isEmpty) continue;
        final id = cardId(course, file);
        titles[id] = (l['title'] ?? file).toString();
        final b = bytesOf?.call(course, file);
        final minutes = b == null || b <= 0 ? _defaultMinutes : (b / _wordsPerMinuteBytes).round().clamp(5, 90);
        thin.add(ModuleCard(id: id, track: track, minutes: minutes));
        final status = (l['status'] ?? '').toString().toLowerCase();
        final done = status == 'done';
        double fraction = done ? 1 : 0;
        if (!done && (status == 'learning' || status == 'opened')) {
          fraction = (await _db.lessonResumeFractionLocal(course: course, file: file)) ?? (status == 'learning' ? 0.3 : 0.05);
        }
        progress[id] = Progress(fraction: fraction, read: done);
        if (!done) tracks[track] = (tracks[track] ?? 0) + minutes;
      }
    }

    final cache = StudyIndexCache(store: SnapshotIndexStore(_db), hash: studyHash, thinIndex: () async => thin);
    final loaded = await cache.load();
    // A good cached index supplies richer cards; progress and titles still come from the snapshot. Cards the
    // snapshot does not know are dropped, so a stale index never offers a module that is gone.
    final cards = loaded.degraded ? thin : loaded.cards.where((c) => titles.containsKey(c.id)).toList();
    final target = now.add(const Duration(days: 26 * 7));
    final inputs = StudyInputs(
      now: now,
      cards: cards,
      progress: progress,
      minutesUntilNextBlock: minutesUntilNextBlock,
      nextBlockLabel: nextBlockLabel,
      energy: energy,
      tracks: {for (final e in tracks.entries) e.key: TrackState(unreadMinutes: e.value, targetDate: target)},
    );
    final pick = pickStudy(inputs, StudyProfile.parse(null));
    return StudyPickResult(pick, degraded: loaded.degraded, notice: loaded.degraded ? loaded.notice : null, titles: titles);
  }

  /// For tests and the "delete the cache" check: drops the stored index so the next pick is degraded.
  Future<void> forgetIndex() async {
    final s = SnapshotIndexStore(_db);
    await s.delete(StudyIndexCache.bodyKey);
    await s.delete(StudyIndexCache.metaKey);
  }

  static String encodeIndex(List<ModuleCard> cards) => jsonEncode({'modules': cards.map((c) => c.toJson()).toList()});
}
