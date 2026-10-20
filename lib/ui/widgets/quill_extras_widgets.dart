import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/client.dart';
import '../../app_scope.dart';
import '../../services/documents.dart';
import '../../services/quill_extras.dart';
import '../../theme.dart';
import '../views/learning_export_stub.dart' if (dart.library.io) '../views/learning_export_native.dart' as export_impl;
import 'common.dart';

/// BI26101508: the binder, article drafting and the image-packaging card. Each takes its api so a test passes a fake.

String _say(Object e) {
  if (e is ApiException) {
    if (e.status == 404 || e.status == 501) return 'This hub does not serve that yet.';
    return e.message;
  }
  if (e is OfflineException) return 'Offline.';
  return '$e';
}

// ── Binder ─────────────────────────────────────────────────────────────────

/// The Decision Architect binder: episodes, and the LinkedIn-ready post each compiles to. Copying is the reader's tap.
class BinderTab extends StatefulWidget {
  const BinderTab({super.key, this.api});
  final QuillExtrasApi? api;

  @override
  State<BinderTab> createState() => _BinderTabState();
}

class _BinderTabState extends State<BinderTab> {
  QuillExtrasApi? _api;
  List<BinderEpisode>? _episodes;
  String? _error;
  String? _openEpisode;
  CompiledEpisode? _compiled;
  bool _compiling = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_api != null) return;
    _api = widget.api ?? HubQuillExtrasApi(AppScope.of(context).api);
    _load();
  }

  Future<void> _load() async {
    try {
      final e = await _api!.binderEpisodes();
      if (mounted) setState(() => _episodes = e);
    } catch (e) {
      if (mounted) setState(() => _error = _say(e));
    }
  }

  Future<void> _compile(BinderEpisode e) async {
    setState(() {
      _openEpisode = e.episodeId;
      _compiled = null;
      _compiling = true;
      _error = null;
    });
    try {
      final c = await _api!.compileEpisode(e.itemId);
      if (mounted) setState(() => _compiled = c);
    } catch (x) {
      if (mounted) setState(() => _error = _say(x));
    } finally {
      if (mounted) setState(() => _compiling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_episodes == null && _error != null) {
      return ErrorRetry(_error!, onRetry: () {
        setState(() => _error = null);
        _load();
      });
    }
    if (_episodes == null) return const Center(child: MiniSpinner());
    final eps = _episodes!;
    return ListView(key: const Key('binder-list'), padding: const EdgeInsets.fromLTRB(14, 8, 14, 96), children: [
      SectionLabel('Episodes · ${eps.length}'),
      if (eps.isEmpty) const EmptyState('No episodes yet', 'Episode canvases of the Decision Architect appear here.', icon: Icons.menu_book_rounded),
      for (final e in eps)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Panel(
            key: Key('episode-${e.episodeId}'),
            color: _openEpisode == e.episodeId ? C.greenBg : C.panel,
            onTap: () => _compile(e),
            child: Row(children: [
              Expanded(child: Text('Episode ${e.episodeId}', style: T.w600(T.body2))),
              Text([if (e.version.isNotEmpty) 'v${e.version}', e.day].where((x) => x.isNotEmpty).join(' · '), style: T.monoSmall),
            ]),
          ),
        ),
      if (_compiling) const Padding(padding: EdgeInsets.all(16), child: Center(child: MiniSpinner())),
      if (_error != null && _episodes != null) ErrorRetry(_error!),
      if (_compiled != null) ...[
        SectionLabel(_compiled!.title.isEmpty ? 'Episode $_openEpisode' : _compiled!.title),
        Panel(
          key: const Key('binder-post'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (_compiled!.status.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(_compiled!.status, style: T.monoSmall)),
            SelectableText(_compiled!.linkedinPost, style: T.body2),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('binder-copy'),
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('Copy post'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _compiled!.linkedinPost));
                if (context.mounted) toast(context, 'Copied. Nothing was posted.');
              },
            ),
          ]),
        ),
      ],
    ]);
  }
}

// ── Article drafting ───────────────────────────────────────────────────────

/// One article, with Draft and Rewrite in a chosen tone. The text a button returns is a proposal: it can be copied or
/// taken as the working text on this screen, and nothing is saved or sent from here.
class ArticleAiScreen extends StatefulWidget {
  const ArticleAiScreen({super.key, required this.title, required this.file, this.api, this.docs});
  final String title, file;
  final QuillExtrasApi? api;
  final DocumentsApi? docs;

  @override
  State<ArticleAiScreen> createState() => _ArticleAiScreenState();
}

class _ArticleAiScreenState extends State<ArticleAiScreen> {
  QuillExtrasApi? _api;
  DocumentsApi? _docs;
  final _prompt = TextEditingController();
  String _text = '';
  String _tone = articleTones.first.$1;
  String? _proposal, _error;
  bool _loading = true, _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_api != null) return;
    final app = AppScope.of(context).api;
    _api = widget.api ?? HubQuillExtrasApi(app);
    _docs = widget.docs ?? HubDocumentsApi(app);
    _loadText();
  }

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _loadText() async {
    try {
      final f = await _docs!.rawFile(widget.file);
      if (mounted) setState(() => _text = utf8.decode(f.bytes, allowMalformed: true));
    } catch (e) {
      if (mounted) setState(() => _error = _say(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _run(ArticleAction a) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final out = await _api!.generateArticle(action: a, text: _text, title: widget.title, tone: _tone, prompt: _prompt.text.trim());
      if (mounted) setState(() => _proposal = out);
    } catch (e) {
      if (mounted) setState(() => _error = _say(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final words = RegExp(r'\S+').allMatches(_text).length;
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(title: Text(widget.title, overflow: TextOverflow.ellipsis)),
      body: _loading
          ? const Center(child: MiniSpinner())
          : ListView(padding: const EdgeInsets.fromLTRB(14, 10, 14, 96), children: [
              Text('$words words in the working text', key: const Key('article-words'), style: T.monoSmall),
              const SizedBox(height: 8),
              DropdownButton<String>(
                key: const Key('article-tone'),
                isExpanded: true,
                value: _tone,
                items: [for (final t in articleTones) DropdownMenuItem(value: t.$1, child: Text('Tone: ${t.$2}'))],
                onChanged: (v) => setState(() => _tone = v ?? _tone),
              ),
              Field(label: 'What to write or change (optional)', controller: _prompt, maxLines: 3),
              Row(children: [
                for (final a in ArticleAction.values) ...[
                  Expanded(child: FilledButton(key: Key('article-${a.name}'), onPressed: _busy ? null : () => _run(a), child: Text(_busy ? 'Working…' : a.label))),
                  const SizedBox(width: 8),
                ],
              ]),
              if (_error != null) ErrorRetry(_error!),
              if (_proposal != null) ...[
                const SectionLabel('Proposed text'),
                Panel(
                  key: const Key('article-proposal'),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SelectableText(_proposal!, style: T.body2),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, children: [
                      OutlinedButton(
                        key: const Key('article-use'),
                        onPressed: () => setState(() {
                          _text = _proposal!;
                          _proposal = null;
                        }),
                        child: const Text('Use as working text'),
                      ),
                      OutlinedButton(
                        key: const Key('article-copy'),
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: _proposal!));
                          if (context.mounted) toast(context, 'Copied. Nothing was saved or sent.');
                        },
                        child: const Text('Copy'),
                      ),
                      TextButton(key: const Key('article-drop'), onPressed: () => setState(() => _proposal = null), child: const Text('Drop')),
                    ]),
                  ]),
                ),
              ],
              const SectionLabel('Working text'),
              Panel(child: SelectableText(_text.isEmpty ? '(empty)' : _text, key: const Key('article-text'), style: T.small)),
            ]),
    );
  }
}

// ── Image packaging ────────────────────────────────────────────────────────

/// Live sourcing progress for the hero-image job, polled every 20 s while it is not done, with a way to take what is
/// ready now. The count comes from the disk on the server, so it cannot flatter.
class ImageProgressCard extends StatefulWidget {
  const ImageProgressCard({super.key, this.api, this.docs, this.every = const Duration(seconds: 20), this.save});
  final QuillExtrasApi? api;
  final DocumentsApi? docs;
  final Duration every;

  /// Saves the zip on the device; tests pass a fake.
  final Future<bool> Function(String name, List<int> bytes)? save;

  @override
  State<ImageProgressCard> createState() => _ImageProgressCardState();
}

class _ImageProgressCardState extends State<ImageProgressCard> {
  QuillExtrasApi? _api;
  DocumentsApi? _docs;
  ImageProgress? _p;
  Timer? _timer;
  bool _packaging = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_api != null) return;
    final app = AppScope.of(context).api;
    _api = widget.api ?? HubQuillExtrasApi(app);
    _docs = widget.docs ?? HubDocumentsApi(app);
    _poll();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    try {
      final p = await _api!.imageProgress();
      if (!mounted) return;
      setState(() => _p = p);
      _timer?.cancel();
      if (!p.done) _timer = Timer(widget.every, _poll);
    } catch (_) {
      // No progress source on this hub: the card stays away rather than showing an error on every task.
      if (mounted) setState(() => _p = null);
    }
  }

  Future<void> _package() async {
    setState(() => _packaging = true);
    try {
      final r = await _api!.packageImages();
      final f = await _docs!.rawFile(r.rel);
      final ok = await (widget.save ?? ((n, b) => export_impl.saveAndOpenExport(n, b, mime: 'application/zip')))(r.name.isEmpty ? f.filename : r.name, f.bytes);
      if (mounted) toast(context, ok ? '${r.images} images packaged (${r.mb} MB)' : '${r.images} images packaged, but this device cannot save files from here');
    } catch (e) {
      if (mounted) toast(context, _say(e), error: true);
    } finally {
      if (mounted) setState(() => _packaging = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    if (p == null) return const SizedBox.shrink();
    final short = p.shortSites;
    return Panel(
      key: const Key('image-progress'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Image sourcing: ${p.have} of ${p.want} verified on disk${p.done ? ' - complete' : ' - fleets running'}', style: T.body2)),
          Text('${p.percent}% · ${p.mb} MB', key: const Key('image-percent'), style: T.monoSmall),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(value: p.percent / 100, minHeight: 6, color: p.done ? C.green : C.amber, backgroundColor: C.border),
        ),
        if (!p.done) ...[
          const SizedBox(height: 6),
          Text('still sourcing: ${short.map((s) => '${s.site} (${s.expected - s.have} short)').join(', ')}', key: const Key('image-short'), style: T.small.copyWith(color: C.text3)),
          const SizedBox(height: 6),
          OutlinedButton(
            key: const Key('image-package'),
            onPressed: _packaging ? null : _package,
            child: Text(_packaging ? 'Packaging…' : 'Download what is ready'),
          ),
        ],
      ]),
    );
  }
}
