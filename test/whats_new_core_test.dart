import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/whats_new_core.dart';

void main() {
  group('BI26101213: reading trailers', () {
    test('only lines that start exactly with New, Improved or Fixed count, with their text trimmed', () {
      final t = parseTrailers('''
app 0.3.97: a long internal subject

Body text that mentions New: stuff in the middle of a line.

New: See what changed after every update.
Improved:   Lists open faster.
Fixed: The sheet no longer closes by itself.
new: lower case does not count
Note: neither does this
  New: nor an indented one
''');
      expect(t.map((x) => '${x.kind}|${x.text}').toList(), [
        'New|See what changed after every update.',
        'Improved|Lists open faster.',
        'Fixed|The sheet no longer closes by itself.',
      ]);
    });

    test('windows line endings read the same, and a message with no trailer gives none', () {
      expect(parseTrailers('subject\r\n\r\nNew: One thing.\r\n').single.text, 'One thing.');
      expect(parseTrailers('just an internal commit'), isEmpty);
      expect(parseTrailers(''), isEmpty);
    });
  });

  group('BI26101213: what cannot ship', () {
    test('a line over 120 characters is refused, 120 is fine', () {
      expect(noteProblem(Trailer('New', 'x' * 120)), isNull);
      expect(noteProblem(Trailer('New', 'x' * 121)), contains('121 characters'));
    });

    test('gather cuts a long line to 120 with an ellipsis and warns instead of failing', () {
      final long = 'word ' * 70;
      final r = gather(['subject\n\nNew: $long\nNew: Short one.']);
      expect(r.problems, isEmpty);
      expect(r.warnings, hasLength(1));
      expect(r.notes.added.first.length, lessThanOrEqualTo(120));
      expect(r.notes.added.first, endsWith('...'));
      expect(r.notes.added.last, 'Short one.');
      expect(clipNote('x' * 120), 'x' * 120);
    });

    test('a line that names a row id is refused', () {
      expect(noteProblem(const Trailer('Fixed', 'Fixed the thing from BI26101213.')), contains('row id'));
      expect(noteProblem(const Trailer('Fixed', 'Fixed the thing.')), isNull);
    });
  });

  group('BI26101213: gathering', () {
    test('groups by kind, keeps commit order and drops exact repeats', () {
      final r = gather([
        'a\n\nNew: First thing.\nFixed: A bug.',
        'internal only',
        'b\n\nImproved: Faster lists.\nNew: Second thing.',
        'c\n\nNew: First thing.\nFixed: Another bug.',
      ]);
      expect(r.problems, isEmpty);
      expect(r.notes.added, ['First thing.', 'Second thing.']);
      expect(r.notes.improved, ['Faster lists.']);
      expect(r.notes.fixed, ['A bug.', 'Another bug.']);
    });

    test('an empty range gives empty notes and no problems', () {
      final r = gather([]);
      expect(r.notes.isEmpty, isTrue);
      expect(r.problems, isEmpty);
      expect(gather(['internal', 'also internal']).notes.isEmpty, isTrue);
    });

    test('a bad line is reported and left out, the good ones stay', () {
      final r = gather(['x\n\nNew: Fixed the thing from BI26101213.\nNew: Fine.']);
      expect(r.problems, hasLength(1));
      expect(r.notes.added, ['Fine.']);
    });
  });

  group('BI26101213: versions and history', () {
    test('versions compare by number, not by text', () {
      expect(compareVersions('0.3.10', '0.3.9'), greaterThan(0));
      expect(compareVersions('0.4.0', '0.3.99'), greaterThan(0));
      expect(compareVersions('0.3.5', '0.3.5'), 0);
      expect(parseVersion('nonsense'), isNull);
    });

    test('the releases below a version are found newest first, capped, and ignore other tags', () {
      final tags = ['apk-v0.3.1', 'apk-v0.3.10', 'apk-v0.3.2', 'v1.0', 'apk-vjunk', 'apk-v0.3.11', 'apk-v0.3.9'];
      expect(versionsBelow(tags, '0.3.11', 10), ['0.3.10', '0.3.9', '0.3.2', '0.3.1']);
      expect(versionsBelow(tags, '0.3.11', 2), ['0.3.10', '0.3.9']);
      expect(versionsBelow(tags, '0.3.1', 5), isEmpty);
      expect(versionsBelow(['apk-v0.3.12'], '0.3.12', 5), isEmpty, reason: 'the current version is not its own predecessor');
    });

    test('the report carries this release and at most ten earlier ones that had notes, newest first', () {
      final history = [
        for (var i = 20; i >= 1; i--) HistoryEntry('0.3.$i', '2026-10-$i'.padRight(10, '0'), i.isEven ? Notes(added: ['Note $i.']) : Notes()),
      ];
      final report = buildReport(version: '0.3.21', date: '2026-10-12', current: Notes(added: ['Now.']), history: history);
      expect(report['version'], '0.3.21');
      expect(report['new'], ['Now.']);
      expect(report['improved'], isEmpty);
      final h = report['history'] as List;
      expect(h, hasLength(10));
      expect((h.first as Map)['version'], '0.3.20');
      expect((h.last as Map)['version'], '0.3.2');
      expect(h.every((e) => (e as Map)['new'] != null), isTrue);
    });
  });

  group('BI26101213: the release body', () {
    test('lists the groups that have lines, and says Maintenance release when there are none', () {
      expect(releaseBody(Notes()), 'Maintenance release.');
      expect(releaseBody(Notes(added: ['A.'], fixed: ['B.'])), '## New\n- A.\n\n## Fixed\n- B.');
      expect(releaseBody(Notes(improved: ['C.', 'D.'])), '## Improved\n- C.\n- D.');
    });

    test('the json round trips through Notes', () {
      final n = Notes(added: ['A.'], improved: ['B.'], fixed: ['C.']);
      final back = Notes.fromJson(jsonDecode(jsonEncode(n.toJson())) as Map<String, dynamic>);
      expect(back.added, ['A.']);
      expect(back.improved, ['B.']);
      expect(back.fixed, ['C.']);
      expect(Notes.fromJson({'new': 'not a list'}).isEmpty, isTrue);
    });
  });

  group('BI26101213: the script end to end, in a throwaway git repository', () {
    String? tool(String name, List<String> probe) {
      try {
        final r = Process.runSync(name, probe, runInShell: Platform.isWindows);
        return r.exitCode == 0 ? name : null;
      } catch (_) {
        return null;
      }
    }

    final haveAll = tool('git', ['--version']) != null && tool('node', ['--version']) != null && tool('dart', ['--version']) != null;

    test('gathers trailers between release tags, writes the asset and the release body', () {
      final repo = Directory.systemTemp.createTempSync('whats_new_repo_');
      addTearDown(() => repo.deleteSync(recursive: true));
      String run(String exe, List<String> args) {
        final r = Process.runSync(exe, args, workingDirectory: repo.path, runInShell: Platform.isWindows, stdoutEncoding: utf8, stderrEncoding: utf8);
        if (r.exitCode != 0) fail('$exe ${args.join(' ')} failed: ${r.stderr}${r.stdout}');
        return '${r.stdout}';
      }

      void copy(String from, String to) {
        File(to).parent.createSync(recursive: true);
        File(from).copySync(to);
      }

      final root = Directory.current.path;
      copy('$root/tool/whats_new.dart', '${repo.path}/tool/whats_new.dart');
      copy('$root/tool/whats_new_core.dart', '${repo.path}/tool/whats_new_core.dart');
      for (final f in ['voice-lint.js', 'voice-rules.json']) {
        copy('$root/tools/voice-lint/$f', '${repo.path}/tools/voice-lint/$f');
      }
      File('${repo.path}/pubspec.yaml').writeAsStringSync('name: scratch\nversion: 0.3.5+5\n');
      run('git', ['init', '-q']);
      run('git', ['config', 'user.email', 'a@b.c']);
      run('git', ['config', 'user.name', 'Test']);
      void commit(String msg) {
        File('${repo.path}/f.txt').writeAsStringSync('${DateTime.now().microsecondsSinceEpoch}');
        run('git', ['add', '.']);
        // The message goes in through a file: a newline inside an argument is cut off by cmd.exe on Windows.
        final f = File('${Directory.systemTemp.path}/whats_new_msg_${DateTime.now().microsecondsSinceEpoch}.txt')..writeAsStringSync(msg);
        try {
          run('git', ['commit', '-q', '-F', f.path]);
        } finally {
          f.deleteSync();
        }
      }

      commit('first');
      run('git', ['tag', 'apk-v0.3.3']);
      commit('second\n\nNew: Old thing.');
      run('git', ['tag', 'apk-v0.3.4']);
      commit('internal change');
      commit('third\n\nNew: Added a new screen.\nFixed: Fixed a crash on start.');
      commit('fourth\n\nImproved: Lists open faster.\nNew: Added a new screen.');

      run('dart', ['tool/whats_new.dart', '--version', '0.3.5']);
      final asset = jsonDecode(File('${repo.path}/assets/whats_new.json').readAsStringSync()) as Map<String, dynamic>;
      expect(asset['version'], '0.3.5');
      expect(asset['new'], ['Added a new screen.']);
      expect(asset['improved'], ['Lists open faster.']);
      expect(asset['fixed'], ['Fixed a crash on start.']);
      final hist = asset['history'] as List;
      expect(hist, hasLength(1), reason: 'only 0.3.4 had notes; 0.3.3 has no predecessor');
      expect((hist.single as Map)['version'], '0.3.4');
      expect((hist.single as Map)['new'], ['Old thing.']);
      expect(File('${repo.path}/build/whats_new.md').readAsStringSync().trim(), '## New\n- Added a new screen.\n\n## Improved\n- Lists open faster.\n\n## Fixed\n- Fixed a crash on start.');

      // A line the voice rules refuse stops the run.
      commit('fifth\n\nNew: This is robust — and seamless.');
      final bad = Process.runSync('dart', ['tool/whats_new.dart', '--version', '0.3.5'], workingDirectory: repo.path, runInShell: Platform.isWindows, stdoutEncoding: utf8, stderrEncoding: utf8);
      expect(bad.exitCode, isNot(0));
      expect('${bad.stderr}', contains('release note'));
    }, skip: haveAll ? false : 'needs git, node and dart on the PATH', timeout: const Timeout(Duration(minutes: 3)));
  });
}
