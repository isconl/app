import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/db.dart';
import 'fmt.dart' as fmt;

/// BI26100145: spaced review. A finished module comes back 1, 7 and 30 days
/// after it was finished. A miss brings it back in 3 days instead; a perfect
/// round moves it on, and a perfect round after the 30-day review retires it.
/// The schedule lives on this device for now (the shared review_schedule
/// collection is a separate row).
const reviewIntervals = [1, 7, 30];
const missRetryDays = 3;
const maxModulesPerDay = 3;
const maxQuestionsPerModule = 3;

class ReviewItem {
  ReviewItem({
    required this.course,
    required this.file,
    required this.title,
    required this.finishedOn,
    this.step = 0,
    required this.due,
    this.retired = false,
    this.last = const [],
    this.history = const [],
  });

  final String course;
  final String file;
  final String title;
  final DateTime finishedOn;

  /// 0, 1 or 2: which of the three reviews is next.
  final int step;
  final DateTime due;
  final bool retired;

  /// The questions asked last time, so the same set is not asked twice running.
  final List<String> last;
  final List<Map<String, dynamic>> history;

  String get key => '$course/$file';

  ReviewItem copyWith({int? step, DateTime? due, bool? retired, List<String>? last, List<Map<String, dynamic>>? history}) => ReviewItem(
        course: course,
        file: file,
        title: title,
        finishedOn: finishedOn,
        step: step ?? this.step,
        due: due ?? this.due,
        retired: retired ?? this.retired,
        last: last ?? this.last,
        history: history ?? this.history,
      );

  Map<String, dynamic> toJson() => {
        'course': course,
        'file': file,
        'title': title,
        'finishedOn': fmt.isoDate(finishedOn),
        'step': step,
        'due': fmt.isoDate(due),
        'retired': retired,
        'last': last,
        'history': history,
      };

  static ReviewItem? fromJson(dynamic j) {
    if (j is! Map) return null;
    final fin = fmt.parseDate(j['finishedOn']);
    final due = fmt.parseDate(j['due']);
    if (fin == null || due == null) return null;
    return ReviewItem(
      course: fmt.s(j['course']),
      file: fmt.s(j['file']),
      title: fmt.s(j['title']),
      finishedOn: DateTime(fin.year, fin.month, fin.day),
      step: (j['step'] is int ? j['step'] as int : 0).clamp(0, 2),
      due: DateTime(due.year, due.month, due.day),
      retired: j['retired'] == true,
      last: [for (final q in (j['last'] is List ? j['last'] as List : const [])) '$q'],
      history: [for (final h in (j['history'] is List ? j['history'] as List : const [])) if (h is Map) Map<String, dynamic>.from(h)],
    );
  }
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// A module just finished: its first review is due the next day.
ReviewItem enrolFinished({required String course, required String file, required String title, required DateTime now}) {
  final d = _day(now);
  return ReviewItem(
    course: course,
    file: file,
    title: title,
    finishedOn: d,
    due: DateTime(d.year, d.month, d.day + reviewIntervals[0]),
  );
}

/// The schedule after a round. Perfect advances (next due is the next interval
/// counted from the finish date, never earlier than tomorrow); a miss comes
/// back in [missRetryDays] days at the same step. A perfect third review retires the module.
ReviewItem afterRound(ReviewItem item, {required bool perfect, required DateTime now, List<String> asked = const []}) {
  final today = _day(now);
  final entry = {'on': fmt.isoDate(today), 'step': item.step, 'perfect': perfect};
  final history = [...item.history, entry];
  if (!perfect) {
    return item.copyWith(due: DateTime(today.year, today.month, today.day + missRetryDays), last: asked, history: history);
  }
  if (item.step >= reviewIntervals.length - 1) {
    return item.copyWith(retired: true, last: asked, history: history);
  }
  final next = item.step + 1;
  var due = DateTime(item.finishedOn.year, item.finishedOn.month, item.finishedOn.day + reviewIntervals[next]);
  final tomorrow = DateTime(today.year, today.month, today.day + 1);
  if (due.isBefore(tomorrow)) due = tomorrow;
  return item.copyWith(step: next, due: due, last: asked, history: history);
}

/// Modules due on [now] (or overdue), oldest first, at most [maxModulesPerDay]. The rest roll to a later day.
List<ReviewItem> dueToday(Iterable<ReviewItem> items, DateTime now) {
  final today = _day(now);
  final due = [for (final i in items) if (!i.retired && !i.due.isAfter(today)) i]..sort((a, b) => a.due.compareTo(b.due));
  return due.take(maxModulesPerDay).toList();
}

/// The questions in a module worth asking again: the PROBE prompt(s), then any
/// "Check yourself" / "Open questions" items that are questions.
List<String> extractQuestions(String markdown) {
  final out = <String>[];
  final lines = markdown.split('\n');
  String? section;
  final buf = <String>[];

  void flushProbe() {
    final text = buf.join(' ').trim();
    if (text.isNotEmpty) out.add(text);
    buf.clear();
  }

  for (final raw in lines) {
    final line = raw.trimRight();
    if (line.startsWith('## ')) {
      if (section == 'probe') flushProbe();
      final h = line.substring(3).toLowerCase();
      section = h.startsWith('probe')
          ? 'probe'
          : (h.startsWith('check yourself') || h.startsWith('open questions'))
              ? 'quiz'
              : null;
      continue;
    }
    if (section == 'probe') {
      if (line.startsWith('**Probe:**')) {
        flushProbe();
        buf.add(line.substring('**Probe:**'.length).trim());
      } else if (line.trim().isEmpty) {
        if (buf.isNotEmpty) flushProbe();
      } else if (buf.isNotEmpty) {
        buf.add(line.trim());
      }
    } else if (section == 'quiz') {
      final m = RegExp(r'^\s*(?:[-*]|\d+[.)])\s+(.*\?)\s*$').firstMatch(line);
      if (m != null) out.add(m[1]!.trim());
    }
  }
  if (section == 'probe') flushProbe();
  return out;
}

/// Up to [n] questions, at random, avoiding the set asked [last] time when there are enough to choose from.
List<String> pickQuestions(List<String> candidates, {List<String> last = const [], Random? rng, int n = maxQuestionsPerModule}) {
  if (candidates.length <= n) return List.of(candidates);
  final r = rng ?? Random();
  for (var attempt = 0; attempt < 8; attempt++) {
    final pool = List.of(candidates)..shuffle(r);
    final pick = pool.take(n).toList();
    if (!setEquals(pick.toSet(), last.toSet())) return pick;
  }
  return (List.of(candidates)..shuffle(r)).take(n).toList();
}

/// "Review: 6 questions, 4 minutes": about 40 seconds a question, never under a minute.
String reviewSummary(int questions) {
  final minutes = max(1, (questions * 40 / 60).ceil());
  return 'Review: $questions question${questions == 1 ? '' : 's'}, $minutes minute${minutes == 1 ? '' : 's'}';
}

/// The schedule, kept on the device.
class SpacedReview extends ChangeNotifier {
  SpacedReview._();
  static final SpacedReview instance = SpacedReview._();

  @visibleForTesting
  SpacedReview.forTesting();

  static const _key = 'review.schedule.v1';
  final _items = <String, ReviewItem>{};
  bool _loaded = false;

  List<ReviewItem> get items => List.unmodifiable(_items.values);

  Future<void> ensureLoaded(AppDb db) async {
    if (_loaded) return;
    _loaded = true;
    try {
      final v = (await db.getSnapshot(_key))?.$1;
      if (v is List) {
        for (final j in v) {
          final i = ReviewItem.fromJson(j);
          if (i != null) _items[i.key] = i;
        }
        notifyListeners();
      }
    } catch (_) {
      // Nothing stored: no reviews yet.
    }
  }

  Future<void> _save(AppDb? db) async {
    if (db == null) return;
    try {
      await db.putSnapshot(_key, [for (final i in _items.values) i.toJson()]);
    } catch (_) {}
  }

  /// A module was finished. Finishing it again restarts its schedule.
  Future<void> enrol({required String course, required String file, required String title, required DateTime now, AppDb? db}) async {
    final item = enrolFinished(course: course, file: file, title: title, now: now);
    _items[item.key] = item;
    notifyListeners();
    await _save(db);
  }

  /// The user undid "done" within the grace period.
  Future<void> withdraw(String course, String file, {AppDb? db}) async {
    if (_items.remove('$course/$file') == null) return;
    notifyListeners();
    await _save(db);
  }

  Future<void> record(String key, {required bool perfect, required DateTime now, List<String> asked = const [], AppDb? db}) async {
    final cur = _items[key];
    if (cur == null) return;
    _items[key] = afterRound(cur, perfect: perfect, now: now, asked: asked);
    notifyListeners();
    await _save(db);
  }
}
