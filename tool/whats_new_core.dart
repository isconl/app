/// BI26101213: the pure half of the release notes. A commit a user would notice carries trailer lines
///
///     New: <a plain sentence>
///     Improved: <a plain sentence>
///     Fixed: <a plain sentence>
///
/// and this file turns the commits between two releases into the notes: it reads the trailers, groups them,
/// drops exact repeats and keeps commit order. It does no I/O of its own (git and the voice linter come in as
/// functions), so every rule here has a test and the same code runs in CI and under `flutter test`.
library;

import 'dart:convert';

/// A note line is one plain sentence, at most this long.
const int maxNoteChars = 120;

/// How many releases of notes ride along in the asset, so a phone that skipped versions sees what it missed.
const int historyReleases = 10;

const trailerKinds = ['New', 'Improved', 'Fixed'];

/// The notes of one release or one range of commits.
class Notes {
  Notes({List<String>? added, List<String>? improved, List<String>? fixed})
      : added = added ?? <String>[],
        improved = improved ?? <String>[],
        fixed = fixed ?? <String>[];

  final List<String> added;
  final List<String> improved;
  final List<String> fixed;

  bool get isEmpty => added.isEmpty && improved.isEmpty && fixed.isEmpty;

  List<String> forKind(String kind) => switch (kind) {
        'New' => added,
        'Improved' => improved,
        _ => fixed,
      };

  Map<String, dynamic> toJson() => {'new': added, 'improved': improved, 'fixed': fixed};

  static Notes fromJson(Map<String, dynamic> j) => Notes(
        added: _strings(j['new']),
        improved: _strings(j['improved']),
        fixed: _strings(j['fixed']),
      );

  static List<String> _strings(dynamic v) => v is List ? [for (final e in v) if (e is String && e.trim().isNotEmpty) e.trim()] : <String>[];
}

/// One trailer line found in a commit message.
class Trailer {
  const Trailer(this.kind, this.text);
  final String kind;
  final String text;
}

final _trailerLine = RegExp(r'^(New|Improved|Fixed):[ \t]+(\S.*?)[ \t]*$');
final _rowId = RegExp(r'\b[A-Z]{2}\d{8}\b');

/// Every trailer line in [message], in order. Only a line that starts exactly with `New:`, `Improved:` or `Fixed:`
/// counts; anything else in the message is internal and never shown.
List<Trailer> parseTrailers(String message) {
  final out = <Trailer>[];
  for (final raw in message.replaceAll('\r\n', '\n').split('\n')) {
    final m = _trailerLine.firstMatch(raw);
    if (m != null) out.add(Trailer(m.group(1)!, m.group(2)!));
  }
  return out;
}

/// Why a trailer sentence cannot ship, or null when it can. A bad note stops the build rather than reaching a user.
String? noteProblem(Trailer t) {
  if (t.text.length > maxNoteChars) return '${t.kind}: line is ${t.text.length} characters, the limit is $maxNoteChars: "${t.text.substring(0, 40)}..."';
  if (_rowId.hasMatch(t.text)) return '${t.kind}: line names a row id, which means nothing to a user: "${t.text}"';
  return null;
}

class GatherResult {
  GatherResult(this.notes, this.problems);
  final Notes notes;
  final List<String> problems;
}

/// The notes for a list of commit messages, oldest first: trailers grouped by kind, exact repeats dropped, order kept.
GatherResult gather(List<String> messages) {
  final notes = Notes();
  final problems = <String>[];
  for (final msg in messages) {
    for (final t in parseTrailers(msg)) {
      final p = noteProblem(t);
      if (p != null) {
        problems.add(p);
        continue;
      }
      final list = notes.forKind(t.kind);
      if (!list.contains(t.text)) list.add(t.text);
    }
  }
  return GatherResult(notes, problems);
}

/// Every line of [n], for the linter.
List<String> allLines(Notes n) => [...n.added, ...n.improved, ...n.fixed];

/// One release's notes in the asset's history.
class HistoryEntry {
  HistoryEntry(this.version, this.date, this.notes);
  final String version;
  final String date;
  final Notes notes;

  Map<String, dynamic> toJson() => {'version': version, 'date': date, ...notes.toJson()};
}

/// `0.3.88` to `[0, 3, 88]`, or null when it is not a version.
List<int>? parseVersion(String v) {
  final m = RegExp(r'^(\d+)\.(\d+)\.(\d+)').firstMatch(v.trim());
  return m == null ? null : [for (var i = 1; i <= 3; i++) int.parse(m.group(i)!)];
}

int compareVersions(String a, String b) {
  final x = parseVersion(a) ?? const [0, 0, 0];
  final y = parseVersion(b) ?? const [0, 0, 0];
  for (var i = 0; i < 3; i++) {
    if (x[i] != y[i]) return x[i].compareTo(y[i]);
  }
  return 0;
}

/// The release versions among [tags] (`apk-v0.3.88`) that are strictly below [version], newest first, at most [count].
List<String> versionsBelow(List<String> tags, String version, int count) {
  final vs = <String>{
    for (final t in tags)
      if (t.startsWith('apk-v') && parseVersion(t.substring(5)) != null) t.substring(5).trim(),
  }.where((v) => compareVersions(v, version) < 0).toList()
    ..sort((a, b) => compareVersions(b, a));
  return vs.take(count).toList();
}

/// The asset: this release's notes, plus the notes of the last [historyReleases] releases that had any.
Map<String, dynamic> buildReport({required String version, required String date, required Notes current, required List<HistoryEntry> history}) => {
      'version': version,
      'date': date,
      ...current.toJson(),
      'history': [for (final h in history.where((h) => !h.notes.isEmpty).take(historyReleases)) h.toJson()],
    };

/// The release body: grouped lists, or "Maintenance release." when there is nothing to say.
String releaseBody(Notes n) {
  if (n.isEmpty) return 'Maintenance release.';
  final b = StringBuffer();
  void group(String title, List<String> items) {
    if (items.isEmpty) return;
    if (b.isNotEmpty) b.writeln();
    b.writeln('## $title');
    for (final i in items) {
      b.writeln('- $i');
    }
  }

  group('New', n.added);
  group('Improved', n.improved);
  group('Fixed', n.fixed);
  return b.toString().trimRight();
}

/// The report as the file the app bundles.
String reportJson(Map<String, dynamic> report) => '${const JsonEncoder.withIndent('  ').convert(report)}\n';
