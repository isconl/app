import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/util/markdown.dart';

/// BI26100324: course modules must read cleanly. The fixtures cover each
/// authoring artefact the renderer used to show raw; the all-modules test runs
/// only when MODULES_DIR points at a copy of the learning vault.
String _read(String n) => File('test/fixtures/modules/$n').readAsStringSync();

Widget _app(String src, {Key? key}) => MaterialApp(
      home: Scaffold(
        body: RepaintBoundary(
            key: key,
            child: SingleChildScrollView(
                child: Markdown(src, variant: MarkdownVariant.reading))),
      ),
    );

String _visibleText(WidgetTester tester) {
  final b = StringBuffer();
  for (final w in tester.widgetList<RichText>(find.byType(RichText))) {
    b.writeln(w.text.toPlainText());
  }
  for (final w in tester.widgetList<Text>(find.byType(Text))) {
    if (w.data != null) b.writeln(w.data);
  }
  return b.toString();
}

final _artefacts = <RegExp>[
  RegExp(r'<!--'),
  RegExp(r'-->'),
  RegExp(r'^\s*\+[-=]{2,}\+', multiLine: true),
  RegExp(r'^\s*\|.*\|\s*$', multiLine: true),
  RegExp(r'^---\s*$', multiLine: true),
  RegExp(r'\[\[|\]\]'),
  RegExp(r'^archetype:', multiLine: true),
];

void main() {
  test('normalise: strips comments and front matter, converts grid tables', () {
    final n = normalizeModuleSource(_read('comment_frontmatter.md'));
    expect(n, isNot(contains('<!--')));
    expect(n, isNot(contains('Hidden Title')));
    expect(n.trimLeft(), startsWith('# Visible Title'));
    final g = normalizeModuleSource(_read('grid_table.md'));
    expect(g, isNot(contains('+---')));
    expect(g, contains('| Week | Focus |'));
    expect(g, contains('| 2 | Build |'));
  });

  testWidgets('grid table renders as a real table', (tester) async {
    await tester.pumpWidget(_app(_read('grid_table.md')));
    expect(find.text('Week'), findsOneWidget);
    expect(find.text('Build'), findsOneWidget);
    expect(_visibleText(tester), isNot(contains('+---')));
  });

  testWidgets('comments, front matter, divider, glossary markers', (tester) async {
    await tester.pumpWidget(_app(_read('comment_frontmatter.md')));
    final t = _visibleText(tester);
    for (final a in _artefacts) {
      expect(a.hasMatch(t), isFalse, reason: 'raw ${a.pattern} visible:\n$t');
    }
    expect(t, contains('Visible Title'));
    expect(t, contains('Body after comment.'));
    expect(t, contains('velocity'));
    expect(t, contains('stand-up'));
    expect(t, contains('What would you check first?'));
  });

  testWidgets('golden: artefact-free module (dark)', (tester) async {
    final key = GlobalKey();
    await tester.binding.setSurfaceSize(const Size(420, 900));
    await tester.pumpWidget(_app(_read('comment_frontmatter.md'), key: key));
    await expectLater(find.byKey(key), matchesGoldenFile('goldens/module_artefacts_dark.png'));
    await tester.pumpWidget(_app(_read('grid_table.md'), key: key));
    await expectLater(find.byKey(key), matchesGoldenFile('goldens/module_grid_table_dark.png'));
    // Pixel goldens are font-engine specific: generated and checked on Linux
    // only, so the Windows CI job does not fail on anti-aliasing.
  }, skip: !Platform.isLinux);

  final dir = Platform.environment['MODULES_DIR'];
  testWidgets('all modules render with no raw artefacts and every heading',
      (tester) async {
    final report = StringBuffer('course\tmodule\tproblem\n');
    var modules = 0, bad = 0;
    // Same set the hub manifest serves: every .md directly inside a course
    // folder whose name is [\w-]+ (so `.trash-*` and nested folders are out).
    final files = <File>[];
    for (final c in Directory(dir!).listSync().whereType<Directory>()) {
      final cn = c.path.split('/').last;
      if (cn.startsWith('_') || !RegExp(r'^[\w-]+$').hasMatch(cn)) continue;
      for (final f in c.listSync().whereType<File>()) {
        if (!f.path.endsWith('.md')) continue;
        if (Platform.environment['MODULES_ALL'] == '1' || f.path.endsWith('_v3_1_0.md')) {
          files.add(f);
        }
      }
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    await tester.binding.setSurfaceSize(const Size(420, 900));
    for (final f in files) {
      modules++;
      final src = f.readAsStringSync();
      await tester.pumpWidget(_app(src));
      final t = _visibleText(tester);
      final problems = <String>[];
      // Fenced code is shown verbatim on purpose (ASCII diagrams), so a hit
      // that also sits inside a fence is not a rendering artefact.
      final fenced = RegExp(r'```[\s\S]*?```').allMatches(src).map((m) => m.group(0)!).join('\n');
      for (final a in _artefacts) {
        final hit = t.split('\n').any((ln) =>
            ln.trim().isNotEmpty && a.hasMatch(ln) && !fenced.contains(ln.trim()));
        if (hit) {
          problems.add('raw ${a.pattern}');
        }
      }
      // Completeness: every ## movement heading in the body is present.
      final body = normalizeModuleSource(src);
      for (final m in RegExp(r'^##\s+(.+)$', multiLine: true).allMatches(body)) {
        final h = m.group(1)!.replaceAll(RegExp(r'[*_`]'), '').trim();
        if (!t.toLowerCase().contains(h.toLowerCase())) problems.add('missing heading: $h');
      }
      final ex = tester.takeException(); if (ex != null) problems.add("exception: ${ex is FlutterError ? ex.toStringDeep().replaceAll("\n", " / ") : ex}");
      if (problems.isNotEmpty) {
        bad++;
        final parts = f.path.split('/');
        report.writeln('${parts[parts.length - 2]}\t${parts.last}\t${problems.join('; ')}');
      }
    }
    File(Platform.environment['REPORT_OUT'] ?? '/tmp/module_report.tsv')
        .writeAsStringSync(report.toString());
    // ignore: avoid_print
    print('modules=$modules problems=$bad');
    expect(bad, 0, reason: report.toString());
  }, skip: dir == null, timeout: const Timeout(Duration(minutes: 20)));
}
