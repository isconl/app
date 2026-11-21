import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/study_search.dart';
import '../widgets/common.dart';
import 'learning.dart' show LessonScreen;

/// BI26100156: the entry at the top of Study. Tapping it opens the search.
class StudySearchEntry extends StatelessWidget {
  const StudySearchEntry({super.key});

  @override
  Widget build(BuildContext context) {
    return Panel(
      key: const Key('study-search-entry'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: () => Navigator.push<void>(context, MaterialPageRoute(builder: (_) => const StudySearchScreen())),
      child: Row(children: [
        const Icon(Icons.search_rounded, size: 18, color: C.text3),
        const SizedBox(width: 10),
        Text('Search modules, terms and text', style: T.body2.copyWith(color: C.text3)),
      ]),
    );
  }
}

class StudySearchScreen extends StatefulWidget {
  const StudySearchScreen({super.key, this.index});

  /// Replaced in tests.
  final StudyIndex? index;

  @override
  State<StudySearchScreen> createState() => _StudySearchScreenState();
}

class _StudySearchScreenState extends State<StudySearchScreen> {
  static const _recentKey = 'study.search.recent.v1';
  final _field = TextEditingController();
  Timer? _debounce;
  SearchResults _results = SearchResults.empty;
  String _query = '';
  List<String> _recent = [];
  bool _ready = false;

  StudyIndex get _index => widget.index ?? StudyIndex.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final db = AppScope.of(context).db;
      try {
        final saved = (await db.getSnapshot(_recentKey))?.$1;
        if (saved is List && mounted) setState(() => _recent = [for (final r in saved) '$r']);
      } catch (_) {}
      await _index.ensureBuilt(db);
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _field.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() {
        _query = v.trim();
        _results = searchDocs(_index.docs, v);
      });
    });
  }

  Future<void> _remember(String q) async {
    if (q.trim().length < minQueryLength) return;
    final next = [q.trim(), ..._recent.where((r) => r != q.trim())].take(10).toList();
    setState(() => _recent = next);
    try {
      await AppScope.of(context).db.putSnapshot(_recentKey, next);
    } catch (_) {}
  }

  Future<void> _clearRecent() async {
    setState(() => _recent = []);
    try {
      await AppScope.of(context).db.putSnapshot(_recentKey, <String>[]);
    } catch (_) {}
  }

  void _open(ModuleDoc d, {Para? para}) {
    _remember(_query);
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => LessonScreen(
          course: d.course,
          file: d.file,
          title: d.title,
          status: '',
          initialParagraph: para?.index,
          foundText: para?.text,
        ),
      ),
    );
  }

  Widget _snippet(TextHit h) {
    final spans = <TextSpan>[];
    var at = 0;
    for (final (a, b) in h.marks) {
      if (a < at) continue;
      if (a > at) spans.add(TextSpan(text: h.snippet.substring(at, a)));
      spans.add(TextSpan(text: h.snippet.substring(a, b), style: const TextStyle(color: C.greenBright, fontWeight: FontWeight.w700)));
      at = b;
    }
    if (at < h.snippet.length) spans.add(TextSpan(text: h.snippet.substring(at)));
    return Text.rich(TextSpan(children: spans), style: T.small.copyWith(color: C.text2), maxLines: 2, overflow: TextOverflow.ellipsis);
  }

  @override
  Widget build(BuildContext context) {
    final r = _results;
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        title: TextField(
          key: const Key('study-search-field'),
          controller: _field,
          autofocus: true,
          onChanged: _onChanged,
          onSubmitted: _remember,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(hintText: 'Search Study', border: InputBorder.none),
        ),
      ),
      body: !_ready
          ? const Center(child: MiniSpinner(size: 22))
          : _query.length < minQueryLength
              ? _recentList()
              : r.isEmpty
                  ? Padding(padding: const EdgeInsets.all(20), child: Text('Nothing found for "$_query" in the ${_index.docs.length} modules on this device.', style: T.small.copyWith(color: C.text3)))
                  : ListView(padding: const EdgeInsets.fromLTRB(14, 6, 14, 40), children: [
                      if (r.modules.isNotEmpty) ...[
                        const SectionLabel('Modules'),
                        for (final h in r.modules)
                          ListTile(
                            key: ValueKey('module-${h.doc.key}'),
                            dense: true,
                            title: Text(h.doc.title, style: T.body2.copyWith(color: C.text)),
                            subtitle: Text(h.doc.course, style: T.tiny),
                            onTap: () => _open(h.doc),
                          ),
                      ],
                      if (r.glossary.isNotEmpty) ...[
                        const SectionLabel('Glossary'),
                        for (final h in r.glossary)
                          ListTile(
                            key: ValueKey('gloss-${h.doc.key}-${h.term.term}'),
                            dense: true,
                            title: Text(h.term.term, style: T.body2.copyWith(color: C.violet)),
                            subtitle: Text(h.term.definition, style: T.tiny, maxLines: 2, overflow: TextOverflow.ellipsis),
                            onTap: () => _open(h.doc),
                          ),
                      ],
                      if (r.text.isNotEmpty) ...[
                        const SectionLabel('In the text'),
                        for (final h in r.text)
                          ListTile(
                            key: ValueKey('text-${h.doc.key}-${h.para.index}'),
                            dense: true,
                            title: _snippet(h),
                            subtitle: Text('${h.doc.title}${h.para.heading.isEmpty ? '' : ' · ${h.para.heading}'}', style: T.tiny, maxLines: 1, overflow: TextOverflow.ellipsis),
                            onTap: () => _open(h.doc, para: h.para),
                          ),
                      ],
                    ]),
    );
  }

  Widget _recentList() {
    if (_recent.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Text('${_index.docs.length} modules are searchable on this device. Type at least $minQueryLength letters.', style: T.small.copyWith(color: C.text3)),
      );
    }
    return ListView(padding: const EdgeInsets.fromLTRB(14, 6, 14, 40), children: [
      SectionLabel('Recent', trailing: TextButton(onPressed: _clearRecent, child: const Text('Clear'))),
      for (final q in _recent)
        ListTile(
          dense: true,
          leading: const Icon(Icons.history_rounded, size: 18),
          title: Text(q, style: T.body2),
          onTap: () {
            _field.text = q;
            _onChanged(q);
          },
        ),
    ]);
  }
}
