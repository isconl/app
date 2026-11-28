/// BI26112301: several notes per module, each anchored to its paragraph, each entry with its own time.
///
/// The server keeps one text per module (`/api/learning/notes`, spark), and the web console shows that text as
/// markdown. So the entries live inside that one text, each opened by a one-line HTML comment that markdown never
/// shows:
///
/// ```text
/// <!-- note id=n1k2 anchor=3 created=2026-11-26T18:30:00Z edited=2026-11-26T18:41:00Z quote="Ship the base phrase" -->
/// the entry's own text
/// ```
///
/// A note written before this (plain text, no markers) reads as one entry with no anchor and no time, and is
/// written back unchanged until it is edited. Old clients keep working: they see readable text.
library;

class NoteEntry {
  const NoteEntry({required this.id, required this.text, this.anchor, this.quote = '', this.created, this.edited});
  final String id;
  final String text;
  final int? anchor;
  final String quote;
  final DateTime? created;
  final DateTime? edited;

  NoteEntry copyWith({String? text, DateTime? edited}) =>
      NoteEntry(id: id, text: text ?? this.text, anchor: anchor, quote: quote, created: created, edited: edited ?? this.edited);
}

final _marker = RegExp(r'^<!-- note ([^\n]*?) -->[ \t]*$', multiLine: true);
final _attr = RegExp(r'(\w+)=("((?:[^"\\]|\\.)*)"|\S+)');

String _esc(String v) => v.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll('\n', ' ').replaceAll('-->', '- ->');
String _unesc(String v) => v.replaceAllMapped(RegExp(r'\\(.)'), (m) => m.group(1)!);

/// The entries in a module's note text, in the order written.
List<NoteEntry> parseNoteEntries(String text) {
  final marks = _marker.allMatches(text).toList();
  if (marks.isEmpty) {
    final t = text.trim();
    return t.isEmpty ? const [] : [NoteEntry(id: 'legacy', text: t)];
  }
  final out = <NoteEntry>[];
  final lead = text.substring(0, marks.first.start).trim();
  if (lead.isNotEmpty) out.add(NoteEntry(id: 'legacy', text: lead));
  for (var i = 0; i < marks.length; i++) {
    final m = marks[i];
    final end = i + 1 < marks.length ? marks[i + 1].start : text.length;
    final attrs = <String, String>{};
    for (final a in _attr.allMatches(m.group(1)!)) {
      attrs[a.group(1)!] = a.group(3) != null ? _unesc(a.group(3)!) : a.group(2)!;
    }
    out.add(NoteEntry(
      id: attrs['id'] ?? 'e$i',
      text: text.substring(m.end, end).trim(),
      anchor: int.tryParse(attrs['anchor'] ?? ''),
      quote: attrs['quote'] ?? '',
      created: DateTime.tryParse(attrs['created'] ?? ''),
      edited: DateTime.tryParse(attrs['edited'] ?? ''),
    ));
  }
  return out;
}

String _iso(DateTime t) => '${t.toUtc().toIso8601String().substring(0, 19)}Z';

/// The module's note text for [entries]. A lone legacy entry is written back as the plain text it was.
String serializeNoteEntries(List<NoteEntry> entries) {
  final kept = entries.where((e) => e.text.trim().isNotEmpty).toList();
  if (kept.length == 1 && kept.first.id == 'legacy') return kept.first.text.trim();
  final b = StringBuffer();
  for (final e in kept) {
    if (b.isNotEmpty) b.write('\n\n');
    b.write('<!-- note id=${e.id}');
    if (e.anchor != null) b.write(' anchor=${e.anchor}');
    if (e.created != null) b.write(' created=${_iso(e.created!)}');
    if (e.edited != null) b.write(' edited=${_iso(e.edited!)}');
    if (e.quote.isNotEmpty) b.write(' quote="${_esc(e.quote)}"');
    b.write(' -->\n');
    b.write(e.text.trim());
  }
  return b.toString();
}

/// Readable text for display, export and copying: each entry under a small time line, no markers.
String readableNoteText(String text) {
  final es = parseNoteEntries(text);
  if (es.length == 1 && es.first.id == 'legacy') return es.first.text;
  return es.map((e) {
    final head = [
      if (e.created != null) noteTime(e.created!),
      if (e.edited != null) 'edited',
      if (e.quote.isNotEmpty) '"${e.quote}"',
    ].join(' · ');
    return head.isEmpty ? e.text : '$head\n${e.text}';
  }).join('\n\n');
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "23 Nov, 08:41" in the phone's own time.
String noteTime(DateTime t) {
  final l = t.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${l.day} ${_months[l.month - 1]}, ${two(l.hour)}:${two(l.minute)}';
}

/// The first few words of a paragraph, so an anchor still reads right after the module is edited.
String quoteOf(String paragraph, {int words = 6}) {
  final clean = paragraph
      .replaceAll(RegExp(r'\{[a-z]+\}'), '')
      .replaceAll(RegExp(r'[*_#>`\[\]]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final w = clean.split(' ').where((x) => x.isNotEmpty).take(words).toList();
  return w.join(' ');
}

/// A short id that is unique enough inside one module's note.
String newNoteId(DateTime now) => 'n${now.microsecondsSinceEpoch.toRadixString(36)}';
