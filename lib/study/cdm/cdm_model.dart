/// BI26092620: the deck document model (DDM, formerly CDM) as the phone reads it.
///
/// Wire shape, from `deck-core/src/node_tree.rs`: a document is
/// `{ddm, headline, subtitle?, meta{}, meta_line?, sections:[node], footer_note?}`
/// and every node is `{type: <snake_case kind>, ...fields}`. The older key `cdm`
/// is accepted for `ddm`, as deck itself does.
///
/// Deliberately tolerant. A kind this build does not know becomes a node with
/// [CdmNode.known] false, so the view can show its fallback instead of failing the
/// page, and a missing or mistyped field reads as empty rather than throwing.
library;

import 'dart:convert';

/// Kinds this build can draw. Anything else is "needs an app update".
const cdmKnownKinds = <String>{
  'heading',
  'paragraph',
  'bullets',
  'checked_bullets',
  'kv_list',
  'truth_check',
  'table',
  'section',
  'audience',
  'page_break',
  'slide_break',
  'quote',
  'code',
  'ordered',
  'chart',
  'image',
  'embed',
  'callout',
  'equation',
  'map',
};

/// The twelve callout labels of course standard v3 section 8.1.
const cdmCalloutKinds = <String>{
  'prior',
  'outcome',
  'place',
  'story',
  'jargon',
  'book',
  'research',
  'fact',
  'probe',
  'failure',
  'essentials',
  'check',
};

class CdmNode {
  CdmNode({required this.type, required this.id, required this.json, this.children = const []});

  /// The wire kind, e.g. `callout`.
  final String type;

  /// A stable key for this block. DDM does not carry block ids yet, so unless the
  /// node has an `id` or `block_id` it is its position in the tree (`b3`, `b3.1`),
  /// which is stable for one document version. Notes and the lifecycle anchor to it.
  final String id;

  final Map<String, dynamic> json;

  /// Child nodes of a `section` or `audience`.
  final List<CdmNode> children;

  bool get known => cdmKnownKinds.contains(type);

  String str(String key) {
    final v = json[key];
    return v is String ? v : (v == null ? '' : v.toString());
  }

  String? strOrNull(String key) {
    final v = json[key];
    if (v == null) return null;
    final s = v is String ? v : v.toString();
    return s.isEmpty ? null : s;
  }

  int intOf(String key, [int fallback = 0]) {
    final v = json[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? fallback;
  }

  bool boolOf(String key) => json[key] == true;

  List<String> strList(String key) {
    final v = json[key];
    if (v is! List) return const [];
    return [for (final e in v) e is String ? e : '$e'];
  }

  List<Map<String, dynamic>> mapList(String key) {
    final v = json[key];
    if (v is! List) return const [];
    return [
      for (final e in v)
        if (e is Map) Map<String, dynamic>.from(e)
    ];
  }

  /// A callout's kind when it is one of the twelve, else null.
  String? get calloutKind {
    final k = str('kind');
    return cdmCalloutKinds.contains(k) ? k : null;
  }
}

class CdmDoc {
  CdmDoc({
    required this.ddm,
    required this.headline,
    this.subtitle,
    this.meta = const {},
    this.metaLine,
    required this.sections,
    this.footerNote,
  });

  final String ddm;
  final String headline;
  final String? subtitle;
  final Map<String, String> meta;
  final String? metaLine;
  final List<CdmNode> sections;
  final String? footerNote;

  /// Parses a document. Throws [FormatException] only when the input is not a
  /// document at all (not JSON, or not an object); content problems degrade.
  factory CdmDoc.fromJsonString(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw const FormatException('not valid JSON');
    }
    if (decoded is! Map) throw const FormatException('a document is a JSON object');
    return CdmDoc.fromJson(Map<String, dynamic>.from(decoded));
  }

  factory CdmDoc.fromJson(Map<String, dynamic> j) {
    String? opt(String k) {
      final v = j[k];
      if (v == null) return null;
      final s = '$v';
      return s.isEmpty ? null : s;
    }

    final meta = <String, String>{};
    final m = j['meta'];
    if (m is Map) {
      m.forEach((k, v) => meta['$k'] = '$v');
    }
    return CdmDoc(
      ddm: '${j['ddm'] ?? j['cdm'] ?? '1'}',
      headline: '${j['headline'] ?? ''}',
      subtitle: opt('subtitle'),
      meta: meta,
      metaLine: opt('meta_line'),
      sections: _nodes(j['sections'], ''),
      footerNote: opt('footer_note'),
    );
  }

  /// Every node in reading order, depth first, wrappers included.
  Iterable<CdmNode> get allNodes sync* {
    Iterable<CdmNode> walk(List<CdmNode> ns) sync* {
      for (final n in ns) {
        yield n;
        yield* walk(n.children);
      }
    }

    yield* walk(sections);
  }
}

List<CdmNode> _nodes(Object? raw, String prefix) {
  if (raw is! List) return const [];
  final out = <CdmNode>[];
  for (var i = 0; i < raw.length; i++) {
    final e = raw[i];
    if (e is! Map) continue;
    final j = Map<String, dynamic>.from(e);
    final type = '${j['type'] ?? ''}';
    final own = j['id'] ?? j['block_id'];
    final id = own is String && own.isNotEmpty ? own : (prefix.isEmpty ? 'b$i' : '$prefix.$i');
    out.add(CdmNode(
      type: type,
      id: id,
      json: j,
      children: (type == 'section' || type == 'audience') ? _nodes(j['nodes'], id) : const [],
    ));
  }
  return out;
}
