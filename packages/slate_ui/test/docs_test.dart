// BI26112340: slate's docs screens, mountable in iSconl and in slate's own app.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slate_ui/slate_ui.dart';

class _Client implements SlateDocsClient {
  _Client(this.docs);
  final Map<String, SlateDoc> docs;
  bool offline = false;
  int reads = 0;
  @override
  Future<SlateDoc> doc(String key) async {
    reads++;
    if (offline) throw Exception('offline');
    final d = docs[key];
    if (d == null) throw Exception('404');
    return d;
  }
}

SlateDocsHost _host(_Client c, {SlateDocStore? store, List<String>? annotated}) => SlateDocsHost(
      client: c,
      store: store ?? MemoryDocStore(),
      render: (ctx, md, hooks) => Column(children: [
        for (final (i, p) in md.split('\n\n').indexed)
          GestureDetector(onLongPress: () => hooks.onParagraphLongPress(i, p), child: Text(p, key: Key('para-$i'))),
      ]),
      annotate: (ctx, key, {block, text, title}) async => annotated?.add('$key:${block ?? '-'}'),
      refreshEvery: const Duration(hours: 1),
    );

void main() {
  test('names read in plain words and keep their project', () {
    expect(docTitle('sconl.FEDORA-INSTALL.md'), 'Fedora install');
    expect(docProject('sconl.FEDORA-INSTALL.md'), 'sconl');
    expect(docTitle('STYLUS-SCONL.md'), 'Stylus sconl');
    expect(docProject('STYLUS-SCONL.md'), '');
  });

  test('the index doc gives grouped links with their notes', () {
    final e = parseDocIndex('# Docs\n\n## Today\n- [Fedora install](sconl.FEDORA-INSTALL.md): wipe and install\n\n## Rules\n- [Writing voice](WRITING-VOICE.md)\n');
    expect(e.map((x) => (x.group, x.key, x.title, x.note)), [
      ('Today', 'sconl.FEDORA-INSTALL.md', 'Fedora install', 'wipe and install'),
      ('Rules', 'WRITING-VOICE.md', 'Writing voice', ''),
    ]);
  });

  test('the outline lists headings and skips fenced code', () {
    final o = docOutline('# Title\n\n## Step one\n\n```\n# not a heading\n```\n\n### Detail\n');
    expect(o.map((x) => (x.$1, x.$2, x.$3)), [(1, 'Title', 'title'), (2, 'Step one', 'step-one'), (3, 'Detail', 'detail')]);
  });

  testWidgets('a doc opens live, says so, and a long-press annotates that paragraph', (t) async {
    final c = _Client({'sconl.FEDORA-INSTALL.md': const SlateDoc(key: 'sconl.FEDORA-INSTALL.md', text: 'First.\n\nSecond.', etag: 'a')});
    final annotated = <String>[];
    await t.pumpWidget(MaterialApp(home: SlateDocScreen(host: _host(c, annotated: annotated), docKey: 'sconl.FEDORA-INSTALL.md')));
    await t.pumpAndSettle();
    expect(find.text('Fedora install'), findsOneWidget);
    expect(find.textContaining('Live from slate'), findsOneWidget);
    await t.longPress(find.byKey(const Key('para-1')));
    await t.pumpAndSettle();
    expect(annotated, ['sconl.FEDORA-INSTALL.md:1']);
    await t.tap(find.byKey(const Key('doc-annotate')));
    await t.pumpAndSettle();
    expect(annotated.last, 'sconl.FEDORA-INSTALL.md:-');
  });

  testWidgets('with no signal the last copy opens, marked offline', (t) async {
    final store = MemoryDocStore();
    await store.write(SlateDoc(key: 'X.md', text: 'Kept copy.', etag: 'a', fetchedAt: DateTime(2026, 11, 23, 9, 5)));
    final c = _Client({})..offline = true;
    await t.pumpWidget(MaterialApp(home: SlateDocScreen(host: _host(c, store: store), docKey: 'X.md')));
    await t.pumpAndSettle();
    expect(find.text('Kept copy.'), findsOneWidget);
    expect(find.textContaining('Offline copy'), findsOneWidget);
  });

  testWidgets('the docs tab lists the index and opens a doc', (t) async {
    final c = _Client({
      'PHONE-DOCS.md': const SlateDoc(key: 'PHONE-DOCS.md', text: '## Today\n- [Fedora install](sconl.FEDORA-INSTALL.md): steps', etag: 'i'),
      'sconl.FEDORA-INSTALL.md': const SlateDoc(key: 'sconl.FEDORA-INSTALL.md', text: 'Step one.', etag: 'a'),
    });
    await t.pumpWidget(MaterialApp(home: Scaffold(body: SlateDocsTab(host: _host(c)))));
    await t.pumpAndSettle();
    expect(find.text('TODAY'), findsOneWidget);
    await t.tap(find.byKey(const Key('doc-tile-sconl.FEDORA-INSTALL.md')));
    await t.pumpAndSettle();
    expect(find.text('Step one.'), findsOneWidget);
  });
}
