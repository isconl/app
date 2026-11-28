import '../api/client.dart';

/// BI26101109: spaced recall. Three short questions per finished module come back on day 1, 7 and 30; one tap per
/// answer; a miss offers to reopen the module at the section the question came from.
///
/// Live only for now: the question's answer is deliberately not sent down with it (so a prompt cannot be answered by
/// reading the payload), which means a question is judged by the hub, so this needs a connection to answer.

class RecallPrompt {
  const RecallPrompt({required this.qId, required this.course, required this.lesson, required this.question, required this.choices, this.generated = false});
  final String qId;
  final String course;
  final String lesson;
  final String question;
  final List<String> choices;

  /// Drafted by the model rather than written in the module: shown with a small tag so a bad one can be flagged.
  final bool generated;
}

class RecallReopen {
  const RecallReopen(this.course, this.lesson, this.anchor);
  final String course;
  final String lesson;
  final String anchor;
}

class RecallResult {
  const RecallResult({required this.correct, required this.answer, this.why = '', this.reopen, this.retired = false});
  final bool correct;
  final String answer;
  final String why;
  final RecallReopen? reopen;
  final bool retired;
}

class RecallSummary {
  const RecallSummary({this.dueToday = 0, this.retiredThisMonth = 0});
  final int dueToday;
  final int retiredThisMonth;

  /// "Recall: 3 due today, 2 retired this month".
  String get line => 'Recall: $dueToday due today, $retiredThisMonth retired this month';
}

abstract class RecallApi {
  Future<List<RecallPrompt>> due();
  Future<RecallSummary> summary();
  Future<RecallResult> answer(String qId, int choice);

  /// "This question is wrong": removes it and drafts a replacement.
  Future<void> flag(String qId);
}

class HubRecallApi implements RecallApi {
  HubRecallApi(this.api);
  final ApiClient api;

  static Map<String, dynamic> _m(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  static List<dynamic> _l(Object? v) => v is List ? v : const [];
  static String _s(Object? v) => v == null || v == '-' ? '' : '$v';
  static int _i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

  @override
  Future<List<RecallPrompt>> due() async {
    final d = _m(await api.getJson('/api/study/recall/due'));
    return [
      for (final p in _l(d['prompts']))
        RecallPrompt(
          qId: _s(_m(p)['qId']),
          course: _s(_m(p)['course']),
          lesson: _s(_m(p)['lesson']),
          question: _s(_m(p)['question']),
          choices: [for (final c in _l(_m(p)['choices'])) '$c'],
          generated: _s(_m(p)['source']) == 'generated',
        ),
    ];
  }

  @override
  Future<RecallSummary> summary() async {
    final d = _m(await api.getJson('/api/study/recall/summary'));
    return RecallSummary(dueToday: _i(d['dueToday']), retiredThisMonth: _i(d['retiredThisMonth']));
  }

  @override
  Future<RecallResult> answer(String qId, int choice) async {
    final d = _m(await api.postJson('/api/study/recall/answer', {'q_id': qId, 'choice': choice}, cold: true));
    if (d['error'] != null) throw ApiException(0, _s(d['error']));
    final r = _m(d['reopen']);
    return RecallResult(
      correct: d['correct'] == true,
      answer: _s(d['answer']),
      why: _s(d['why']),
      retired: d['retired'] == true,
      reopen: r.isEmpty ? null : RecallReopen(_s(r['course']), _s(r['lesson']), _s(r['anchor'])),
    );
  }

  @override
  Future<void> flag(String qId) async {
    final d = _m(await api.postJson('/api/study/recall/flag', {'q_id': qId}, cold: true));
    if (d['error'] != null) throw ApiException(0, _s(d['error']));
  }
}
