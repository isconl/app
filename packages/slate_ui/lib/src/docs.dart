import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData, HapticFeedback;

/// BI26112340 (Sconl, 23 Nov 2026): slate's docs on the phone, read the way modules are read, kept in step with live
/// slate, and annotated. Written as the base of a standalone slate app: everything that is the host's (how markdown is
/// drawn, where offline copies live, how an annotation is written) comes in through the types below, so the same
/// screens mount in iSconl now and in slate's own app later.

/// One doc as slate holds it.
class SlateDoc {
  const SlateDoc({required this.key, required this.text, this.etag = '', this.fetchedAt, this.offline = false});
  final String key;
  final String text;

  /// slate's sha256 of the text: two copies with one etag are the same doc.
  final String etag;
  final DateTime? fetchedAt;

  /// True when this is the phone's last copy because slate could not be reached.
  final bool offline;

  SlateDoc copyWith({bool? offline}) =>
      SlateDoc(key: key, text: text, etag: etag, fetchedAt: fetchedAt, offline: offline ?? this.offline);
}

/// The doc reads a host gives slate's docs screens. iSconl answers through hub's `/api/slate/docs/<name>`.
abstract class SlateDocsClient {
  Future<SlateDoc> doc(String key);
}

/// Where the phone keeps its last copy of each doc and the docs opened lately. The host decides the storage.
abstract class SlateDocStore {
  Future<SlateDoc?> read(String key);
  Future<void> write(SlateDoc doc);
  Future<List<String>> recents();
  Future<void> touch(String key);
}

/// A store that forgets on restart, for tests and for a host with no storage yet.
class MemoryDocStore implements SlateDocStore {
  final Map<String, SlateDoc> _docs = {};
  final List<String> _recent = [];
  @override
  Future<SlateDoc?> read(String key) async => _docs[key];
  @override
  Future<void> write(SlateDoc doc) async => _docs[doc.key] = doc;
  @override
  Future<List<String>> recents() async => List.of(_recent);
  @override
  Future<void> touch(String key) async {
    _recent
      ..remove(key)
      ..insert(0, key);
    if (_recent.length > 20) _recent.removeRange(20, _recent.length);
  }
}

/// What the renderer is handed: a long-press on a paragraph (to annotate it), and a slot it fills so the outline can
/// jump to a heading by its slug.
class SlateDocHooks {
  SlateDocHooks({required this.onParagraphLongPress});
  final void Function(int block, String text) onParagraphLongPress;
  bool Function(String slug)? revealHeading;
}

typedef SlateDocRenderer = Widget Function(BuildContext context, String markdown, SlateDocHooks hooks);

/// Opens the host's annotation editor on a doc, on one paragraph when [block] is given.
typedef SlateDocAnnotate = Future<void> Function(BuildContext context, String key, {int? block, String? text, String? title});

/// Draws the doc's annotations under it (the host's notes section), or null for none.
typedef SlateDocAnnotations = Widget? Function(BuildContext context, String key, String title);

/// The host's pieces, in one value so a screen deep in the tree gets all of them.
class SlateDocsHost {
  const SlateDocsHost({
    required this.client,
    required this.store,
    required this.render,
    this.annotate,
    this.annotations,
    this.indexKey = 'PHONE-DOCS.md',
    this.refreshEvery = const Duration(seconds: 60),
  });
  final SlateDocsClient client;
  final SlateDocStore store;
  final SlateDocRenderer render;
  final SlateDocAnnotate? annotate;
  final SlateDocAnnotations? annotations;

  /// The doc that lists the docs worth having to hand, as markdown links grouped under headings.
  final String indexKey;

  /// While a doc is open, how often it asks slate whether it changed.
  final Duration refreshEvery;
}

/// A doc name in plain words: `sconl.FEDORA-INSTALL.md` reads "Fedora install", `STYLUS-SCONL.md` "Stylus sconl".
String docTitle(String key) {
  var k = key.replaceAll(RegExp(r'\.md$', caseSensitive: false), '');
  final dot = k.indexOf('.');
  if (dot > 0 && k.substring(0, dot) == k.substring(0, dot).toLowerCase() && dot < k.length - 1) {
    k = k.substring(dot + 1);
  }
  k = k.replaceAll(RegExp(r'[-_.]+'), ' ').trim().toLowerCase();
  return k.isEmpty ? key : k[0].toUpperCase() + k.substring(1);
}

/// The project a doc belongs to, from its prefix (`sconl.FEDORA-INSTALL.md` -> `sconl`), or empty.
String docProject(String key) {
  final dot = key.indexOf('.');
  if (dot <= 0) return '';
  final p = key.substring(0, dot);
  return p == p.toLowerCase() && !key.toLowerCase().startsWith('$p.md') ? p : '';
}

final docNamePattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,118}\.md$');

class DocIndexEntry {
  const DocIndexEntry({required this.key, required this.title, this.note = '', this.group = ''});
  final String key;
  final String title;
  final String note;
  final String group;
}

/// Reads the index doc: every `[title](NAME.md)` link, with the words after it and the heading it sits under.
List<DocIndexEntry> parseDocIndex(String markdown) {
  final out = <DocIndexEntry>[];
  var group = '';
  final link = RegExp(r'\[([^\]]+)\]\(([A-Za-z0-9][A-Za-z0-9._-]*\.md)\)\s*[:,]?\s*(.*)$');
  for (final raw in markdown.split('\n')) {
    final line = raw.trim();
    final h = RegExp(r'^#{2,4}\s+(.*)$').firstMatch(line);
    if (h != null) {
      group = h.group(1)!.trim();
      continue;
    }
    final m = link.firstMatch(line);
    if (m == null) continue;
    out.add(DocIndexEntry(key: m.group(2)!, title: m.group(1)!.trim(), note: m.group(3)!.trim(), group: group));
  }
  return out;
}

/// The doc's headings, for the outline: (level, text, slug) in reading order. Fenced code is skipped.
List<(int, String, String)> docOutline(String markdown) {
  final out = <(int, String, String)>[];
  var fenced = false;
  for (final line in markdown.split('\n')) {
    if (line.trimLeft().startsWith('```')) fenced = !fenced;
    if (fenced) continue;
    final m = RegExp(r'^(#{1,4})\s+(.+?)\s*#*\s*$').firstMatch(line);
    if (m == null) continue;
    final text = m.group(2)!.replaceAll(RegExp(r'\*\*|__|`|\{[a-z]+\}\s*'), '').trim();
    out.add((m.group(1)!.length, text, headingSlugOf(text)));
  }
  return out;
}

/// The same slug rule iSconl's markdown uses for heading anchors.
String headingSlugOf(String text) => text
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');

String _clock(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String _when(DateTime t) {
  final n = DateTime.now();
  final today = t.year == n.year && t.month == n.month && t.day == n.day;
  return today ? _clock(t) : '${t.day} ${_months[t.month - 1]}, ${_clock(t)}';
}

/// Loads a doc: the phone's copy at once, then slate's, which replaces it when it differs.
class SlateDocController extends ChangeNotifier {
  SlateDocController(this.host, this.key);
  final SlateDocsHost host;
  final String key;

  SlateDoc? doc;
  bool loading = false;
  String? error;

  /// Set when slate sent a newer text while the doc was open, until the reader looks.
  bool changedWhileOpen = false;
  Timer? _timer;
  bool _disposed = false;

  Future<void> start() async {
    final kept = await host.store.read(key);
    if (kept != null && !_disposed) {
      doc = kept.copyWith(offline: true);
      notifyListeners();
    }
    unawaited(host.store.touch(key));
    await refresh();
    _timer = Timer.periodic(host.refreshEvery, (_) => refresh(quiet: true));
  }

  Future<void> refresh({bool quiet = false}) async {
    if (loading || _disposed) return;
    loading = true;
    if (!quiet) notifyListeners();
    try {
      final live = await host.client.doc(key);
      if (_disposed) return;
      final changed = doc != null && doc!.etag.isNotEmpty && live.etag.isNotEmpty && doc!.etag != live.etag;
      if (changed && quiet) changedWhileOpen = true;
      doc = SlateDoc(key: live.key, text: live.text, etag: live.etag, fetchedAt: DateTime.now());
      error = null;
      await host.store.write(doc!);
    } catch (e) {
      if (_disposed) return;
      error = '$e';
      if (doc != null) doc = doc!.copyWith(offline: true);
    } finally {
      loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  void seenChange() {
    changedWhileOpen = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}

/// One doc, read like a module: the doc's own reading surface, an outline, three text sizes, copy, a live-sync line
/// and annotations (a long-press on a paragraph, or the pen button).
class SlateDocScreen extends StatefulWidget {
  const SlateDocScreen({super.key, required this.host, required this.docKey});
  final SlateDocsHost host;
  final String docKey;

  @override
  State<SlateDocScreen> createState() => _SlateDocScreenState();
}

class _SlateDocScreenState extends State<SlateDocScreen> {
  late final SlateDocController _c = SlateDocController(widget.host, widget.docKey);
  late final SlateDocHooks _hooks = SlateDocHooks(onParagraphLongPress: _annotateParagraph);
  final _scroll = ScrollController();
  static int _size = 1; // kept for the life of the app: 0 small, 1 normal, 2 large
  static const _scales = [0.9, 1.0, 1.15];

  String get _title => docTitle(widget.docKey);

  @override
  void initState() {
    super.initState();
    _c.addListener(_changed);
    _c.start();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (_c.changedWhileOpen) {
      _c.seenChange();
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Updated from slate')));
    }
  }

  @override
  void dispose() {
    _c.removeListener(_changed);
    _c.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _annotateParagraph(int block, String text) async {
    final a = widget.host.annotate;
    if (a == null) return;
    HapticFeedback.selectionClick();
    await a(context, widget.docKey, block: block, text: text, title: _title);
  }

  void _outline() {
    final doc = _c.doc;
    if (doc == null) return;
    final items = docOutline(doc.text);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
          child: items.isEmpty
              ? const Padding(padding: EdgeInsets.all(24), child: Text('This doc has no headings.'))
              : ListView(
                  key: const Key('doc-outline'),
                  shrinkWrap: true,
                  children: [
                    for (final (level, text, slug) in items)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.only(left: 16.0 + (level - 1) * 14, right: 16),
                        title: Text(text,
                            style: TextStyle(fontWeight: level <= 2 ? FontWeight.w600 : FontWeight.w400)),
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _hooks.revealHeading?.call(slug);
                        },
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _copy() async {
    final doc = _c.doc;
    if (doc == null) return;
    await Clipboard.setData(ClipboardData(text: doc.text));
    if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Doc copied')));
  }

  Widget _syncLine(ThemeData theme) {
    final doc = _c.doc;
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final (IconData icon, String words, Color? colour) = switch ((doc, _c.loading, _c.error)) {
      (null, true, _) => (Icons.cloud_download_outlined, 'Loading from slate', null),
      (null, _, final String e) => (Icons.cloud_off_rounded, 'Could not reach slate: $e', theme.colorScheme.error),
      (final SlateDoc d, _, _) when d.offline =>
        (Icons.cloud_off_rounded, 'Offline copy${d.fetchedAt == null ? '' : ' from ${_when(d.fetchedAt!)}'}', Colors.amber),
      (final SlateDoc d, _, _) => (Icons.cloud_done_rounded, 'Live from slate · synced ${_when(d.fetchedAt ?? DateTime.now())}', Colors.green),
      _ => (Icons.cloud_queue_rounded, '', null),
    };
    return Row(key: const Key('doc-sync'), children: [
      Icon(icon, size: 13, color: colour ?? muted?.color),
      const SizedBox(width: 6),
      Expanded(child: Text(words, style: muted?.copyWith(color: colour ?? muted.color), overflow: TextOverflow.ellipsis)),
      if (_c.loading && doc != null) const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final doc = _c.doc;
    final project = docProject(widget.docKey);
    final notes = widget.host.annotations?.call(context, widget.docKey, _title);
    final mq = MediaQuery.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(key: const Key('doc-outline-btn'), tooltip: 'Outline', icon: const Icon(Icons.toc_rounded), onPressed: doc == null ? null : _outline),
          IconButton(
            key: const Key('doc-size'),
            tooltip: 'Text size',
            icon: const Icon(Icons.format_size_rounded),
            onPressed: () => setState(() => _size = (_size + 1) % _scales.length),
          ),
          PopupMenuButton<String>(
            key: const Key('doc-more'),
            onSelected: (v) => switch (v) { 'copy' => _copy(), 'refresh' => _c.refresh(), _ => null },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'refresh', child: ListTile(leading: Icon(Icons.sync_rounded), title: Text('Refresh from slate'))),
              PopupMenuItem(value: 'copy', child: ListTile(leading: Icon(Icons.copy_rounded), title: Text('Copy the doc'))),
            ],
          ),
        ],
      ),
      floatingActionButton: widget.host.annotate == null || doc == null
          ? null
          : FloatingActionButton.small(
              key: const Key('doc-annotate'),
              heroTag: 'doc-annotate',
              tooltip: 'Annotate',
              onPressed: () => widget.host.annotate!(context, widget.docKey, title: _title),
              child: const Icon(Icons.edit_note_rounded),
            ),
      body: RefreshIndicator(
        onRefresh: () => _c.refresh(),
        child: MediaQuery(
          data: mq.copyWith(textScaler: TextScaler.linear(mq.textScaler.scale(1) * _scales[_size])),
          child: SingleChildScrollView(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 96),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (project.isNotEmpty)
                    Text(project.toUpperCase(),
                        style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1.2, color: theme.colorScheme.onSurfaceVariant)),
                  Text(widget.docKey, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 6),
                  _syncLine(theme),
                  const SizedBox(height: 14),
                  if (doc == null && !_c.loading && _c.error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: FilledButton.tonalIcon(onPressed: _c.refresh, icon: const Icon(Icons.refresh_rounded), label: const Text('Try again')),
                    ),
                  if (doc == null && _c.loading) const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
                  if (doc != null) KeyedSubtree(key: ValueKey(doc.etag), child: widget.host.render(context, doc.text, _hooks)),
                  if (doc != null && notes != null) ...[const SizedBox(height: 24), notes],
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The list of docs: the pinned ones from the index doc, the ones opened lately, and a field to open any doc by name.
class SlateDocsTab extends StatefulWidget {
  const SlateDocsTab({super.key, required this.host});
  final SlateDocsHost host;

  @override
  State<SlateDocsTab> createState() => _SlateDocsTabState();
}

class _SlateDocsTabState extends State<SlateDocsTab> {
  late final SlateDocController _index = SlateDocController(widget.host, widget.host.indexKey);
  final _field = TextEditingController();
  List<String> _recent = const [];
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _index.addListener(_update);
    _index.start();
    _loadRecent();
  }

  Future<void> _loadRecent() async {
    final r = await widget.host.store.recents();
    if (mounted) setState(() => _recent = r.where((k) => k != widget.host.indexKey).toList());
  }

  void _update() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _index.removeListener(_update);
    _index.dispose();
    _field.dispose();
    super.dispose();
  }

  Future<void> open(String key) async {
    var k = key.trim();
    if (k.isEmpty) return;
    if (!k.toLowerCase().endsWith('.md')) k = '$k.md';
    if (!docNamePattern.hasMatch(k)) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('"$k" is not a doc name')));
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SlateDocScreen(host: widget.host, docKey: k)));
    await _loadRecent();
  }

  bool _match(String a, String b) => _filter.isEmpty || a.toLowerCase().contains(_filter) || b.toLowerCase().contains(_filter);

  Widget _tile(String key, String title, String note) {
    final theme = Theme.of(context);
    final project = docProject(key);
    return Card(
      key: Key('doc-tile-$key'),
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => open(key),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(children: [
            Icon(Icons.article_outlined, color: theme.colorScheme.primary, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                if (note.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(note, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text([if (project.isNotEmpty) project, key].join(' · '),
                      style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded, size: 18),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = _index.doc == null ? const <DocIndexEntry>[] : parseDocIndex(_index.doc!.text);
    final groups = <String, List<DocIndexEntry>>{};
    for (final e in entries.where((e) => _match(e.title, e.key))) {
      groups.putIfAbsent(e.group.isEmpty ? 'Pinned' : e.group, () => []).add(e);
    }
    final pinnedKeys = entries.map((e) => e.key).toSet();
    final recent = _recent.where((k) => !pinnedKeys.contains(k) && _match(docTitle(k), k)).toList();
    Widget label(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(2, 16, 2, 8),
          child: Text(t.toUpperCase(), style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1.1, color: theme.colorScheme.onSurfaceVariant)),
        );
    return RefreshIndicator(
      onRefresh: () async {
        await _index.refresh();
        await _loadRecent();
      },
      child: ListView(
        key: const Key('docs-tab'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 32),
        children: [
          TextField(
            key: const Key('doc-open-field'),
            controller: _field,
            textInputAction: TextInputAction.go,
            onChanged: (v) => setState(() => _filter = v.trim().toLowerCase()),
            onSubmitted: open,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: 'Find a doc, or type its name to open it',
              suffixIcon: IconButton(
                key: const Key('doc-open-go'),
                tooltip: 'Open',
                icon: const Icon(Icons.arrow_forward_rounded),
                onPressed: () => open(_field.text),
              ),
            ),
          ),
          if (_index.doc == null && _index.loading) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          if (_index.doc == null && !_index.loading && _index.error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Could not reach slate for the doc list. Type a doc name above to open it.', style: theme.textTheme.bodySmall),
            ),
          for (final g in groups.entries) ...[label(g.key), for (final e in g.value) _tile(e.key, e.title, e.note)],
          if (recent.isNotEmpty) ...[label('Opened lately'), for (final k in recent) _tile(k, docTitle(k), '')],
          if (_index.doc != null && groups.isEmpty && recent.isEmpty && _filter.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('No docs pinned yet. Type a doc name above to open it.', style: theme.textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}
