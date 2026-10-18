// The on-phone study scorer (BI26101604). Ranks every module from local data each time Study opens: offline, no
// network call on this path, a one-line reason per pick built from its two largest score parts. No mood is inferred
// from behaviour: energy comes only from a logged journal entry the caller passes in.
import 'models.dart';
import 'profile.dart';

class ScorePart {
  final String name; // coverage, momentum, fit, relevance, review, announcement
  final double raw; // 0 to 1
  final double weight;
  const ScorePart(this.name, this.raw, this.weight);
  double get value => raw * weight;
  Map<String, dynamic> toJson() => {'name': name, 'raw': _r(raw), 'weight': _r(weight), 'value': _r(value)};
}

double _r(double v) => (v * 1000).round() / 1000;

class Recommendation {
  final ModuleCard card;
  final double score;
  final String reason;
  final List<ScorePart> parts;
  const Recommendation(this.card, this.score, this.reason, this.parts);
  Map<String, dynamic> toJson() => {'id': card.id, 'score': _r(score), 'reason': reason, 'parts': parts.map((p) => p.toJson()).toList()};
}

class StudyPick {
  final Recommendation? top;
  final Recommendation? lighter;
  final Recommendation? deeper;
  final int candidates;
  const StudyPick({this.top, this.lighter, this.deeper, this.candidates = 0});
  Map<String, dynamic> toJson() => {
        'top': top?.toJson(),
        'lighter': lighter?.toJson(),
        'deeper': deeper?.toJson(),
        'candidates': candidates,
      };
}

const _partOrder = ['fit', 'coverage', 'review', 'announcement', 'relevance', 'momentum'];

StudyPick pickStudy(StudyInputs inp, StudyProfile prof) {
  final read = <String>{for (final e in inp.progress.entries) if (e.value.read) e.key};
  final window = inp.minutesUntilNextBlock ?? prof.defaultWindowMinutes;
  final hourRate = _hourRate(inp, prof);
  final eventSubjects = {for (final e in inp.events) ...e.subjects};
  final taskSubjects = {for (final t in inp.tasks) ...t.subjects};
  final themeSubjects = inp.cycle.themeSubjects.toSet();
  final starved = <String>{
    if (inp.cycle.lastTwoDays) for (final e in inp.tracks.entries) if (!e.value.pickedThisCycle) e.key
  };

  final scored = <Recommendation>[];
  for (final c in inp.cards) {
    if (c.archived) continue;
    final pr = inp.progress[c.id];
    if (c.prerequisites.any((p) => !read.contains(p))) continue;
    var reviewDue = false;
    if (pr != null && pr.read) {
      reviewDue = _reviewDue(pr, inp.now, prof);
      if (!reviewDue) continue;
    }

    final ts = inp.tracks[c.track];
    final behind = ts != null && ts.cyclesBehind > 1;
    final covW = prof.coverage * (behind ? prof.coverageOverride : 1);
    final parts = <ScorePart>[
      ScorePart('fit', _fit(c, window, inp.energy, hourRate), prof.fit),
      ScorePart('coverage', _coverage(ts, inp.now, inp.cycle), covW),
      ScorePart('review', reviewDue ? 1 : 0, prof.review),
      ScorePart('announcement', inp.announced.contains(c.id) ? 1 : 0, prof.announcement),
      ScorePart('relevance', _relevance(c, eventSubjects, taskSubjects, themeSubjects), prof.relevance),
      ScorePart('momentum', (pr != null && pr.fraction >= 0.1 && pr.fraction <= 0.9) ? 1 : 0, prof.momentum),
    ];
    var total = 0.0;
    for (final p in parts) {
      total += p.value;
    }
    if (starved.contains(c.track)) total += prof.trackGuarantee;
    scored.add(Recommendation(c, total, _reason(c, parts, ts, pr, window, inp), parts));
  }
  if (scored.isEmpty) return const StudyPick();
  scored.sort((a, b) {
    final d = b.score.compareTo(a.score);
    return d != 0 ? d : a.card.id.compareTo(b.card.id);
  });
  final top = scored.first;
  Recommendation? lighter, deeper;
  for (final r in scored.skip(1)) {
    final c = r.card, t = top.card;
    final isLighter = c.minutes <= t.minutes && c.difficulty <= t.difficulty && (c.minutes < t.minutes || c.difficulty < t.difficulty);
    final isDeeper = c.minutes >= t.minutes && c.difficulty >= t.difficulty && (c.minutes > t.minutes || c.difficulty > t.difficulty);
    if (isLighter && lighter == null) lighter = r;
    if (isDeeper && deeper == null) deeper = r;
    if (lighter != null && deeper != null) break;
  }
  return StudyPick(top: top, lighter: lighter, deeper: deeper, candidates: scored.length);
}

bool _reviewDue(Progress p, DateTime now, StudyProfile prof) {
  if (!p.probeWeak || p.weakMarkedAt == null) return false;
  final i = p.reviewsDone < prof.reviewCurveDays.length ? p.reviewsDone : prof.reviewCurveDays.length - 1;
  return now.difference(p.weakMarkedAt!).inHours >= prof.reviewCurveDays[i] * 24;
}

double _fit(ModuleCard c, int window, int? energy, double? hourRate) {
  if (window <= 0 || c.minutes > window) return 0;
  var f = 0.5 + 0.5 * (c.minutes / window);
  if (energy != null && energy < 4) {
    if (c.difficulty <= 1) {
      f += 0.3;
    } else if (c.difficulty >= 3) {
      f -= 0.3;
    }
  }
  if (hourRate != null) f *= 0.5 + hourRate;
  return f.clamp(0.0, 1.0);
}

double? _hourRate(StudyInputs inp, StudyProfile prof) {
  if (inp.sessions.length < prof.hourlyRateMinSessions) return null;
  var n = 0, done = 0;
  for (final s in inp.sessions) {
    if (s.startedAt.hour != inp.now.hour) continue;
    n++;
    if (s.completed) done++;
  }
  return n == 0 ? null : done / n;
}

double _coverage(TrackState? ts, DateTime now, CycleInfo cycle) {
  if (ts == null) return 0;
  final daysLeft = ts.targetDate.difference(now).inHours / 24.0;
  final cyclesLeft = (daysLeft / cycle.lengthDays).clamp(1.0, double.infinity);
  final target = ts.unreadMinutes / cyclesLeft;
  if (target <= 0) return 0;
  final debt = (target - ts.minutesReadThisCycle).clamp(0.0, double.infinity);
  return (debt / target).clamp(0.0, 1.0);
}

double _relevance(ModuleCard c, Set<String> events, Set<String> tasks, Set<String> theme) {
  var hits = 0;
  if (c.subjects.any(events.contains)) hits++;
  if (c.subjects.any(tasks.contains)) hits++;
  if (c.subjects.any(theme.contains)) hits++;
  return hits / 3;
}

String _reason(ModuleCard c, List<ScorePart> parts, TrackState? ts, Progress? pr, int window, StudyInputs inp) {
  final live = parts.where((p) => p.value > 0).toList()
    ..sort((a, b) {
      final d = b.value.compareTo(a.value);
      return d != 0 ? d : _partOrder.indexOf(a.name).compareTo(_partOrder.indexOf(b.name));
    });
  if (live.isEmpty) return 'next in ${c.track.isEmpty ? 'your course' : c.track}';
  return live.take(2).map((p) => _phrase(p.name, c, ts, pr, window, inp)).join('; ');
}

String _phrase(String part, ModuleCard c, TrackState? ts, Progress? pr, int window, StudyInputs inp) {
  switch (part) {
    case 'fit':
      return inp.minutesUntilNextBlock != null && inp.nextBlockLabel != null
          ? 'fits the $window minutes before your ${inp.nextBlockLabel} block'
          : 'fits the $window minutes you have';
    case 'coverage':
      final b = ts?.cyclesBehind ?? 0;
      if (b >= 1) {
        final n = b.round();
        return '${c.track} is $n ${n == 1 ? 'cycle' : 'cycles'} behind';
      }
      return "${c.track} is behind this cycle's pace";
    case 'momentum':
      return 'you are ${((pr?.fraction ?? 0) * 100).round()}% through it';
    case 'relevance':
      if (inp.events.any((e) => e.subjects.any(c.subjects.contains))) return 'matches an event in the next two days';
      if (inp.tasks.any((e) => e.subjects.any(c.subjects.contains))) return 'matches an open task';
      return "matches this cycle's theme";
    case 'review':
      return 'due for review';
    case 'announcement':
      return 'named in a campus announcement';
  }
  return part;
}
