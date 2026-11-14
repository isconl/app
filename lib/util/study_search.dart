import 'package:flutter/foundation.dart';

import '../data/db.dart';
import 'fmt.dart' as fmt;

/// BI26100156: search across the modules on the device. The index is built in
/// memory from the downloaded module bodies (already stored on the device), so
/// it works with no signal. Paragraph numbering matches the reader's own
/// (blank-line split, non-empty chunks), so a result can jump to its place.
class Para {
  Para(this.index, this.heading, this.text);
  final int index;
  final String heading;
  final String text;
}

class GlossTerm {
  GlossTerm(this.term, this.definition);
  final String term;
  final String definition;
}

class ModuleDoc {
  ModuleDoc(this.course, this.file, this.title, this.paras, this.terms, this.paraCount);
  final String course;
  final String file;
  final String title;
  final List<Para> paras;
  final List<GlossTerm> terms;

  /// How many chunks the reader counts, headings and all.
  final int paraCount;
  String get key => '$course/$file';
}

final _jargon = RegExp(r'\[\[(?!link:)([^\]|]+)\|([^\]]+)\]\]');

/// Markdown to plain words: no emphasis marks, link targets or jargon markers.
String plain(String md) {
  var t = md;
  t = t.replaceAllMapped(_jargon, (m) => m[1]!);
  t = t.replaceAllMapped(RegExp(r'\[\[link:([^\]|]*)\|?([^\]]*)\]\]'), (m) => m[2]!.isNotEmpty ? m[2]! : m[1]!);
  t = t.replaceAllMapped(RegExp(r'!?\[([^\]]*)\]\([^)]*\)'), (m) => m[1]!);
  t = t.replaceAll(RegExp(r'[*_`>#]+'), '');
  t = t.replaceAll(RegExp(r'^\s*(?:[-+]|\d+[.)])\s+', multiLine: true), '');
  return t.replaceAll(RegExp(r'\s+'), ' ').trim();
}

ModuleDoc indexModule(String course, String file, String markdown, {String? title}) {
  final chunks = markdown.split(RegExp(r'\n\s*\n')).where((p) => p.trim().isNotEmpty).toList();
  var heading = '';
  var docTitle = title ?? '';
  final paras = <Para>[];
  final terms = <GlossTerm>[];
  final seen = <String>{};
  for (var i = 0; i < chunks.length; i++) {
    final raw = chunks[i].trim();
    final firstLine = raw.split('\n').first;
    final h = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(firstLine);
    if (h != null) {
      heading = plain(h[2]!);
      if (docTitle.isEmpty && h[1] == '#') docTitle = heading;
    }
    for (final m in _jargon.allMatches(raw)) {
      final term = m[1]!.trim();
      if (seen.add(term.toLowerCase())) terms.add(GlossTerm(term, plain(m[2]!)));
    }
    final text = plain(raw);
    if (text.isNotEmpty) paras.add(Para(i, heading, text));
  }
  return ModuleDoc(course, file, docTitle.isEmpty ? file : docTitle, paras, terms, chunks.length);
}

class ModuleHit {
  ModuleHit(this.doc);
  final ModuleDoc doc;
}

class GlossaryHit {
  GlossaryHit(this.doc, this.term);
  final ModuleDoc doc;
  final GlossTerm term;
}

class TextHit {
  TextHit(this.doc, this.para, this.snippet, this.marks);
  final ModuleDoc doc;
  final Para para;

  /// About two lines around the first match.
  final String snippet;

  /// Character ranges in [snippet] to highlight.
  final List<(int, int)> marks;
}

class SearchResults {
  SearchResults(this.modules, this.glossary, this.text);
  final List<ModuleHit> modules;
  final List<GlossaryHit> glossary;
  final List<TextHit> text;
  bool get isEmpty => modules.isEmpty && glossary.isEmpty && text.isEmpty;
  static final empty = SearchResults(const [], const [], const []);
}

List<String> queryTerms(String q) => [for (final t in q.toLowerCase().split(RegExp(r'\s+'))) if (t.isNotEmpty) t];

const minQueryLength = 2;

/// Modules whose title matches, glossary terms that match, and paragraphs that
/// contain every word of the query. [textLimit] bounds the paragraph list.
SearchResults searchDocs(List<ModuleDoc> docs, String query, {int textLimit = 30, int snippetChars = 150}) {
  final q = query.trim();
  if (q.length < minQueryLength) return SearchResults.empty;
  final terms = queryTerms(q);
  final modules = <ModuleHit>[];
  final gloss = <GlossaryHit>[];
  final text = <TextHit>[];
  for (final d in docs) {
    final title = d.title.toLowerCase();
    if (terms.every(title.contains)) modules.add(ModuleHit(d));
    for (final t in d.terms) {
      final low = t.term.toLowerCase();
      if (terms.every(low.contains)) gloss.add(GlossaryHit(d, t));
    }
    if (text.length >= textLimit) continue;
    for (final p in d.paras) {
      final low = p.text.toLowerCase();
      if (!terms.every(low.contains)) continue;
      final (snippet, marks) = _snippet(p.text, terms, snippetChars);
      text.add(TextHit(d, p, snippet, marks));
      if (text.length >= textLimit) break;
    }
  }
  return SearchResults(modules, gloss, text);
}

(String, List<(int, int)>) _snippet(String full, List<String> terms, int width) {
  final low = full.toLowerCase();
  var first = low.length;
  for (final t in terms) {
    final i = low.indexOf(t);
    if (i >= 0 && i < first) first = i;
  }
  var start = (first - width ~/ 3).clamp(0, full.length);
  if (start > 0) {
    final sp = full.indexOf(' ', start);
    if (sp >= 0 && sp < first) start = sp + 1;
  }
  final end = (start + width).clamp(0, full.length);
  var s = full.substring(start, end);
  final prefix = start > 0 ? '…' : '';
  final suffix = end < full.length ? '…' : '';
  final marks = <(int, int)>[];
  final sLow = s.toLowerCase();
  for (final t in terms) {
    var from = 0;
    while (true) {
      final i = sLow.indexOf(t, from);
      if (i < 0) break;
      marks.add((i + prefix.length, i + t.length + prefix.length));
      from = i + t.length;
    }
  }
  marks.sort((a, b) => a.$1.compareTo(b.$1));
  return ('$prefix$s$suffix', marks);
}

/// Index of every module body on the device, built on first use and rebuilt when the count changes.
class StudyIndex extends ChangeNotifier {
  StudyIndex._() : _frozen = false;
  static final StudyIndex instance = StudyIndex._();

  /// A fixed index that never rescans the database.
  @visibleForTesting
  StudyIndex.forTesting(this.docs) : _frozen = true;

  final bool _frozen;
  List<ModuleDoc> docs = const [];
  int _builtFor = -1;
  bool building = false;

  Future<void> ensureBuilt(AppDb db) async {
    if (building || _frozen) return;
    building = true;
    try {
      final keys = await db.snapshotKeysWithPrefix('lesson:');
      if (keys.length == _builtFor) return;
      final out = <ModuleDoc>[];
      for (final key in keys) {
        final row = await db.getSnapshot(key);
        if (row == null) continue;
        final id = key.substring('lesson:'.length);
        final slash = id.indexOf('/');
        if (slash < 0) continue;
        final m = fmt.m(row.$1);
        final content = fmt.s(m['content']);
        if (content.isEmpty) continue;
        out.add(indexModule(id.substring(0, slash), id.substring(slash + 1), content, title: fmt.s(m['title']).isEmpty ? null : fmt.s(m['title'])));
      }
      docs = out;
      _builtFor = keys.length;
      notifyListeners();
    } catch (_) {
      // A failed scan leaves the old index in place.
    } finally {
      building = false;
    }
  }
}
