import 'dart:convert';

import '../api/client.dart';

/// BI26100508: the console's documents and writer routes, behind one class that
/// alone knows them. Nothing here sends a document anywhere on its own: a share
/// link is only created when the reader taps it, and it says what it exposes first.

class GeneratedDoc {
  const GeneratedDoc({
    required this.id,
    required this.filename,
    this.archetypeId = '',
    this.targetKind = 'general',
    this.targetLabel = '',
    this.taskId = '',
    this.createdAt = '',
    this.status = 'active',
    this.fromOneDrive = false,
    this.webUrl = '',
    this.downloadUrl = '',
  });
  final String id;
  final String filename;
  final String archetypeId;

  /// engagement | project | general
  final String targetKind;
  final String targetLabel;
  final String taskId;
  final String createdAt;
  final String status;

  /// Found in OneDrive, never generated here: it can be opened and downloaded, nothing else.
  final bool fromOneDrive;
  final String webUrl;
  final String downloadUrl;

  bool get canAttach => targetKind == 'project' && !fromOneDrive;
}

class DocGroup {
  const DocGroup(this.kind, this.subgroups);
  final String kind;
  final List<({String label, List<GeneratedDoc> docs})> subgroups;
  int get count => subgroups.fold(0, (n, g) => n + g.docs.length);
}

class Archetype {
  const Archetype({required this.id, required this.title, this.governed = false, this.fields = const [], this.layout = ''});
  final String id;
  final String title;
  final bool governed;
  final List<ArchetypeField> fields;
  final String layout;
  Archetype withFields(List<ArchetypeField> f, String layout) => Archetype(id: id, title: title, governed: governed, fields: f, layout: layout);
}

class ArchetypeField {
  const ArchetypeField({required this.name, required this.label, this.type = 'text', this.required = false, this.options = const [], this.keys = const [], this.section = ''});
  final String name;
  final String label;

  /// text, textarea, select, list, reasoned-list, table-list.
  final String type;
  final bool required;
  final List<String> options;

  /// Column names for reasoned-list and table-list rows.
  final List<String> keys;
  final String section;

  bool get multiline => const {'textarea', 'list', 'reasoned-list', 'table-list'}.contains(type);

  /// What the field expects, said in the form.
  String get hint => switch (type) {
        'list' => 'One item per line',
        'reasoned-list' || 'table-list' => 'One row per line, columns split by |${keys.isEmpty ? '' : ' (${keys.join(' | ')})'}',
        _ => '',
      };
}

class DocTarget {
  const DocTarget(this.kind, {this.id = '', this.label = ''});

  /// engagement | project | general
  final String kind;
  final String id;
  final String label;

  /// Engagements have their own archetype set; everything else uses the shared one.
  String get namespace => kind == 'engagement' && id.isNotEmpty ? id : '_common';
}

class GeneratedFile {
  const GeneratedFile({required this.ext, required this.filename, required this.bytes});
  final String ext;
  final String filename;
  final List<int> bytes;
}

class DocTask {
  const DocTask(this.id, this.title);
  final String id;
  final String title;
}

/// The preview and the files of one generate call.
class GenerateResult {
  const GenerateResult(this.files);
  final List<GeneratedFile> files;
}

/// Raw field text to the value shape a document template expects. One place, so a
/// new field type is taught once.
Object parseFieldValue(ArchetypeField f, String raw) {
  final lines = raw.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  switch (f.type) {
    case 'list':
      return lines;
    case 'reasoned-list':
    case 'table-list':
      final keys = f.keys.isEmpty ? const ['a', 'b'] : f.keys;
      return [
        for (final line in lines)
          () {
            final parts = line.split('|').map((s) => s.trim()).toList();
            return {for (var i = 0; i < keys.length; i++) keys[i]: i < parts.length ? parts[i] : ''};
          }(),
      ];
    default:
      return raw;
  }
}

/// The reverse, for reopening a stored document in the form.
String fieldValueToText(ArchetypeField f, Object? v) {
  if (v is List) {
    if (f.type == 'reasoned-list' || f.type == 'table-list') {
      final keys = f.keys.isEmpty ? const ['a', 'b'] : f.keys;
      return v.map((r) => r is Map ? keys.map((k) => '${r[k] ?? ''}').join(' | ') : '$r').join('\n');
    }
    return v.join('\n');
  }
  return v == null ? '' : '$v';
}

/// Fields the form still needs before Generate means anything.
List<String> missingRequired(List<ArchetypeField> fields, Map<String, String> values) =>
    [for (final f in fields) if (f.required && (values[f.name] ?? '').trim().isEmpty) f.label];

/// The first column of the picker: the console's grouping, newest first inside each.
List<DocGroup> groupDocs(List<GeneratedDoc> docs) {
  const kinds = ['engagement', 'project', 'general'];
  final by = {for (final k in kinds) k: <String, List<GeneratedDoc>>{}};
  for (final d in docs) {
    final kind = by.containsKey(d.targetKind) ? d.targetKind : 'general';
    final label = kind == 'general' ? '' : d.targetLabel;
    (by[kind]!.putIfAbsent(label, () => [])).add(d);
  }
  return [
    for (final k in kinds)
      if (by[k]!.isNotEmpty)
        DocGroup(k, [
          for (final e in (by[k]!.entries.toList()..sort((a, b) => a.key.compareTo(b.key))))
            (label: e.key, docs: [...e.value]..sort((a, b) => b.createdAt.compareTo(a.createdAt))),
        ]),
  ];
}

List<GeneratedDoc> searchDocs(List<GeneratedDoc> docs, String q, Map<String, String> archetypeTitles) {
  final s = q.trim().toLowerCase();
  if (s.isEmpty) return docs;
  return [
    for (final d in docs)
      if (d.filename.toLowerCase().contains(s) ||
          d.targetLabel.toLowerCase().contains(s) ||
          (archetypeTitles[d.archetypeId] ?? d.archetypeId).toLowerCase().contains(s))
        d,
  ];
}

abstract class DocumentsApi {
  Future<List<GeneratedDoc>> list({String status = 'active'});
  Future<({String filename, List<int> bytes})> download(GeneratedDoc d);
  Future<void> setStatus(String id, String status);
  Future<List<DocTask>> attachableTasks(String id);
  Future<void> attach(String id, String taskId);
  Future<List<DocTarget>> engagements();
  Future<List<DocTarget>> projects();
  Future<List<Archetype>> archetypes(String namespace);
  Future<Archetype> schema(Archetype a, String namespace);
  Future<({Archetype archetype, DocTarget target, Map<String, dynamic> content})> stored(String id);
  Future<String> preview(String namespace, String archetypeId, Map<String, dynamic> content);
  Future<GenerateResult> generate(String namespace, String archetypeId, Map<String, dynamic> content, List<String> formats);

  /// A model fills one field, or all of them, from a brief. Never applied unseen.
  Future<String> researchField(String archetypeId, ArchetypeField field, String brief, Map<String, dynamic> others);
  Future<Map<String, String>> fullDraft(String archetypeId, List<ArchetypeField> fields, String brief);

  /// Deliverables on the document store: file paths are relative, as the hub serves them.
  Future<({String filename, List<int> bytes})> rawFile(String rel);
  Future<String> render(String rel);
  Future<String> replace(String rel, List<int> bytes);
  Future<String> rebuildTwin(String rel);
  Future<void> pushToOneDrive(String rel);

  /// Creates a view link. The caller shows what it exposes and asks first.
  Future<String> shareLink(String rel);
}

class HubDocumentsApi implements DocumentsApi {
  HubDocumentsApi(this.api);
  final ApiClient api;

  static Map<String, dynamic> _m(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  static List<dynamic> _l(Object? v) => v is List ? v : const [];
  static String _s(Object? v) => v == null || v == '-' ? '' : '$v';

  static Map<String, dynamic> _ok(Object? res) {
    final m = _m(res);
    if (m['success'] == false || (m['success'] == null && m['ok'] == false)) {
      final errs = _l(m['errors']);
      throw ApiException(0, errs.isNotEmpty ? errs.join('; ') : (_s(m['error']).isEmpty ? 'Refused' : _s(m['error'])));
    }
    if (m['error'] != null && m['success'] == null) throw ApiException(0, _s(m['error']));
    return m;
  }

  static String q(String v) => Uri.encodeQueryComponent(v);

  static GeneratedDoc parseDoc(Map<String, dynamic> d) => GeneratedDoc(
        id: _s(d['ID']),
        filename: _s(d['FILENAME']),
        archetypeId: _s(d['ARCHETYPE_ID']),
        targetKind: _s(d['TARGET_KIND']).isEmpty ? 'general' : _s(d['TARGET_KIND']),
        targetLabel: _s(d['TARGET_LABEL']).isEmpty ? _s(d['TARGET_ID']) : _s(d['TARGET_LABEL']),
        taskId: _s(d['TASK_ID']),
        createdAt: _s(d['CREATED_AT']),
        status: _s(d['STATUS']).isEmpty ? 'active' : _s(d['STATUS']),
        fromOneDrive: d['SOURCE'] == 'onedrive',
        webUrl: _s(d['ONEDRIVE_WEBURL']),
        downloadUrl: _s(d['ONEDRIVE_DOWNLOAD_URL']),
      );

  static ArchetypeField parseField(Object? v) {
    final f = _m(v);
    return ArchetypeField(
      name: _s(f['name']),
      label: _s(f['label']).isEmpty ? _s(f['name']) : _s(f['label']),
      type: _s(f['type']).isEmpty ? 'text' : _s(f['type']),
      required: f['required'] == true,
      options: [for (final o in _l(f['options'])) '$o'],
      keys: [for (final o in _l(f['keys'])) '$o'],
      section: _s(f['section']),
    );
  }

  @override
  Future<List<GeneratedDoc>> list({String status = 'active'}) async {
    final d = _m(await api.getJson('/api/generate/docs?status=${q(status)}'));
    return [for (final x in _l(d['docs'])) parseDoc(_m(x))];
  }

  @override
  Future<({String filename, List<int> bytes})> download(GeneratedDoc d) async {
    final m = _m(await api.getJson('/api/generate/docs/download?id=${q(d.id)}', cold: true));
    if (m['error'] != null) throw ApiException(0, _s(m['error']));
    return (filename: _s(m['filename']).isEmpty ? d.filename : _s(m['filename']), bytes: base64Decode(_s(m['base64'])));
  }

  @override
  Future<void> setStatus(String id, String status) async => _ok(await api.postJson('/api/generate/docs/update', {'id': id, 'status': status}));

  @override
  Future<List<DocTask>> attachableTasks(String id) async {
    final d = _m(await api.getJson('/api/generate/docs/tasks?id=${q(id)}'));
    return [for (final t in _l(d['tasks'])) DocTask(_s(_m(t)['ID']), _s(_m(t)['TITLE']).isEmpty ? _s(_m(t)['ID']) : _s(_m(t)['TITLE']))];
  }

  @override
  Future<void> attach(String id, String taskId) async => _ok(await api.postJson('/api/generate/docs/attach', {'id': id, 'taskId': taskId}));

  @override
  Future<List<DocTarget>> engagements() async {
    final d = _m(await api.getJson('/api/corporate'));
    return [for (final e in _l(d['engagements'])) DocTarget('engagement', id: _s(_m(e)['id']), label: _s(_m(e)['name']).isEmpty ? _s(_m(e)['id']) : _s(_m(e)['name']))];
  }

  @override
  Future<List<DocTarget>> projects() async {
    final d = _m(await api.getJson('/api/projects'));
    return [for (final p in _l(d['projects'])) DocTarget('project', id: _s(_m(p)['ID']), label: _s(_m(p)['NAME']).isEmpty ? _s(_m(p)['ID']) : _s(_m(p)['NAME']))];
  }

  @override
  Future<List<Archetype>> archetypes(String namespace) async {
    final d = _m(await api.getJson('/api/generate/archetypes?namespace=${q(namespace)}'));
    return [
      for (final a in _l(d['archetypes']))
        Archetype(id: _s(_m(a)['id']), title: _s(_m(a)['title']).isEmpty ? _s(_m(a)['id']) : _s(_m(a)['title']), governed: _m(a)['governance'] != null && _m(a)['governance'] != false, layout: _s(_m(a)['layout'])),
    ];
  }

  @override
  Future<Archetype> schema(Archetype a, String namespace) async {
    if (a.fields.isNotEmpty) return a;
    final d = _m(await api.getJson('/api/generate/archetypes/schema?archetypeId=${q(a.id)}&namespace=${q(namespace)}'));
    if (d['error'] != null) throw ApiException(0, _s(d['error']));
    return a.withFields([for (final f in _l(d['fields'])) parseField(f)], _s(d['layout']));
  }

  @override
  Future<({Archetype archetype, DocTarget target, Map<String, dynamic> content})> stored(String id) async {
    final d = _m(await api.getJson('/api/generate/docs/content?id=${q(id)}', cold: true));
    if (d['error'] != null) throw ApiException(0, _s(d['error']));
    final kind = _s(d['targetKind']).isEmpty ? 'general' : _s(d['targetKind']);
    return (
      archetype: Archetype(id: _s(d['archetypeId']), title: _s(d['archetypeId'])),
      target: DocTarget(kind, id: _s(d['targetId']), label: _s(d['targetLabel'])),
      content: _m(d['content']),
    );
  }

  @override
  Future<String> preview(String namespace, String archetypeId, Map<String, dynamic> content) async {
    final d = _ok(await api.postJson('/api/generate/preview', {'namespace': namespace, 'archetypeId': archetypeId, 'content': content}, cold: true));
    return _s(d['markdown']);
  }

  @override
  Future<GenerateResult> generate(String namespace, String archetypeId, Map<String, dynamic> content, List<String> formats) async {
    final d = _m(await api.postJson('/api/generate', {'namespace': namespace, 'archetypeId': archetypeId, 'content': content, 'formats': formats}, cold: true));
    if (d['errors'] is List && (d['errors'] as List).isNotEmpty) throw ApiException(0, (d['errors'] as List).join('; '));
    if (d['error'] != null) throw ApiException(0, _s(d['error']));
    final files = _m(d['files']);
    return GenerateResult([
      for (final e in files.entries)
        GeneratedFile(ext: e.key, filename: _s(_m(e.value)['filename']).isEmpty ? 'document.${e.key}' : _s(_m(e.value)['filename']), bytes: base64Decode(_s(_m(e.value)['base64']))),
    ]);
  }

  @override
  Future<String> researchField(String archetypeId, ArchetypeField field, String brief, Map<String, dynamic> others) async {
    final d = _ok(await api.postJson('/api/writer/research-field', {
      'archetypeId': archetypeId,
      'field': {'name': field.name, 'label': field.label, 'type': field.type},
      'brief': brief,
      'otherFieldValues': others,
    }, cold: true));
    final v = d['value'];
    return v is List ? v.join('\n') : _s(v);
  }

  @override
  Future<Map<String, String>> fullDraft(String archetypeId, List<ArchetypeField> fields, String brief) async {
    final d = _m(await api.postJson('/api/writer/full-draft', {
      'archetypeId': archetypeId,
      'fields': [for (final f in fields) {'name': f.name, 'label': f.label, 'type': f.type}],
      'brief': brief,
    }, cold: true));
    if (d['error'] != null) throw ApiException(0, _s(d['error']));
    return {for (final e in d.entries) e.key: e.value is List ? (e.value as List).join('\n') : _s(e.value)};
  }

  @override
  Future<({String filename, List<int> bytes})> rawFile(String rel) => api.getBytes('/api/documents/raw?file=${q(rel)}&download=1');

  @override
  Future<String> render(String rel) async {
    final d = _m(await api.getJson('/api/documents/render?file=${q(rel)}', cold: true));
    final t = _s(d['full']).isNotEmpty ? _s(d['full']) : _s(_m(d['preview'])['text']);
    if (t.isEmpty) throw ApiException(0, _s(d['note']).isEmpty ? 'No readable text in this one' : _s(d['note']));
    return t;
  }

  @override
  Future<String> replace(String rel, List<int> bytes) async {
    final d = _ok(await api.postJson('/api/documents/replace', {'file': rel, 'contentBase64': base64Encode(bytes)}, cold: true));
    final kb = ((d['bytes'] as num?) ?? 0) ~/ 1024;
    return 'Replaced ($kb KB)${d['mirrored'] == true ? ' and mirrored to OneDrive' : '. OneDrive follows on the next pass'}. The previous version is kept.';
  }

  @override
  Future<String> rebuildTwin(String rel) async {
    final d = _ok(await api.postJson('/api/documents/twin', {'file': rel}, cold: true));
    return 'Word copy rebuilt: ${_s(d['twin'])} (${d['words'] ?? 0} words, read back and checked).';
  }

  @override
  Future<void> pushToOneDrive(String rel) async => _ok(await api.postJson('/api/documents/push', {'file': rel}, cold: true));

  @override
  Future<String> shareLink(String rel) async {
    final d = _ok(await api.postJson('/api/documents/share', {'file': rel}, cold: true));
    return _s(d['url']);
  }
}
