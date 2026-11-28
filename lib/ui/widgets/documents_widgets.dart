import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_scope.dart';
import '../../services/documents.dart';
import '../../theme.dart';
import '../../util/markdown.dart';
import '../views/learning_export_stub.dart' if (dart.library.io) '../views/learning_export_native.dart' as export_impl;
import 'common.dart';

DocumentsApi _defaultApi(BuildContext context) => HubDocumentsApi(AppScope.of(context).api);

String _err(Object e) => '$e'.replaceFirst('ApiException(0): ', '').replaceFirst('Exception: ', '');

String mimeFor(String name) {
  final n = name.toLowerCase();
  if (n.endsWith('.pdf')) return 'application/pdf';
  if (n.endsWith('.docx')) return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
  if (n.endsWith('.md') || n.endsWith('.txt')) return 'text/plain';
  if (n.endsWith('.xlsx')) return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  return 'application/octet-stream';
}

Future<bool> _confirm(BuildContext context, String title, String body, String yes, {bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: C.red) : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(yes),
        ),
      ],
    ),
  );
  return r == true;
}

// ----------------------------------------------------------- deliverable actions

/// What the reader can do with one task deliverable: read it in full, save and
/// open it, replace it with their edited copy, rebuild its Word copy, put it on
/// OneDrive now, and make a view link. Every write needs a tap, the replace and
/// the link each ask first, and nothing goes anywhere on its own.
class DeliverableActions extends StatefulWidget {
  const DeliverableActions({super.key, required this.rel, required this.name, this.api, this.onChanged});
  final String rel;
  final String name;
  final DocumentsApi? api;
  final VoidCallback? onChanged;

  @override
  State<DeliverableActions> createState() => _DeliverableActionsState();
}

class _DeliverableActionsState extends State<DeliverableActions> {
  DocumentsApi get _api => widget.api ?? _defaultApi(context);
  bool _busy = false;
  String? _message;
  String? _full;
  String? _link;

  Future<void> _run(String working, Future<String?> Function() job) async {
    setState(() {
      _busy = true;
      _message = working;
    });
    try {
      final done = await job();
      if (mounted) setState(() => _message = done);
    } catch (e) {
      if (mounted) setState(() => _message = _err(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _read() => _run('Reading...', () async {
        final t = await _api.render(widget.rel);
        if (mounted) setState(() => _full = t);
        return null;
      });

  Future<void> _open() => _run('Fetching...', () async {
        final f = await _api.rawFile(widget.rel);
        final name = f.filename.isEmpty ? widget.name : f.filename;
        final ok = await export_impl.saveAndOpenExport(name, f.bytes, mime: mimeFor(name));
        return ok ? null : 'Saved, but nothing on this device opens ${name.split('.').last} files.';
      });

  Future<void> _replace() async {
    final r = await FilePicker.platform.pickFiles(withData: true);
    final f = r?.files.single;
    if (f == null || f.bytes == null) return;
    final expected = widget.rel.split('/').last;
    if (!mounted) return;
    final ok = await _confirm(
      context,
      'Replace "$expected"?',
      f.name == expected
          ? 'Your copy "${f.name}" becomes the stored document. The previous version is kept.'
          : 'You picked "${f.name}". The stored name stays "$expected" and the contents become what you picked. The previous version is kept.',
      'Replace it',
    );
    if (!ok) return;
    await _run('Replacing...', () async {
      final m = await _api.replace(widget.rel, f.bytes!);
      widget.onChanged?.call();
      return m;
    });
  }

  Future<void> _twin() => _run('Rebuilding...', () async {
        final m = await _api.rebuildTwin(widget.rel);
        widget.onChanged?.call();
        return m;
      });

  Future<void> _push() => _run('Pushing...', () async {
        await _api.pushToOneDrive(widget.rel);
        widget.onChanged?.call();
        return 'On OneDrive. The phone copy is current now.';
      });

  Future<void> _share() async {
    final ok = await _confirm(
      context,
      'Make a view link?',
      'This creates a link to "${widget.name}" that anyone holding it can open and read, without signing in. The hub does not set an expiry, so it stays live until you remove it in OneDrive. Nothing is sent: you decide who gets it.',
      'Create the link',
    );
    if (!ok) return;
    await _run('Linking...', () async {
      final url = await _api.shareLink(widget.rel);
      if (mounted) setState(() => _link = url);
      return url.isEmpty ? 'The hub made no link.' : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isMd = widget.name.toLowerCase().endsWith('.md');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 4, children: [
        TextButton(key: Key('doc-read-${widget.name}'), onPressed: _busy ? null : _read, child: const Text('Read all')),
        TextButton(key: Key('doc-open-${widget.name}'), onPressed: _busy ? null : _open, child: const Text('Open')),
        TextButton(key: Key('doc-replace-${widget.name}'), onPressed: _busy ? null : _replace, child: const Text('Replace')),
        if (isMd) TextButton(key: Key('doc-twin-${widget.name}'), onPressed: _busy ? null : _twin, child: const Text('Rebuild Word copy')),
        TextButton(key: Key('doc-push-${widget.name}'), onPressed: _busy ? null : _push, child: const Text('Put on OneDrive')),
        TextButton(key: Key('doc-share-${widget.name}'), onPressed: _busy ? null : _share, child: const Text('View link')),
      ]),
      if (_message != null) Text(_message!, key: Key('doc-message-${widget.name}'), style: T.tiny),
      if (_link != null && _link!.isNotEmpty)
        Row(children: [
          Expanded(child: SelectableText(_link!, key: Key('doc-link-${widget.name}'), style: T.small)),
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _link!));
              if (mounted) setState(() => _message = 'Link copied. Anyone with it can read the document.');
            },
            child: const Text('Copy'),
          ),
        ]),
      if (_full != null)
        Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(border: Border.all(color: C.border), borderRadius: BorderRadius.circular(Sz.rMd)),
          child: widget.name.toLowerCase().endsWith('.md') ? Markdown(_full!) : SelectableText(_full!, style: T.small),
        ),
    ]);
  }
}

// ----------------------------------------------------------- library

/// The generated documents, grouped by what they were for, with search and the
/// status filter. Delete asks first and says what it does.
class DocumentsLibrary extends StatefulWidget {
  const DocumentsLibrary({super.key, this.api, this.onEdit});
  final DocumentsApi? api;

  /// Reopens a stored document in the studio.
  final void Function(GeneratedDoc doc)? onEdit;

  @override
  State<DocumentsLibrary> createState() => _DocumentsLibraryState();
}

class _DocumentsLibraryState extends State<DocumentsLibrary> {
  DocumentsApi get _api => widget.api ?? _defaultApi(context);
  List<GeneratedDoc>? _docs;
  Map<String, String> _titles = const {};
  String _status = 'active';
  String _q = '';
  String? _error;
  String? _message;
  final _collapsed = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final docs = await _api.list(status: _status);
      var titles = _titles;
      try {
        titles = {for (final a in await _api.archetypes('_common')) a.id: a.title};
      } catch (_) {}
      if (mounted) {
        setState(() {
          _docs = docs;
          _titles = titles;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = _err(e));
    }
  }

  Future<void> _download(GeneratedDoc d) async {
    try {
      final f = await _api.download(d);
      final ok = await export_impl.saveAndOpenExport(f.filename, f.bytes, mime: mimeFor(f.filename));
      if (mounted) setState(() => _message = ok ? null : 'Saved, but nothing on this device opens ${f.filename.split('.').last} files.');
    } catch (e) {
      if (mounted) setState(() => _message = _err(e));
    }
  }

  Future<void> _status2(GeneratedDoc d, String status) async {
    if (status == 'deleted' &&
        !await _confirm(context, 'Delete this generated document?', 'The rendered files are removed from disk. The row stays on record, hidden by default.', 'Delete', danger: true)) {
      return;
    }
    try {
      await _api.setStatus(d.id, status);
      await _load();
    } catch (e) {
      if (mounted) setState(() => _message = _err(e));
    }
  }

  Future<void> _attach(GeneratedDoc d) async {
    try {
      final tasks = await _api.attachableTasks(d.id);
      if (!mounted) return;
      if (tasks.isEmpty) {
        setState(() => _message = "No tasks on this document's project to attach to.");
        return;
      }
      final pick = await showDialog<DocTask>(
        context: context,
        builder: (_) => SimpleDialog(
          title: const Text('Attach to task'),
          children: [for (final t in tasks) SimpleDialogOption(onPressed: () => Navigator.pop(context, t), child: Text(t.title))],
        ),
      );
      if (pick == null) return;
      await _api.attach(d.id, pick.id);
      if (mounted) setState(() => _message = 'Attached to ${pick.title}.');
      await _load();
    } catch (e) {
      if (mounted) setState(() => _message = _err(e));
    }
  }

  static const _kindLabels = {'engagement': 'Engagement', 'project': 'Project', 'general': 'General'};

  @override
  Widget build(BuildContext context) {
    final docs = _docs;
    if (_error != null && docs == null) return ErrorRetry(_error!, onRetry: _load);
    if (docs == null) return const Center(child: CircularProgressIndicator());
    final visible = searchDocs(docs, _q, _titles);
    final groups = groupDocs(visible);
    return ListView(padding: const EdgeInsets.fromLTRB(14, 8, 14, 96), children: [
      Row(children: [
        DropdownButton<String>(
          key: const Key('docs-status'),
          value: _status,
          items: [for (final s in const ['active', 'archived', 'deleted']) DropdownMenuItem(value: s, child: Text(s))],
          onChanged: (v) {
            if (v == null) return;
            setState(() {
              _status = v;
              _docs = null;
            });
            _load();
          },
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            key: const Key('docs-search'),
            decoration: const InputDecoration(isDense: true, hintText: 'Search name, target or type'),
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
      ]),
      Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text('${visible.length} document${visible.length == 1 ? '' : 's'}', style: T.tiny)),
      if (_message != null) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(_message!, key: const Key('docs-message'), style: T.small)),
      if (docs.isEmpty)
        Text("Nothing here yet. Generate a document and it'll show up in this list.", key: const Key('docs-empty'), style: T.small)
      else if (visible.isEmpty)
        Text('No documents match "$_q".', style: T.small),
      for (final g in groups) ...[
        InkWell(
          onTap: () => setState(() => _collapsed.contains(g.kind) ? _collapsed.remove(g.kind) : _collapsed.add(g.kind)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(children: [
              Expanded(child: Text(_kindLabels[g.kind] ?? g.kind, style: T.title)),
              Text('${g.count}', style: T.tiny),
              Icon(_collapsed.contains(g.kind) ? Icons.chevron_right : Icons.expand_more, size: 18),
            ]),
          ),
        ),
        if (!_collapsed.contains(g.kind))
          for (final sg in g.subgroups) ...[
            if (sg.label.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4, bottom: 2), child: Text(sg.label, style: T.small.copyWith(fontWeight: FontWeight.w600))),
            for (final d in sg.docs) _row(d),
          ],
      ],
    ]);
  }

  Widget _row(GeneratedDoc d) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(border: Border.all(color: C.border), borderRadius: BorderRadius.circular(Sz.rMd)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(d.filename, style: T.body2),
        Text(
          '${d.fromOneDrive ? 'OneDrive, not generated here' : (_titles[d.archetypeId] ?? d.archetypeId)}'
          '${d.createdAt.isEmpty ? '' : ', ${d.createdAt}'}${d.taskId.isEmpty ? '' : ', task ${d.taskId}'}',
          style: T.tiny,
        ),
        Wrap(spacing: 4, children: [
          TextButton(key: Key('dl-${d.id}'), onPressed: () => _download(d), child: const Text('Open')),
          if (!d.fromOneDrive && widget.onEdit != null) TextButton(key: Key('edit-${d.id}'), onPressed: () => widget.onEdit!(d), child: const Text('Edit fields')),
          if (d.canAttach) TextButton(key: Key('attach-${d.id}'), onPressed: () => _attach(d), child: const Text('Attach to task')),
          if (!d.fromOneDrive && d.status == 'active') TextButton(onPressed: () => _status2(d, 'archived'), child: const Text('Archive')),
          if (!d.fromOneDrive && d.status == 'archived') TextButton(onPressed: () => _status2(d, 'active'), child: const Text('Restore')),
          if (!d.fromOneDrive) TextButton(key: Key('del-${d.id}'), onPressed: () => _status2(d, 'deleted'), child: Text('Delete', style: TextStyle(color: C.red))),
        ]),
      ]),
    );
  }
}

// ----------------------------------------------------------- studio

/// Pick a target and a template, fill the fields (or have a model draft them from
/// a brief, for review), preview, and generate. A drafted field lands in its box
/// to be read and changed; nothing is generated unseen.
class DocumentStudio extends StatefulWidget {
  const DocumentStudio({super.key, this.api, this.reopen, this.onGenerated});
  final DocumentsApi? api;

  /// A stored document to reopen in the form (the library's "Edit fields").
  final GeneratedDoc? reopen;
  final VoidCallback? onGenerated;

  @override
  State<DocumentStudio> createState() => _DocumentStudioState();
}

class _DocumentStudioState extends State<DocumentStudio> {
  DocumentsApi get _api => widget.api ?? _defaultApi(context);
  DocTarget _target = const DocTarget('general');
  List<DocTarget>? _engagements;
  List<DocTarget>? _projects;
  List<Archetype>? _archetypes;
  Archetype? _active;
  final _values = <String, String>{};
  final _controllers = <String, TextEditingController>{};
  final _brief = TextEditingController();
  final _formats = <String, bool>{'docx': true, 'md': false, 'pdf': false};
  String _preview = '';
  GenerateResult? _result;
  String? _message;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.reopen != null) {
        _reopen(widget.reopen!);
      } else {
        _loadArchetypes();
      }
    });
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _brief.dispose();
    super.dispose();
  }

  Future<void> _loadArchetypes() async {
    try {
      final a = await _api.archetypes(_target.namespace);
      if (mounted) setState(() => _archetypes = a);
    } catch (e) {
      if (mounted) {
        setState(() {
          _archetypes = const [];
          _message = _err(e);
        });
      }
    }
  }

  Future<void> _setKind(String kind) async {
    setState(() {
      _target = DocTarget(kind);
      _active = null;
      _archetypes = null;
    });
    try {
      if (kind == 'engagement') _engagements ??= await _api.engagements();
      if (kind == 'project') _projects ??= await _api.projects();
    } catch (e) {
      if (mounted) setState(() => _message = _err(e));
    }
    if (mounted) {
      setState(() {});
      await _loadArchetypes();
    }
  }

  Future<void> _pick(DocTarget t) async {
    setState(() {
      _target = t;
      _active = null;
      _archetypes = null;
    });
    await _loadArchetypes();
  }

  TextEditingController _ctl(ArchetypeField f) => _controllers.putIfAbsent(f.name, () {
        final c = TextEditingController(text: _values[f.name] ?? '');
        c.addListener(() => _values[f.name] = c.text);
        return c;
      });

  Future<void> _choose(Archetype a) async {
    try {
      final full = await _api.schema(a, _target.namespace);
      if (!mounted) return;
      setState(() {
        _active = full;
        _values.clear();
        for (final c in _controllers.values) {
          c.dispose();
        }
        _controllers.clear();
        _preview = '';
        _result = null;
        _message = null;
      });
    } catch (e) {
      if (mounted) setState(() => _message = _err(e));
    }
  }

  Future<void> _reopen(GeneratedDoc d) async {
    try {
      final s = await _api.stored(d.id);
      _target = s.target;
      final list = await _api.archetypes(_target.namespace);
      final base = list.firstWhere((a) => a.id == s.archetype.id, orElse: () => Archetype(id: s.archetype.id, title: s.archetype.id));
      final full = await _api.schema(base, _target.namespace);
      if (!mounted) return;
      setState(() {
        _archetypes = list;
        _active = full;
        for (final f in full.fields) {
          _values[f.name] = fieldValueToText(f, s.content[f.name]);
        }
      });
    } catch (e) {
      if (mounted) setState(() => _message = _err(e));
      await _loadArchetypes();
    }
  }

  Map<String, dynamic> _payload() => {for (final f in _active!.fields) f.name: parseFieldValue(f, _values[f.name] ?? '')};

  void _fill(String name, String value) {
    _values[name] = value;
    final c = _controllers[name];
    if (c != null) c.text = value;
  }

  Future<void> _research(ArchetypeField f) async {
    setState(() => _busy = true);
    try {
      final v = await _api.researchField(_active!.id, f, _brief.text, _payload());
      if (mounted) setState(() => _fill(f.name, v));
    } catch (e) {
      if (mounted) setState(() => _message = _err(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _fullDraft() async {
    if (_brief.text.trim().isEmpty) {
      setState(() => _message = 'Write a brief first. A full draft needs something to work from.');
      return;
    }
    setState(() {
      _busy = true;
      _message = 'Drafting...';
    });
    try {
      final d = await _api.fullDraft(_active!.id, _active!.fields, _brief.text);
      if (mounted) {
        setState(() {
          d.forEach(_fill);
          _message = 'Draft filled in. Review it before generating.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _message = _err(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _doPreview() async {
    final missing = missingRequired(_active!.fields, _values);
    if (missing.isNotEmpty) {
      setState(() => _message = 'Still needed: ${missing.join(', ')}.');
      return;
    }
    setState(() => _busy = true);
    try {
      final md = await _api.preview(_target.namespace, _active!.id, _payload());
      if (mounted) setState(() => _preview = md);
    } catch (e) {
      if (mounted) setState(() => _message = _err(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _generate() async {
    final formats = [for (final e in _formats.entries) if (e.value) e.key];
    if (formats.isEmpty) {
      setState(() => _message = 'Pick at least one format.');
      return;
    }
    final missing = missingRequired(_active!.fields, _values);
    if (missing.isNotEmpty) {
      setState(() => _message = 'Still needed: ${missing.join(', ')}.');
      return;
    }
    setState(() {
      _busy = true;
      _message = 'Generating...';
    });
    try {
      final r = await _api.generate(_target.namespace, _active!.id, _payload(), formats);
      if (mounted) {
        setState(() {
          _result = r;
          _message = 'Generated ${r.files.length} file${r.files.length == 1 ? '' : 's'}.';
        });
      }
      widget.onGenerated?.call();
    } catch (e) {
      if (mounted) setState(() => _message = _err(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = _active;
    return ListView(padding: const EdgeInsets.fromLTRB(14, 8, 14, 96), children: [
      Text('Draft for', style: T.tiny),
      const SizedBox(height: 4),
      SegmentedButton<String>(
        key: const Key('studio-kind'),
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: 'engagement', label: Text('Engagement')),
          ButtonSegment(value: 'project', label: Text('Project')),
          ButtonSegment(value: 'general', label: Text('General')),
        ],
        selected: {_target.kind},
        onSelectionChanged: (s) => _setKind(s.first),
      ),
      if (_target.kind != 'general') _targetPicker(),
      if (_message != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_message!, key: const Key('studio-message'), style: T.small)),
      const SizedBox(height: 10),
      if (a == null) ..._archetypeList() else ..._form(a),
    ]);
  }

  Widget _targetPicker() {
    final list = _target.kind == 'engagement' ? _engagements : _projects;
    if (list == null) return Padding(padding: const EdgeInsets.only(top: 8), child: Text('Reading...', style: T.small));
    if (list.isEmpty) return Padding(padding: const EdgeInsets.only(top: 8), child: Text('None on record yet.', style: T.small));
    return DropdownButton<String>(
      key: const Key('studio-target'),
      isExpanded: true,
      hint: Text('Select ${_target.kind == 'engagement' ? 'an engagement' : 'a project'}'),
      value: list.any((t) => t.id == _target.id) ? _target.id : null,
      items: [for (final t in list) DropdownMenuItem(value: t.id, child: Text(t.label, overflow: TextOverflow.ellipsis))],
      onChanged: (id) {
        final t = list.firstWhere((x) => x.id == id);
        _pick(t);
      },
    );
  }

  List<Widget> _archetypeList() {
    final list = _archetypes;
    if (list == null) return [Text('Reading the templates...', style: T.small)];
    if (list.isEmpty) return [Text('No templates for this target.', key: const Key('studio-none'), style: T.small)];
    return [
      Text('Choose a template', style: T.title),
      for (final a in list)
        ListTile(
          key: Key('arch-${a.id}'),
          contentPadding: EdgeInsets.zero,
          title: Text(a.title),
          subtitle: Text(a.id, style: T.tiny),
          trailing: a.governed ? Text('governed', style: T.tiny) : null,
          onTap: () => _choose(a),
        ),
    ];
  }

  List<Widget> _form(Archetype a) {
    String? section;
    final out = <Widget>[
      Row(children: [
        Expanded(child: Text(a.title, style: T.title)),
        TextButton(onPressed: () => setState(() => _active = null), child: const Text('Templates')),
      ]),
      TextField(
        key: const Key('studio-brief'),
        controller: _brief,
        minLines: 2,
        maxLines: 5,
        decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'A brief for the model: what is this document about?'),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(key: const Key('studio-fulldraft'), onPressed: _busy ? null : _fullDraft, child: const Text('Draft every field from the brief')),
      ),
    ];
    for (final f in a.fields) {
      if (f.section.isNotEmpty && f.section != section) {
        section = f.section;
        out.add(Padding(padding: const EdgeInsets.only(top: 8), child: Text(f.section, style: T.title)));
      }
      out.add(_field(f));
    }
    out.addAll([
      const SizedBox(height: 10),
      Wrap(spacing: 10, children: [
        for (final e in _formats.entries)
          FilterChip(label: Text(e.key), selected: e.value, onSelected: (v) => setState(() => _formats[e.key] = v)),
      ]),
      Wrap(spacing: 8, children: [
        OutlinedButton(key: const Key('studio-preview'), onPressed: _busy ? null : _doPreview, child: const Text('Preview')),
        FilledButton(key: const Key('studio-generate'), onPressed: _busy ? null : _generate, child: const Text('Generate')),
      ]),
      if (_preview.isNotEmpty)
        Container(
          key: const Key('studio-preview-box'),
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(border: Border.all(color: C.border), borderRadius: BorderRadius.circular(Sz.rMd)),
          child: Markdown(_preview),
        ),
      if (_result != null) ...[
        const SizedBox(height: 10),
        Text('Generated files', style: T.title),
        for (final f in _result!.files)
          ListTile(
            key: Key('gen-${f.ext}'),
            contentPadding: EdgeInsets.zero,
            title: Text(f.filename),
            subtitle: Text('${(f.bytes.length / 1024).toStringAsFixed(1)} KB', style: T.tiny),
            trailing: TextButton(
              onPressed: () async {
                final ok = await export_impl.saveAndOpenExport(f.filename, f.bytes, mime: mimeFor(f.filename));
                if (mounted && !ok) setState(() => _message = 'Saved, but nothing on this device opens ${f.ext} files.');
              },
              child: const Text('Open'),
            ),
          ),
      ],
    ]);
    return out;
  }

  Widget _field(ArchetypeField f) {
    final label = f.required ? '${f.label} *' : f.label;
    final spark = IconButton(
      tooltip: 'Draft this field from the brief',
      icon: const Icon(Icons.auto_awesome, size: 18),
      onPressed: _busy ? null : () => _research(f),
    );
    Widget control;
    if (f.type == 'select') {
      control = DropdownButtonFormField<String>(
        key: Key('field-${f.name}'),
        initialValue: f.options.contains(_values[f.name]) ? _values[f.name] : null,
        items: [for (final o in f.options) DropdownMenuItem(value: o, child: Text(o))],
        onChanged: (v) => _values[f.name] = v ?? '',
        decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
      );
    } else {
      control = TextField(
        key: Key('field-${f.name}'),
        controller: _ctl(f),
        minLines: f.multiline ? (f.type == 'textarea' ? 3 : 4) : 1,
        maxLines: f.multiline ? 12 : 1,
        decoration: InputDecoration(isDense: true, border: const OutlineInputBorder(), helperText: f.hint.isEmpty ? null : f.hint),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Expanded(child: Text(label, style: T.small)), if (f.type != 'select') spark]),
        control,
      ]),
    );
  }
}
