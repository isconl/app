import '../api/client.dart';
import '../util/fmt.dart' as fmt;

/// PI26101601: what a drag teaches slate. A drop above another row asks one question, and slate answers in a sentence.
/// The app never reorders on guesswork: the list is redrawn from slate's order after the answer.
enum RankAnswer { urgent, valuable, once }

extension RankAnswerText on RankAnswer {
  String get wire => name;
  String get label => switch (this) { RankAnswer.urgent => 'More urgent', RankAnswer.valuable => 'More valuable', RankAnswer.once => 'Just this once' };
}

/// One thing slate has learned from past drags, with the day it fades.
class LearnedAdjustment {
  const LearnedAdjustment({required this.id, required this.sentence, this.fadesAt});
  factory LearnedAdjustment.from(Map<String, dynamic> m) => LearnedAdjustment(id: fmt.i(m['id']), sentence: fmt.s(m['sentence']), fadesAt: DateTime.tryParse(fmt.s(m['fadesAt'])));
  final int id;
  final String sentence;
  final DateTime? fadesAt;

  String get fadeLine => fadesAt == null ? '' : 'Fades ${fadesAt!.toIso8601String().substring(0, 10)}';
}

abstract class RankApi {
  Future<List<LearnedAdjustment>> adjustments();
  Future<void> undo(int id);
}

class HttpRankApi implements RankApi {
  HttpRankApi(this.api);
  final ApiClient api;

  @override
  Future<List<LearnedAdjustment>> adjustments() async =>
      [for (final m in fmt.lm(fmt.m(await api.getJson('/api/rank/adjustments'))['adjustments'])) LearnedAdjustment.from(m)];

  @override
  Future<void> undo(int id) async {
    await api.postJson('/api/rank/adjustments/$id/undo', {});
  }
}

/// The row the dragged one now sits above, from the list as it was before the drop. Null when dropped at the end.
/// [newIndex] is Flutter's `onReorder` value (already shifted when moving down, so it is a position in the old list
/// with the moved item removed).
String? rowAbove(List<String> idsBefore, int oldIndex, int newIndex) {
  final rest = [...idsBefore]..removeAt(oldIndex);
  final at = newIndex > oldIndex ? newIndex - 1 : newIndex;
  return at >= 0 && at < rest.length ? rest[at] : null;
}
