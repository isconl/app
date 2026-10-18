// Study assistant 3/5 (BI26101604): the data the on-phone scorer reads. Pure Dart, no Flutter imports, so every
// rule is unit-testable and the same golden vectors can run in abacus (profile isconl.study@1).

/// One machine card from the study index (1/5): what the scorer needs to know about a module without opening it.
class ModuleCard {
  final String id;
  final String track;
  final List<String> subjects;
  final List<String> prerequisites;
  final int minutes;
  final int difficulty; // 1 (easiest) to 5
  final String version;
  final bool archived;
  const ModuleCard({
    required this.id,
    required this.track,
    this.subjects = const [],
    this.prerequisites = const [],
    required this.minutes,
    this.difficulty = 3,
    this.version = '',
    this.archived = false,
  });

  factory ModuleCard.fromJson(Map<String, dynamic> j) => ModuleCard(
        id: j['id'] as String,
        track: (j['track'] ?? '') as String,
        subjects: _strings(j['subjects']),
        prerequisites: _strings(j['prerequisites']),
        minutes: (j['minutes'] as num?)?.toInt() ?? 0,
        difficulty: (j['difficulty'] as num?)?.toInt() ?? 3,
        version: (j['version'] ?? '') as String,
        archived: j['archived'] == true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'track': track,
        'subjects': subjects,
        'prerequisites': prerequisites,
        'minutes': minutes,
        'difficulty': difficulty,
        'version': version,
        'archived': archived,
      };
}

List<String> _strings(Object? v) => v is List ? v.map((e) => e.toString()).toList() : const [];

/// What the reader has done with a module.
class Progress {
  final double fraction; // 0 to 1
  final bool read;
  final bool probeWeak; // the PROBE self-check was marked weak
  final DateTime? weakMarkedAt; // when it was marked weak, or last reviewed
  final int reviewsDone;
  const Progress({this.fraction = 0, this.read = false, this.probeWeak = false, this.weakMarkedAt, this.reviewsDone = 0});

  factory Progress.fromJson(Map<String, dynamic> j) => Progress(
        fraction: (j['fraction'] as num?)?.toDouble() ?? 0,
        read: j['read'] == true,
        probeWeak: j['probeWeak'] == true,
        weakMarkedAt: j['weakMarkedAt'] == null ? null : DateTime.parse(j['weakMarkedAt'] as String),
        reviewsDone: (j['reviewsDone'] as num?)?.toInt() ?? 0,
      );
}

/// One finished or abandoned study session (the log from 5/5).
class StudySession {
  final DateTime startedAt;
  final bool completed;
  const StudySession(this.startedAt, this.completed);
}

/// A calendar event or task: only its subjects matter to the pick.
class SubjectMention {
  final List<String> subjects;
  final DateTime? at;
  const SubjectMention(this.subjects, [this.at]);
}

/// One track's pace state, supplied by the caller from local data.
class TrackState {
  final double unreadMinutes;
  final DateTime targetDate; // default: 26 weeks from first run
  final double minutesReadThisCycle;
  final double cyclesBehind; // how many cycles of its pace the track is behind
  final bool pickedThisCycle;
  const TrackState({
    required this.unreadMinutes,
    required this.targetDate,
    this.minutesReadThisCycle = 0,
    this.cyclesBehind = 0,
    this.pickedThisCycle = false,
  });
}

/// Where the reader is in the current cycle (/api/cycle-theme).
class CycleInfo {
  final int lengthDays;
  final int dayOfCycle; // 1-based
  final List<String> themeSubjects;
  const CycleInfo({this.lengthDays = 7, this.dayOfCycle = 1, this.themeSubjects = const []});
  bool get lastTwoDays => dayOfCycle >= lengthDays - 1;
}

/// Everything the scorer reads. All of it is local; building it never touches the network.
class StudyInputs {
  final DateTime now;
  final List<ModuleCard> cards;
  final Map<String, Progress> progress;
  final List<StudySession> sessions;
  final int? minutesUntilNextBlock; // null: nothing scheduled, a default window applies
  final int? energy; // 1 to 10, from a journal entry under six hours old, else null
  final List<SubjectMention> events; // next 48 hours
  final List<SubjectMention> tasks; // open tasks
  final Set<String> announced; // module ids named by a live campus announcement
  final Map<String, TrackState> tracks;
  final CycleInfo cycle;
  final String? nextBlockLabel; // "15:00", shown in the reason
  const StudyInputs({
    required this.now,
    required this.cards,
    this.progress = const {},
    this.sessions = const [],
    this.minutesUntilNextBlock,
    this.energy,
    this.events = const [],
    this.tasks = const [],
    this.announced = const {},
    this.tracks = const {},
    this.cycle = const CycleInfo(),
    this.nextBlockLabel,
  });

  factory StudyInputs.fromJson(Map<String, dynamic> j) {
    final tr = <String, TrackState>{};
    (j['tracks'] as Map<String, dynamic>? ?? {}).forEach((k, v) {
      final m = v as Map<String, dynamic>;
      tr[k] = TrackState(
        unreadMinutes: (m['unreadMinutes'] as num).toDouble(),
        targetDate: DateTime.parse(m['targetDate'] as String),
        minutesReadThisCycle: (m['minutesReadThisCycle'] as num?)?.toDouble() ?? 0,
        cyclesBehind: (m['cyclesBehind'] as num?)?.toDouble() ?? 0,
        pickedThisCycle: m['pickedThisCycle'] == true,
      );
    });
    List<SubjectMention> mentions(Object? v) =>
        (v as List? ?? []).map((e) => SubjectMention(_strings((e as Map)['subjects']))).toList();
    final c = j['cycle'] as Map<String, dynamic>?;
    return StudyInputs(
      now: DateTime.parse(j['now'] as String),
      cards: (j['cards'] as List).map((e) => ModuleCard.fromJson(e as Map<String, dynamic>)).toList(),
      progress: {
        for (final e in (j['progress'] as Map<String, dynamic>? ?? {}).entries) e.key: Progress.fromJson(e.value as Map<String, dynamic>)
      },
      sessions: (j['sessions'] as List? ?? [])
          .map((e) => StudySession(DateTime.parse((e as Map)['startedAt'] as String), e['completed'] == true))
          .toList(),
      minutesUntilNextBlock: (j['minutesUntilNextBlock'] as num?)?.toInt(),
      energy: (j['energy'] as num?)?.toInt(),
      events: mentions(j['events']),
      tasks: mentions(j['tasks']),
      announced: _strings(j['announced']).toSet(),
      tracks: tr,
      cycle: c == null
          ? const CycleInfo()
          : CycleInfo(
              lengthDays: (c['lengthDays'] as num?)?.toInt() ?? 7,
              dayOfCycle: (c['dayOfCycle'] as num?)?.toInt() ?? 1,
              themeSubjects: _strings(c['themeSubjects'])),
      nextBlockLabel: j['nextBlockLabel'] as String?,
    );
  }
}
