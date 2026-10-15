/// BI26101213: gathers the release notes at build time. Pure Dart, no network, no AI.
///
///   dart tool/whats_new.dart [--version X.Y.Z] [--head REF] [--out assets/whats_new.json] [--md build/whats_new.md]
///
/// Reads the commit trailers (`New:`, `Improved:`, `Fixed:`) between the previous `apk-v*` release tag and HEAD,
/// writes `assets/whats_new.json` (this release plus the last ten releases' notes, bundled in the APK) and
/// `build/whats_new.md` (the release body). Every note line goes through the vendored voice linter
/// (`tools/voice-lint/voice-lint.js`, needs `node`); a line that fails it, is too long or names a row id stops
/// the build, so a bad note never ships. With no trailers the current entry is empty.
library;

import 'dart:convert';
import 'dart:io';

import 'whats_new_core.dart';

/// Run git and return its output, or throw.
String git(List<String> args) {
  final r = Process.runSync('git', args, stdoutEncoding: utf8, stderrEncoding: utf8);
  if (r.exitCode != 0) throw StateError('git ${args.join(' ')} failed: ${r.stderr}');
  return r.stdout as String;
}

/// The messages of the commits in [range], oldest first.
List<String> messagesIn(String range) => git(['log', '--reverse', '--format=%B%x1e', range]).split('\x1e').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

/// Lint problems for [lines] from the vendored voice linter: one string per error finding.
List<String> lintProblems(List<String> lines) {
  if (lines.isEmpty) return const [];
  final tmp = File('${Directory.systemTemp.path}${Platform.pathSeparator}whats_new_lines_$pid.json');
  tmp.writeAsStringSync(jsonEncode(lines));
  try {
    final r = Process.runSync('node', ['tools/voice-lint/voice-lint.js', '--json', tmp.path, '--format', 'json'], stdoutEncoding: utf8, stderrEncoding: utf8);
    if (r.exitCode != 0 && r.exitCode != 1) {
      return ['voice lint could not run (exit ${r.exitCode}): ${'${r.stderr}'.trim()}'];
    }
    final found = jsonDecode('${r.stdout}'.trim().isEmpty ? '[]' : '${r.stdout}') as List;
    return [
      for (final f in found.whereType<Map>())
        if (f['severity'] == 'error') '${f['rule']}: ${f['message']} ("${f['snippet']}")',
    ];
  } finally {
    if (tmp.existsSync()) tmp.deleteSync();
  }
}

String arg(List<String> args, String name, String fallback) {
  final i = args.indexOf(name);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : fallback;
}

String pubspecVersion() {
  final m = RegExp(r'^version:\s*(\d+\.\d+\.\d+)', multiLine: true).firstMatch(File('pubspec.yaml').readAsStringSync());
  if (m == null) throw StateError('pubspec.yaml has no version');
  return m.group(1)!;
}

void main(List<String> args) {
  final version = arg(args, '--version', pubspecVersion());
  final head = arg(args, '--head', 'HEAD');
  final out = arg(args, '--out', 'assets/whats_new.json');
  final md = arg(args, '--md', 'build/whats_new.md');
  final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);

  final tags = git(['tag', '-l', 'apk-v*']).split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  final below = versionsBelow(tags, version, historyReleases + 1);
  final problems = <String>[];

  // This release: from the previous release tag to HEAD.
  final range = below.isEmpty ? head : 'apk-v${below.first}..$head';
  final current = gather(messagesIn(range));
  problems.addAll(current.problems);
  for (final w in current.warnings) {
    stderr.writeln('::warning::release note: $w');
  }

  // The releases before it, each from its own predecessor, newest first.
  final history = <HistoryEntry>[];
  for (var i = 0; i < below.length - 1; i++) {
    final v = below[i];
    final r = gather(messagesIn('apk-v${below[i + 1]}..apk-v$v'));
    problems.addAll(r.problems);
    final date = git(['log', '-1', '--format=%cs', 'apk-v$v']).trim();
    history.add(HistoryEntry(v, date, r.notes));
  }

  // The voice rules apply to every line that will be shown, the current ones and the carried history alike.
  final lines = [...allLines(current.notes), for (final h in history) ...allLines(h.notes)];
  problems.addAll(lintProblems(lines));

  if (problems.isNotEmpty) {
    for (final p in problems) {
      stderr.writeln('::error::release note: $p');
    }
    exit(1);
  }

  final report = buildReport(version: version, date: today, current: current.notes, history: history);
  File(out).parent.createSync(recursive: true);
  File(out).writeAsStringSync(reportJson(report));
  File(md).parent.createSync(recursive: true);
  File(md).writeAsStringSync('${releaseBody(current.notes)}\n');
  stdout.writeln('whats_new: $version, ${allLines(current.notes).length} line(s) this release, ${history.where((h) => !h.notes.isEmpty).length} earlier release(s) with notes');
}
