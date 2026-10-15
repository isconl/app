import 'package:flutter/foundation.dart';

import '../api/client.dart';

/// BI26101214: the study routes the console has and the app lacked, through hub.

class CampusItem {
  const CampusItem({
    required this.courseId,
    required this.title,
    required this.courseTitle,
    this.lesson = '',
    this.minutes = 0,
    this.headline = '',
    this.why = '',
    this.done = false,
  });
  final String courseId;
  final String lesson;
  final String title;
  final String courseTitle;
  final int minutes;
  final String headline;
  final String why;
  final bool done;
}

class CampusBand {
  const CampusBand({required this.label, required this.tone, required this.items});
  final String label;
  final String tone;
  final List<CampusItem> items;
}

/// What to read right now, and why: courses in bands (urgent, soon, later).
class Campus {
  const Campus({required this.bands, this.minutes = 0, this.computed = false, this.updatedAt = ''});
  final List<CampusBand> bands;

  /// About how long the urgent ones take.
  final int minutes;

  /// True when no standing advice is set and this is the computed next step.
  final bool computed;
  final String updatedAt;

  bool get isEmpty => bands.isEmpty || bands.every((b) => b.items.isEmpty);
}

/// One day of a contribution map: the date and how many.
class ContribDay {
  const ContribDay(this.date, this.count);
  final String date;
  final int count;
}

class Contributions {
  const Contributions({required this.days, required this.total});
  final List<ContribDay> days;
  final int total;

  int get activeDays => days.where((d) => d.count > 0).length;

  /// The run of active days ending today (or the last day the map has).
  int get streak {
    var s = 0;
    for (var i = days.length - 1; i >= 0 && days[i].count > 0; i--) {
      s++;
    }
    return s;
  }

  /// Intensity 0 to 4 for a count, relative to the busiest day, as the console buckets it.
  int level(int count) {
    if (count <= 0) return 0;
    final max = days.fold<int>(0, (m, d) => d.count > m ? d.count : m);
    if (max <= 0) return 0;
    if (count >= max * 0.75) return 4;
    if (count >= max * 0.5) return 3;
    if (count >= max * 0.25) return 2;
    return 1;
  }
}

/// The module the task's words match best (`/api/learning/prime`).
class PrimeResult {
  const PrimeResult({required this.ok, this.course = '', this.file = '', this.content = '', this.error = ''});
  final bool ok;
  final String course;
  final String file;
  final String content;
  final String error;
}

abstract class StudyExtrasApi {
  Future<Campus> campus();
  Future<Contributions> studyContributions();
  Future<Contributions> githubContributions({bool refresh = false});
  Future<PrimeResult> prime(String query);

  /// Asks about the open module. Hub reads the module itself and calls the AI through link;
  /// the app sends only the question and which module it is about. Returns the answer in markdown.
  Future<String> tutor({required String course, required String file, required String question});
}

class HubStudyExtrasApi implements StudyExtrasApi {
  HubStudyExtrasApi(this.api);
  final ApiClient api;

  static Map<String, dynamic> _m(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  static List<dynamic> _l(Object? v) => v is List ? v : const [];
  static int _i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

  @visibleForTesting
  static Campus parseCampus(Object? res) {
    final c = _m(res);
    return Campus(
      minutes: _i(c['minutes']),
      computed: c['computed'] == true,
      updatedAt: '${c['updatedAt'] ?? ''}',
      bands: [
        for (final b in _l(c['bands']))
          if (b is Map)
            CampusBand(
              label: '${b['label'] ?? ''}',
              tone: '${b['tone'] ?? ''}',
              items: [
                for (final i in _l(b['items']))
                  if (i is Map)
                    CampusItem(
                      courseId: '${i['courseId'] ?? ''}',
                      lesson: '${i['lesson'] ?? ''}',
                      title: '${i['title'] ?? ''}',
                      courseTitle: '${i['courseTitle'] ?? ''}',
                      minutes: _i(i['minutes']),
                      headline: '${i['headline'] ?? ''}',
                      why: '${i['why'] ?? ''}',
                      done: i['status'] == 'done',
                    ),
              ],
            ),
      ],
    );
  }

  @visibleForTesting
  static Contributions parseContributions(Object? res) {
    final c = _m(res);
    final days = [
      for (final d in _l(c['days']))
        if (d is Map) ContribDay('${d['date'] ?? ''}', _i(d['count'])),
    ];
    final total = c['totalContributions'] != null ? _i(c['totalContributions']) : days.fold<int>(0, (a, d) => a + d.count);
    return Contributions(days: days, total: total);
  }

  @override
  Future<Campus> campus() async => parseCampus(await api.getJson('/api/learning/campus'));

  @override
  Future<Contributions> studyContributions() async => parseContributions(await api.getJson('/api/learning/contributions'));

  @override
  Future<Contributions> githubContributions({bool refresh = false}) async =>
      parseContributions(await api.getJson('/api/github/contributions${refresh ? '?refresh=1' : ''}'));

  @override
  Future<PrimeResult> prime(String query) async {
    final p = _m(await api.getJson('/api/learning/prime?q=${Uri.encodeQueryComponent(query)}'));
    return PrimeResult(
      ok: p['ok'] == true,
      course: '${p['course'] ?? ''}',
      file: '${p['file'] ?? ''}',
      content: '${p['content'] ?? ''}',
      error: '${p['error'] ?? ''}',
    );
  }

  @override
  Future<String> tutor({required String course, required String file, required String question}) async {
    final d = _m(await api.postJson('/api/learning/tutor', {'course': course, 'file': file, 'question': question}, cold: true));
    if (d['success'] != true) throw ApiException(0, '${d['error'] ?? 'No answer available'}');
    return '${d['answer'] ?? ''}';
  }
}

/// The question the tutor receives for a long-pressed paragraph: the passage first, so the
/// answer is about that passage and not the module in general.
String tutorQuestion(String paragraph, String question) {
  final p = paragraph.trim().replaceAll(RegExp(r'\s+'), ' ');
  final quote = p.length > 400 ? '${p.substring(0, 397)}...' : p;
  return 'About this passage from the module: "$quote"\n\n${question.trim()}';
}

/// The tutor's answers, kept per paragraph (by the reader's block index) so each shows
/// under the paragraph it was asked about, and a new question on the same paragraph
/// replaces its answer.
class TutorController extends ChangeNotifier {
  TutorController({required this.api, required this.course, required this.file});
  final StudyExtrasApi api;
  final String course;
  final String file;

  /// While on, every paragraph shows an Ask button (long-press works too).
  bool mode = false;

  void toggleMode() {
    mode = !mode;
    notifyListeners();
  }

  final Map<int, String> answers = {};
  final Map<int, String> errors = {};
  final Set<int> thinking = {};

  Future<void> ask(int paragraph, String text, String question) async {
    if (question.trim().isEmpty) return;
    thinking.add(paragraph);
    errors.remove(paragraph);
    notifyListeners();
    try {
      answers[paragraph] = await api.tutor(course: course, file: file, question: tutorQuestion(text, question));
    } catch (e) {
      errors[paragraph] = '$e'.replaceFirst('ApiException(0): ', '');
    } finally {
      thinking.remove(paragraph);
      notifyListeners();
    }
  }

  void dismiss(int paragraph) {
    answers.remove(paragraph);
    errors.remove(paragraph);
    notifyListeners();
  }
}
