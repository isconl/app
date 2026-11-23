import 'dart:math';

/// BI26112301 (note taking v2): one module's notes as a document of several notes, each anchored to a paragraph
/// (or to no paragraph, for a change of topic), each made of timestamped entries.
///
/// The server still keeps one text per module (`GET/POST /api/learning/notes`), so the document is written as plain
/// markdown with the machine fields in HTML comments. Old clients, the web console, the tutor and
/// `_kit/bin/pull-study-notes.sh` read it as ordinary markdown: a heading per note, a small time heading per entry.
/// A note written before v2 (no marker) reads as one note with one entry, dated by when it was saved.
const noteDocMarker = '<!-- isconl:notes v2 -->';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _two(int n) => n.toString().padLeft(2, '0');

/// "23 Nov, 08:41", with the year when it is not this year.
String noteStamp(DateTime t, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final year = t.year == n.year ? '' : ' ${t.year}';
  return '${t.day} ${_months[t.month - 1]}$year, ${_two(t.hour)}:${_two(t.minute)}';
}

String _clock(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

/// The first words of a paragraph, enough to find it again after the module is edited.
String paragraphQuote(String text, {int words = 8}) {
  final plain = text
      .replaceAll(RegExp(r'\*\*|__|`|\[\[|\]\]|\{[a-z]+\}'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final w = plain.split(' ').where((x) => x.isNotEmpty).toList();
  return w.take(words).join(' ');
}

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ').trim();

String _attr(String s) => s.replaceAll('"', "'").replaceAll('-->', '->').replaceAll('\n', ' ');

final _rand = Random();
String newNoteId() =>
    DateTime.now().microsecondsSinceEpoch.toRadixString(36) + _rand.nextInt(1 << 20).toRadixString(36);

class NoteEntry {
  NoteEntry({required this.id, required this.text, required this.createdAt, DateTime? updatedAt, this.draft = false})
      : updatedAt = updatedAt ?? createdAt;

  final String id;
  String text;
  final DateTime createdAt;
  DateTime updatedAt;

  /// Still being typed in the composer; becomes a plain entry on Save or when the card closes.
  bool draft;

  /// Changed a minute or more after it was first written.
  bool get edited => !draft && updatedAt.difference(createdAt).inSeconds >= 60;

  String stamp({DateTime? now}) =>
      noteStamp(createdAt, now: now) + (edited ? ' · edited ${_clock(updatedAt)}' : '');
}

class ModuleNote {
  ModuleNote({required this.id, this.anchor, this.quote = '', this.title = '', required this.createdAt, List<NoteEntry>? entries})
      : entries = entries ?? [];

  final String id;

  /// Block index of the paragraph in the module, or null for a note on no paragraph.
  final int? anchor;

  /// The paragraph's first words; this, not the index, is what finds the paragraph after an edit.
  final String quote;
  final String title;
  final DateTime createdAt;
  final List<NoteEntry> entries;

  bool get isEmpty => entries.every((e) => e.text.trim().isEmpty);

  NoteEntry? get draft => entries.where((e) => e.draft).firstOrNull;

  List<NoteEntry> get saved => entries.where((e) => !e.draft && e.text.trim().isNotEmpty).toList();

  DateTime get lastTouched =>
      entries.fold(createdAt, (t, e) => e.updatedAt.isAfter(t) ? e.updatedAt : t);

  /// "Paragraph 4: Price discovery starts with the…" or "General note".
  String get label {
    if (anchor == null) return title.trim().isNotEmpty ? title.trim() : 'General note';
    final q = quote.trim();
    return q.isEmpty ? 'Paragraph ${anchor! + 1}' : 'Paragraph ${anchor! + 1}: $q…';
  }

  bool matches({int? anchor, String quote = ''}) {
    if (anchor == null) return false;
    final q = _norm(quote);
    if (q.isNotEmpty && _norm(this.quote).isNotEmpty) return _norm(this.quote) == q;
    return this.anchor == anchor;
  }
}

class NoteDoc {
  NoteDoc([List<ModuleNote>? notes]) : notes = notes ?? [];

  final List<ModuleNote> notes;

  bool get isEmpty => notes.every((n) => n.isEmpty);

  int get entryCount => notes.fold(0, (c, n) => c + n.saved.length + ((n.draft?.text.trim().isNotEmpty ?? false) ? 1 : 0));

  ModuleNote? byId(String id) => notes.where((n) => n.id == id).firstOrNull;

  /// The note on this paragraph, if one exists.
  ModuleNote? forParagraph(int anchor, String quote) =>
      notes.where((n) => n.matches(anchor: anchor, quote: quote)).firstOrNull;

  /// The note last written in, for opening the card without a paragraph.
  ModuleNote? get latest {
    final live = notes.where((n) => !n.isEmpty).toList()
      ..sort((a, b) => b.lastTouched.compareTo(a.lastTouched));
    return live.firstOrNull;
  }

  ModuleNote add({int? anchor, String quote = '', String title = '', DateTime? now}) {
    final n = ModuleNote(id: newNoteId(), anchor: anchor, quote: quote, title: title, createdAt: now ?? DateTime.now());
    notes.add(n);
    return n;
  }

  /// Reads a stored note text. Text without the v2 marker is an older note: one note, one entry.
  static NoteDoc parse(String text, {int? legacyAnchor, DateTime? legacyAt}) {
    final src = text.replaceAll('\r\n', '\n');
    if (!src.trimLeft().startsWith(noteDocMarker)) {
      if (src.trim().isEmpty) return NoteDoc();
      final at = legacyAt ?? DateTime.now();
      return NoteDoc([
        ModuleNote(id: 'legacy', anchor: legacyAnchor, createdAt: at, entries: [
          NoteEntry(id: 'legacy-1', text: src.trim(), createdAt: at),
        ]),
      ]);
    }
    final lines = src.split('\n');
    final doc = NoteDoc();
    ModuleNote? note;
    NoteEntry? entry;
    final buf = <String>[];
    void flush() {
      if (entry != null) entry!.text = buf.join('\n').trim();
      buf.clear();
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final next = i + 1 < lines.length ? lines[i + 1].trim() : '';
      if (line.trim() == noteDocMarker) continue;
      if (line.startsWith('## ') && next.startsWith('<!-- note ')) {
        flush();
        entry = null;
        final a = _attrs(next);
        note = ModuleNote(
          id: a['id'] ?? newNoteId(),
          anchor: int.tryParse(a['anchor'] ?? ''),
          quote: a['quote'] ?? '',
          title: a['title'] ?? '',
          createdAt: DateTime.tryParse(a['created'] ?? '') ?? DateTime.now(),
        );
        doc.notes.add(note);
        i++;
        continue;
      }
      if (line.startsWith('### ') && next.startsWith('<!-- entry ')) {
        flush();
        final a = _attrs(next);
        note ??= () {
          final n = ModuleNote(id: newNoteId(), createdAt: DateTime.now());
          doc.notes.add(n);
          return n;
        }();
        final created = DateTime.tryParse(a['created'] ?? '') ?? DateTime.now();
        entry = NoteEntry(
          id: a['id'] ?? newNoteId(),
          text: '',
          createdAt: created,
          updatedAt: DateTime.tryParse(a['updated'] ?? '') ?? created,
          draft: a.containsKey('draft'),
        );
        note.entries.add(entry);
        i++;
        continue;
      }
      if (entry != null) {
        buf.add(line);
      } else if (line.trim().isNotEmpty) {
        // Text outside any entry (typed in by hand on the web): kept as an entry so nothing is lost.
        note ??= () {
          final n = ModuleNote(id: newNoteId(), createdAt: DateTime.now());
          doc.notes.add(n);
          return n;
        }();
        entry = NoteEntry(id: newNoteId(), text: '', createdAt: note.createdAt);
        note.entries.add(entry);
        buf.add(line);
      }
    }
    flush();
    return doc;
  }

  static Map<String, String> _attrs(String comment) {
    final body = comment.replaceFirst(RegExp(r'^<!--\s*\w+\s*'), '').replaceFirst(RegExp(r'\s*-->$'), '');
    final out = <String, String>{};
    for (final m in RegExp(r'(\w+)(?:=("[^"]*"|\S+))?').allMatches(body)) {
      var v = m.group(2) ?? '';
      if (v.startsWith('"') && v.endsWith('"') && v.length >= 2) v = v.substring(1, v.length - 1);
      out[m.group(1)!] = v;
    }
    return out;
  }

  /// The stored text: markdown for people, the comments for the app. Empty notes and empty drafts are dropped.
  String serialize() {
    final live = notes.where((n) => !n.isEmpty).toList();
    if (live.isEmpty) return '';
    final b = StringBuffer('$noteDocMarker\n');
    for (final n in live) {
      b.writeln();
      b.writeln('## ${n.label}');
      b.write('<!-- note id=${n.id}');
      if (n.anchor != null) b.write(' anchor=${n.anchor}');
      if (n.quote.isNotEmpty) b.write(' quote="${_attr(n.quote)}"');
      if (n.title.isNotEmpty) b.write(' title="${_attr(n.title)}"');
      b.writeln(' created=${n.createdAt.toIso8601String()} -->');
      for (final e in n.entries.where((e) => e.text.trim().isNotEmpty)) {
        b.writeln();
        b.writeln('### ${noteStamp(e.createdAt, now: DateTime(0))}${e.edited ? ' · edited ${_clock(e.updatedAt)}' : ''}${e.draft ? ' · draft' : ''}');
        b.writeln('<!-- entry id=${e.id} created=${e.createdAt.toIso8601String()} '
            'updated=${e.updatedAt.toIso8601String()}${e.draft ? ' draft' : ''} -->');
        b.writeln(e.text.trim());
      }
    }
    return b.toString();
  }

  /// The same document without the app's comments, for reading, copying and export. [level] is the heading level
  /// of a note (an entry is one deeper).
  String readable({int level = 2}) {
    final live = notes.where((n) => !n.isEmpty).toList();
    final b = StringBuffer();
    final h1 = '#' * level, h2 = '#' * (level + 1);
    final single = live.length == 1 && live.first.id == 'legacy';
    for (final n in live) {
      if (!single) b.writeln('$h1 ${n.label}\n');
      for (final e in n.entries.where((e) => e.text.trim().isNotEmpty)) {
        if (!single) b.writeln('$h2 ${e.stamp()}\n');
        b.writeln('${e.text.trim()}\n');
      }
    }
    return b.toString().trim();
  }
}
