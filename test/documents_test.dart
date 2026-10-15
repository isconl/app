import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/services/documents.dart';
import 'package:isconl/ui/widgets/documents_widgets.dart';

class FakeDocs implements DocumentsApi {
  final calls = <String>[];
  List<GeneratedDoc> docs = const [
    GeneratedDoc(id: 'd1', filename: 'a.docx', archetypeId: 'memo', targetKind: 'project', targetLabel: 'Alpha', createdAt: '2026-10-01'),
    GeneratedDoc(id: 'd2', filename: 'b.docx', archetypeId: 'memo', targetKind: 'project', targetLabel: 'Alpha', createdAt: '2026-10-03'),
    GeneratedDoc(id: 'd3', filename: 'c.md', archetypeId: 'letter'),
  ];
  String shareUrl = 'https://x/y';

  @override
  Future<List<GeneratedDoc>> list({String status = 'active'}) async => docs;
  @override
  Future<({String filename, List<int> bytes})> download(GeneratedDoc d) async => (filename: d.filename, bytes: [1]);
  @override
  Future<void> setStatus(String id, String status) async => calls.add('status:$id:$status');
  @override
  Future<List<DocTask>> attachableTasks(String id) async => const [DocTask('t1', 'Task one')];
  @override
  Future<void> attach(String id, String taskId) async => calls.add('attach:$id:$taskId');
  @override
  Future<List<DocTarget>> engagements() async => const [];
  @override
  Future<List<DocTarget>> projects() async => const [DocTarget('project', id: 'p1', label: 'Alpha')];
  @override
  Future<List<Archetype>> archetypes(String namespace) async => const [Archetype(id: 'memo', title: 'Memo')];
  @override
  Future<Archetype> schema(Archetype a, String namespace) async => a.withFields(const [
        ArchetypeField(name: 'subject', label: 'Subject', required: true),
        ArchetypeField(name: 'points', label: 'Points', type: 'list'),
      ], '');
  @override
  Future<({Archetype archetype, DocTarget target, Map<String, dynamic> content})> stored(String id) async =>
      (archetype: const Archetype(id: 'memo', title: 'memo'), target: const DocTarget('general'), content: {'subject': 'Hi', 'points': ['a', 'b']});
  Map<String, dynamic>? lastContent;
  @override
  Future<String> preview(String namespace, String archetypeId, Map<String, dynamic> content) async {
    lastContent = content;
    return '# Preview';
  }

  @override
  Future<GenerateResult> generate(String namespace, String archetypeId, Map<String, dynamic> content, List<String> formats) async {
    lastContent = content;
    calls.add('generate:${formats.join(',')}');
    return const GenerateResult([GeneratedFile(ext: 'docx', filename: 'memo.docx', bytes: [1, 2])]);
  }

  @override
  Future<String> researchField(String archetypeId, ArchetypeField field, String brief, Map<String, dynamic> others) async => 'drafted ${field.name}';
  @override
  Future<Map<String, String>> fullDraft(String archetypeId, List<ArchetypeField> fields, String brief) async => {'subject': 'S', 'points': 'x\ny'};
  @override
  Future<({String filename, List<int> bytes})> rawFile(String rel) async => (filename: 'f', bytes: [1]);
  @override
  Future<String> render(String rel) async => 'full text';
  @override
  Future<String> replace(String rel, List<int> bytes) async => 'ok';
  @override
  Future<String> rebuildTwin(String rel) async => 'twin';
  @override
  Future<void> pushToOneDrive(String rel) async => calls.add('push:$rel');
  @override
  Future<String> shareLink(String rel) async {
    calls.add('share:$rel');
    return shareUrl;
  }
}

void main() {
  group('field parsing', () {
    test('lists and rows', () {
      const list = ArchetypeField(name: 'l', label: 'L', type: 'list');
      expect(parseFieldValue(list, 'a\n\n b \n'), ['a', 'b']);
      const rows = ArchetypeField(name: 'r', label: 'R', type: 'table-list', keys: ['x', 'y']);
      expect(parseFieldValue(rows, 'one | two\nthree'), [
        {'x': 'one', 'y': 'two'},
        {'x': 'three', 'y': ''},
      ]);
      expect(fieldValueToText(rows, parseFieldValue(rows, 'one | two')), 'one | two');
      expect(parseFieldValue(const ArchetypeField(name: 't', label: 'T'), ' keep '), ' keep ');
    });

    test('required fields', () {
      const f = [ArchetypeField(name: 'a', label: 'A', required: true), ArchetypeField(name: 'b', label: 'B')];
      expect(missingRequired(f, {'a': ' '}), ['A']);
      expect(missingRequired(f, {'a': 'x'}), isEmpty);
    });
  });

  test('grouping is by kind then label, newest first, and search matches', () {
    final api = FakeDocs();
    final g = groupDocs(api.docs);
    expect(g.map((x) => x.kind), ['project', 'general']);
    expect(g.first.subgroups.single.docs.map((d) => d.id), ['d2', 'd1']);
    expect(searchDocs(api.docs, 'letter', {}).map((d) => d.id), ['d3']);
    expect(searchDocs(api.docs, 'alpha', {}).length, 2);
    expect(searchDocs(api.docs, 'zzz', {}), isEmpty);
  });

  testWidgets('library: delete asks first, attach picks a task', (t) async {
    final api = FakeDocs();
    await t.pumpWidget(MaterialApp(home: Scaffold(body: DocumentsLibrary(api: api))));
    await t.pumpAndSettle();
    expect(find.text('a.docx'), findsOneWidget);
    await t.tap(find.byKey(const Key('del-d1')));
    await t.pumpAndSettle();
    expect(find.text('Delete this generated document?'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(api.calls, isEmpty);
    await t.tap(find.byKey(const Key('del-d1')));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Delete'));
    await t.pumpAndSettle();
    expect(api.calls, ['status:d1:deleted']);
    await t.tap(find.byKey(const Key('attach-d1')));
    await t.pumpAndSettle();
    await t.tap(find.text('Task one'));
    await t.pumpAndSettle();
    expect(api.calls.last, 'attach:d1:t1');
    await t.enterText(find.byKey(const Key('docs-search')), 'letter');
    await t.pumpAndSettle();
    expect(find.text('a.docx'), findsNothing);
    expect(find.text('c.md'), findsOneWidget);
  });

  testWidgets('studio: pick, fill, refuse until required is filled, then generate', (t) async {
    final api = FakeDocs();
    await t.pumpWidget(MaterialApp(home: Scaffold(body: DocumentStudio(api: api))));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('arch-memo')));
    await t.pumpAndSettle();
    final gen = find.byKey(const Key('studio-generate'));
    await t.scrollUntilVisible(gen, 200, scrollable: find.byType(Scrollable).first);
    await t.tap(gen);
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.byKey(const Key('studio-message')), -200, scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('Still needed: Subject'), findsOneWidget);
    expect(api.calls, isEmpty);
    await t.enterText(find.byKey(const Key('field-subject')), 'Hello');
    await t.enterText(find.byKey(const Key('field-points')), 'one\ntwo');
    await t.scrollUntilVisible(gen, 200, scrollable: find.byType(Scrollable).first);
    await t.tap(gen);
    await t.pumpAndSettle();
    expect(api.calls, ['generate:docx']);
    expect(api.lastContent, {'subject': 'Hello', 'points': ['one', 'two']});
    expect(find.byKey(const Key('gen-docx')), findsOneWidget);
  });

  testWidgets('studio: a full draft lands in the boxes for review', (t) async {
    final api = FakeDocs();
    await t.pumpWidget(MaterialApp(home: Scaffold(body: DocumentStudio(api: api))));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('arch-memo')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('studio-fulldraft')));
    await t.pumpAndSettle();
    expect(find.textContaining('Write a brief first'), findsOneWidget);
    await t.enterText(find.byKey(const Key('studio-brief')), 'about x');
    await t.tap(find.byKey(const Key('studio-fulldraft')));
    await t.pumpAndSettle();
    expect(find.text('S'), findsOneWidget);
    expect(api.calls, isEmpty);
  });

  testWidgets('deliverable: share asks first and shows the link, never copies on its own', (t) async {
    final api = FakeDocs();
    await t.pumpWidget(MaterialApp(home: Scaffold(body: DeliverableActions(rel: 'x/memo.md', name: 'memo.md', api: api))));
    await t.tap(find.byKey(const Key('doc-share-memo.md')));
    await t.pumpAndSettle();
    expect(find.textContaining('does not set an expiry'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(api.calls, isEmpty);
    await t.tap(find.byKey(const Key('doc-share-memo.md')));
    await t.pumpAndSettle();
    await t.tap(find.text('Create the link'));
    await t.pumpAndSettle();
    expect(api.calls, ['share:x/memo.md']);
    expect(find.byKey(const Key('doc-link-memo.md')), findsOneWidget);
    await t.tap(find.byKey(const Key('doc-read-memo.md')));
    await t.pumpAndSettle();
    expect(find.textContaining('full text'), findsOneWidget);
  });
}
