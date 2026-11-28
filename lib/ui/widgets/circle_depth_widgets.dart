import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_scope.dart';
import '../../services/circle_depth.dart';
import '../../services/circle_pickers.dart';
import '../../theme.dart';
import '../../util/markdown.dart';

CircleDepthApi _defaultApi(BuildContext context) => HubCircleDepthApi(AppScope.of(context).api);

String _err(Object e) => '$e'.replaceFirst('ApiException(0): ', '').replaceFirst('Exception: ', '');

BoxDecoration _box() => BoxDecoration(border: Border.all(color: C.border), borderRadius: BorderRadius.circular(Sz.rMd));

// ---------------------------------------------------------------- reachout

/// "Ready to send": the message written for this person in their register. The reader
/// edits it and copies it; the app never sends it. "Sent it" logs the touch afterwards.
class ReachoutCard extends StatefulWidget {
  const ReachoutCard({super.key, required this.personId, required this.fallbackChannel, this.api, this.onLogged, this.pollStale = true});
  final String personId;

  /// The person's usual channel, used when logging a sent message that names none.
  final String fallbackChannel;
  final CircleDepthApi? api;
  final VoidCallback? onLogged;

  /// A stale draft is rewritten behind the scenes; look again once. Tests turn this off.
  final bool pollStale;

  @override
  State<ReachoutCard> createState() => _ReachoutCardState();
}

class _ReachoutCardState extends State<ReachoutCard> {
  CircleDepthApi get _api => widget.api ?? _defaultApi(context);
  final _body = TextEditingController();
  final _angle = TextEditingController();
  ReachoutState? _state;
  bool _busy = false;
  String? _message;
  Timer? _again;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _again?.cancel();
    _body.dispose();
    _angle.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await _api.reachout(widget.personId);
      if (!mounted) return;
      setState(() {
        _state = s;
        if (s.reachout != null) _body.text = s.reachout!.body;
      });
      if (s.stale && widget.pollStale) _again = Timer(const Duration(seconds: 9), _load);
    } catch (e) {
      if (mounted) setState(() => _state = ReachoutState(error: _err(e)));
    }
  }

  Future<void> _rewrite({String intent = ''}) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final r = await _api.rewriteReachout(widget.personId, intent: intent);
      if (mounted) {
        setState(() {
          _state = ReachoutState(reachout: r);
          _body.text = r.body;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _message = _err(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sent() async {
    final r = _state?.reachout;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await _api.logSent(
        widget.personId,
        channel: (r?.channel.isNotEmpty ?? false) ? r!.channel : (widget.fallbackChannel.isEmpty ? 'message' : widget.fallbackChannel),
        summary: sentSummary(_body.text),
      );
      if (mounted) setState(() => _message = 'Logged. The next message is already rewriting.');
      widget.onLogged?.call();
      unawaited(_load());
    } catch (e) {
      if (mounted) setState(() => _message = _err(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _state;
    final r = s?.reachout;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: _box(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Ready to send', style: T.title),
        Text('Written in their register. You send it yourself.', style: T.tiny),
        const SizedBox(height: 8),
        if (s == null)
          Text('Loading the message...', style: T.small)
        else if (r == null)
          Text(s.error.isEmpty ? 'No message yet.' : s.error, key: const Key('reachout-none'), style: T.small)
        else ...[
          Wrap(spacing: 8, children: [
            if (r.urgency.isNotEmpty) Text('${r.urgency} priority', key: const Key('reachout-urgency'), style: T.tiny.copyWith(color: C.amber)),
            if (r.channel.isNotEmpty) Text(r.channel, style: T.tiny),
            if (s.stale) Text('rewriting with the newest context...', key: const Key('reachout-stale'), style: T.tiny),
          ]),
          if (r.why.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(r.why, style: T.small)),
          if (r.intent.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('The angle: ${r.intent}', style: T.small.copyWith(fontStyle: FontStyle.italic))),
          const SizedBox(height: 8),
          TextField(
            key: const Key('reachout-text'),
            controller: _body,
            minLines: 4,
            maxLines: 12,
            decoration: const InputDecoration(border: OutlineInputBorder(), helperText: 'Edit it freely. What you leave here is what gets copied.'),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton(
              key: const Key('reachout-copy'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _body.text));
                if (mounted) setState(() => _message = 'Copied. Go and send it.');
              },
              child: const Text('Copy the message'),
            ),
            OutlinedButton(key: const Key('reachout-sent'), onPressed: _busy ? null : _sent, child: const Text('Sent it: log the touch')),
            OutlinedButton(key: const Key('reachout-regen'), onPressed: _busy ? null : () => _rewrite(), child: const Text('Different words')),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(key: const Key('reachout-angle'), controller: _angle, decoration: const InputDecoration(isDense: true, hintText: 'A different angle: what must it achieve?')),
            ),
            TextButton(
              key: const Key('reachout-rewrite'),
              onPressed: _busy
                  ? null
                  : () {
                      final a = _angle.text.trim();
                      if (a.isEmpty) {
                        setState(() => _message = 'Say what the message should achieve.');
                        return;
                      }
                      _rewrite(intent: a);
                    },
              child: const Text('Rewrite'),
            ),
          ]),
        ],
        if (_message != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_message!, key: const Key('reachout-message'), style: T.small)),
      ]),
    );
  }
}

// ---------------------------------------------------------------- tags

/// A person's tags as chips, with remove and add. The Circle's tag list is shared, so
/// the owner screen reloads after a change.
class PersonTagsCard extends StatefulWidget {
  const PersonTagsCard({super.key, required this.personId, required this.tags, this.api, this.onChanged});
  final String personId;
  final List<String> tags;
  final CircleDepthApi? api;
  final VoidCallback? onChanged;

  @override
  State<PersonTagsCard> createState() => _PersonTagsCardState();
}

class _PersonTagsCardState extends State<PersonTagsCard> {
  late List<String> _tags = [...widget.tags];
  String? _message;

  CircleDepthApi get _api => widget.api ?? _defaultApi(context);

  Future<void> _add() async {
    final tag = await showDialog<String>(context: context, builder: (_) => const _TextDialog(title: 'Add a tag', hint: 'e.g. mentor, alumni, investor'));
    if (tag == null || tag.trim().isEmpty) return;
    try {
      await _api.addTag(widget.personId, tag.trim());
      if (mounted) {
        setState(() {
          if (!_tags.contains(tag.trim())) _tags.add(tag.trim());
          _message = null;
        });
      }
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) setState(() => _message = _err(e));
    }
  }

  Future<void> _remove(String tag) async {
    try {
      await _api.removeTag(widget.personId, tag);
      if (mounted) {
        setState(() {
          _tags.remove(tag);
          _message = null;
        });
      }
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) setState(() => _message = _err(e));
    }
  }

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(14),
        decoration: _box(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Tags', style: T.title)),
            TextButton(key: const Key('tag-add'), onPressed: _add, child: const Text('Add a tag')),
          ]),
          if (_tags.isEmpty) Text('No tags yet.', style: T.small),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final t in _tags)
              InputChip(
                key: Key('chip-$t'),
                label: Text(t),
                onDeleted: () => _remove(t),
                deleteButtonTooltipMessage: 'Remove $t',
              ),
          ]),
          if (_message != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_message!, key: const Key('tag-error'), style: T.small.copyWith(color: C.red))),
        ]),
      );
}

/// Every tag with how many people carry it: rename, merge (with the affected count
/// shown first) and delete (confirmed).
class TagsManager extends StatefulWidget {
  const TagsManager({super.key, this.api, this.onChanged});
  final CircleDepthApi? api;
  final VoidCallback? onChanged;

  @override
  State<TagsManager> createState() => _TagsManagerState();
}

class _TagsManagerState extends State<TagsManager> {
  CircleDepthApi get _api => widget.api ?? _defaultApi(context);
  List<TagCount>? _tags;
  String? _error;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final t = await _api.tags();
      if (mounted) {
        setState(() {
          _tags = t;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = _err(e));
    }
  }

  Future<void> _do(String done, Future<void> Function() action) async {
    try {
      await action();
      widget.onChanged?.call();
      if (mounted) setState(() => _message = done);
      await _load();
    } catch (e) {
      if (mounted) setState(() => _message = _err(e));
    }
  }

  Future<void> _rename(TagCount t) async {
    final to = await showDialog<String>(context: context, builder: (_) => _TextDialog(title: 'Rename "${t.tag}"', initial: t.tag, hint: 'New name'));
    if (to == null || to.trim().isEmpty || to.trim() == t.tag) return;
    await _do('Renamed "${t.tag}" to "${to.trim()}".', () => _api.renameTag(t.tag, to.trim()));
  }

  Future<void> _merge(TagCount t) async {
    final others = [for (final x in _tags ?? <TagCount>[]) if (x.tag != t.tag) x];
    if (others.isEmpty) {
      setState(() => _message = 'There is no other tag to merge into.');
      return;
    }
    final into = await showDialog<String>(context: context, builder: (_) => _MergeDialog(source: t, targets: others));
    if (into == null) return;
    await _do('Merged "${t.tag}" into "$into".', () => _api.mergeTags([t.tag], into));
  }

  Future<void> _delete(TagCount t) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete tag "${t.tag}"?'),
        content: Text('Removes it from ${t.count} contact${t.count == 1 ? '' : 's'}. The contacts themselves are untouched.', key: const Key('tag-delete-warning')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep it')),
          FilledButton(key: const Key('tag-delete-confirm'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete tag')),
        ],
      ),
    );
    if (sure != true) return;
    await _do('Deleted tag "${t.tag}".', () => _api.deleteTag(t.tag));
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Center(child: Text(_error!, key: const Key('tags-error'), style: T.small.copyWith(color: C.red)));
    final tags = _tags;
    if (tags == null) return const Center(child: CircularProgressIndicator());
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (tags.isEmpty) Text('No tags yet. Add one from a person.', style: T.small),
      for (final t in tags)
        Container(
          key: Key('tag-${t.tag}'),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
          decoration: _box(),
          child: Row(children: [
            Expanded(child: Text(t.tag, style: T.body)),
            Text('${t.count}', key: Key('count-${t.tag}'), style: T.monoSmall),
            PopupMenuButton<String>(
              key: Key('tag-menu-${t.tag}'),
              onSelected: (v) => switch (v) {
                'rename' => _rename(t),
                'merge' => _merge(t),
                _ => _delete(t),
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('Rename')),
                PopupMenuItem(value: 'merge', child: Text('Merge into another tag')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ]),
        ),
      if (_message != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_message!, key: const Key('tags-message'), style: T.small)),
    ]);
  }
}

class _MergeDialog extends StatefulWidget {
  const _MergeDialog({required this.source, required this.targets});
  final TagCount source;
  final List<TagCount> targets;
  @override
  State<_MergeDialog> createState() => _MergeDialogState();
}

class _MergeDialogState extends State<_MergeDialog> {
  late String _into = widget.targets.first.tag;

  @override
  Widget build(BuildContext context) {
    final s = widget.source;
    return AlertDialog(
      title: Text('Merge "${s.tag}"'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        DropdownButton<String>(
          key: const Key('merge-into'),
          isExpanded: true,
          value: _into,
          items: [for (final t in widget.targets) DropdownMenuItem(value: t.tag, child: Text('${t.tag} (${t.count})'))],
          onChanged: (v) => setState(() => _into = v ?? _into),
        ),
        const SizedBox(height: 8),
        // The count first: this is the number of people whose tag will change.
        Text('${s.count} contact${s.count == 1 ? '' : 's'} carrying "${s.tag}" will carry "$_into" instead.', key: const Key('merge-affected'), style: T.small),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(key: const Key('merge-confirm'), onPressed: () => Navigator.pop(context, _into), child: const Text('Merge')),
      ],
    );
  }
}

class _TextDialog extends StatefulWidget {
  const _TextDialog({required this.title, this.initial = '', this.hint = ''});
  final String title;
  final String initial;
  final String hint;
  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final TextEditingController _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(key: const Key('text-dialog-field'), controller: _c, autofocus: true, decoration: InputDecoration(hintText: widget.hint)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(key: const Key('text-dialog-ok'), onPressed: () => Navigator.pop(context, _c.text), child: const Text('OK')),
        ],
      );
}

// ---------------------------------------------------------------- who can

/// "Who can": ask for a capability and see who in the Circle has it (with the evidence),
/// then warm paths through people who know someone who does.
class WhoCanView extends StatefulWidget {
  const WhoCanView({super.key, this.api, this.onOpen});
  final CircleDepthApi? api;
  final void Function(String personId)? onOpen;
  @override
  State<WhoCanView> createState() => _WhoCanViewState();
}

class _WhoCanViewState extends State<WhoCanView> {
  CircleDepthApi get _api => widget.api ?? _defaultApi(context);
  final _q = TextEditingController();
  WhoCan? _result;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final q = _q.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await _api.whoCan(q);
      if (mounted) setState(() => _result = r);
    } catch (e) {
      if (mounted) setState(() => _error = _err(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          Expanded(child: TextField(key: const Key('whocan-q'), controller: _q, onSubmitted: (_) => _go(), decoration: const InputDecoration(hintText: 'Who can introduce me to an investor?'))),
          IconButton(key: const Key('whocan-go'), onPressed: _busy ? null : _go, icon: const Icon(Icons.search_rounded)),
        ]),
        const SizedBox(height: 12),
        if (_error != null) Text(_error!, key: const Key('whocan-error'), style: T.small.copyWith(color: C.red)),
        if (_busy) Text('Searching the graph...', style: T.small),
        if (_result != null && _result!.isEmpty) Text('Nobody on record matches yet. Capabilities grow as evidence lands.', key: const Key('whocan-none'), style: T.small),
        for (final p in _result?.direct ?? const <WhoCanPerson>[])
          ListTile(
            key: Key('direct-${p.id}'),
            contentPadding: EdgeInsets.zero,
            title: Text(p.name, style: T.body),
            subtitle: Text([p.role.isNotEmpty ? p.role : p.circle, if (p.why.isNotEmpty) p.why.first].join('\n'), style: T.small),
            onTap: () => widget.onOpen?.call(p.id),
          ),
        if (_result != null && _result!.adjacent.isNotEmpty) ...[
          Padding(padding: const EdgeInsets.only(top: 10, bottom: 4), child: Text('WARM PATHS', style: T.label)),
          for (final p in _result!.adjacent)
            ListTile(
              key: Key('warm-${p.id}'),
              contentPadding: EdgeInsets.zero,
              title: Text(p.name, style: T.body),
              subtitle: Text(p.note, style: T.small),
              onTap: () => widget.onOpen?.call(p.id),
            ),
        ],
      ]);
}

// ---------------------------------------------------------------- analysis

/// The circle-wide read, precomputed and refreshed in the background.
class CircleAnalysisView extends StatefulWidget {
  const CircleAnalysisView({super.key, this.api});
  final CircleDepthApi? api;
  @override
  State<CircleAnalysisView> createState() => _CircleAnalysisViewState();
}

class _CircleAnalysisViewState extends State<CircleAnalysisView> {
  Future<String?>? _f;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _f ??= (widget.api ?? _defaultApi(context)).analysis();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
        future: _f,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) return Center(child: Text(_err(snap.error!), key: const Key('analysis-error'), style: T.small.copyWith(color: C.red)));
          final c = snap.data;
          if (c == null) return Padding(padding: const EdgeInsets.all(16), child: Text('The first circle-wide read is being written in the background. It appears here on its own.', key: const Key('analysis-none'), style: T.small));
          return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Markdown(c));
        },
      );
}

// ---------------------------------------------------------------- gallery

/// Photos and videos by person or event, with filters and upload from the camera roll.
/// Faces are never analysed in the app.
class CircleGalleryView extends StatefulWidget {
  const CircleGalleryView({super.key, this.api, this.pick = pickMedia, this.openUrl});
  final CircleDepthApi? api;
  final Future<PickedBytes?> Function() pick;
  final Future<void> Function(String url)? openUrl;

  @override
  State<CircleGalleryView> createState() => _CircleGalleryViewState();
}

class _CircleGalleryViewState extends State<CircleGalleryView> {
  CircleDepthApi get _api => widget.api ?? _defaultApi(context);
  GalleryFilters? _filters;
  String _mode = 'person';
  String _tag = '';
  String? _personId;
  String? _event;
  String _kind = 'photos';
  List<GalleryItem> _items = const [];
  bool _loading = false;
  String? _error;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFilters());
  }

  Future<void> _loadFilters() async {
    try {
      final f = await _api.galleryFilters();
      if (mounted) setState(() => _filters = f);
    } catch (e) {
      if (mounted) setState(() => _error = _err(e));
    }
  }

  String? get _target => _mode == 'person' ? _personId : _event;

  Future<void> _loadItems() async {
    final id = _target;
    if (id == null) {
      setState(() => _items = const []);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _api.galleryItems(scope: _mode, id: id);
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) {
        setState(() {
          _items = const [];
          _error = _err(e);
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _upload() async {
    final id = _target;
    if (id == null) return;
    final f = await widget.pick();
    if (f == null) return;
    setState(() => _message = 'Uploading ${f.name}...');
    try {
      await _api.galleryUpload(scope: _mode, id: id, kind: _kind, fileName: f.name, bytes: f.bytes, contentType: f.contentType);
      if (mounted) setState(() => _message = '${f.name} uploaded.');
      await _loadItems();
    } catch (e) {
      if (mounted) setState(() => _message = 'Upload failed: ${_err(e)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = _filters;
    if (f == null) return Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!, key: const Key('gallery-error'), style: T.small.copyWith(color: C.red)));
    final people = f.peopleWith(_tag);
    return ListView(padding: const EdgeInsets.all(16), children: [
      SegmentedButton<String>(
        key: const Key('gallery-mode'),
        segments: const [ButtonSegment(value: 'person', label: Text('By person')), ButtonSegment(value: 'event', label: Text('By event'))],
        selected: {_mode},
        onSelectionChanged: (s) => setState(() {
          _mode = s.first;
          _items = const [];
        }),
      ),
      const SizedBox(height: 8),
      if (_mode == 'person') ...[
        DropdownButton<String>(
          key: const Key('gallery-tag'),
          isExpanded: true,
          value: _tag,
          items: [const DropdownMenuItem(value: '', child: Text('any tag')), for (final t in f.tags) DropdownMenuItem(value: t, child: Text(t))],
          onChanged: (v) => setState(() {
            _tag = v ?? '';
            if (_personId != null && !f.peopleWith(_tag).any((p) => p.id == _personId)) {
              _personId = null;
              _items = const [];
            }
          }),
        ),
        DropdownButton<String>(
          key: const Key('gallery-person'),
          isExpanded: true,
          value: people.any((p) => p.id == _personId) ? _personId : '',
          items: [const DropdownMenuItem(value: '', child: Text('choose a person...')), for (final p in people) DropdownMenuItem(value: p.id, child: Text(p.name))],
          onChanged: (v) {
            setState(() => _personId = (v == null || v.isEmpty) ? null : v);
            _loadItems();
          },
        ),
      ] else ...[
        if (f.events.isEmpty) Text('No event folders found yet.', style: T.small),
        DropdownButton<String>(
          key: const Key('gallery-event'),
          isExpanded: true,
          value: f.events.contains(_event) ? _event : '',
          items: [const DropdownMenuItem(value: '', child: Text('choose an event...')), for (final e in f.events) DropdownMenuItem(value: e, child: Text(e))],
          onChanged: (v) {
            setState(() => _event = (v == null || v.isEmpty) ? null : v);
            _loadItems();
          },
        ),
      ],
      if (_target != null) ...[
        Row(children: [
          if (_mode == 'person')
            DropdownButton<String>(
              key: const Key('gallery-kind'),
              value: _kind,
              items: [for (final k in ['photos', 'videos', 'captures']) DropdownMenuItem(value: k, child: Text(k))],
              onChanged: (v) => setState(() => _kind = v ?? _kind),
            ),
          const Spacer(),
          FilledButton.icon(key: const Key('gallery-upload'), onPressed: _upload, icon: const Icon(Icons.upload_rounded, size: 16), label: const Text('Upload')),
        ]),
      ],
      if (_message != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_message!, key: const Key('gallery-message'), style: T.small)),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_error!, key: const Key('gallery-error'), style: T.small.copyWith(color: C.red))),
      const SizedBox(height: 10),
      if (_loading) const Center(child: CircularProgressIndicator())
      else if (_target == null) Text('Pick ${_mode == 'person' ? 'a person' : 'an event'} to see their gallery.', style: T.small)
      else if (_items.isEmpty) Text('Nothing here yet.', key: const Key('gallery-empty'), style: T.small)
      else
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          children: [
            for (final i in _items)
              InkWell(
                key: Key('item-${i.id}'),
                onTap: () => _openItem(i),
                child: i.isVideo
                    ? Container(decoration: _box(), child: const Center(child: Icon(Icons.play_circle_outline_rounded, size: 32)))
                    : Image.network(i.downloadUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(decoration: _box(), child: Center(child: Text(i.name, style: T.tiny, maxLines: 3, overflow: TextOverflow.ellipsis)))),
              ),
          ],
        ),
    ]);
  }

  void _openItem(GalleryItem i) {
    if (i.isVideo) {
      final open = widget.openUrl ?? (u) async => launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication).then((_) {});
      open(i.downloadUrl);
      return;
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Flexible(child: InteractiveViewer(child: Image.network(i.downloadUrl, errorBuilder: (_, __, ___) => Padding(padding: const EdgeInsets.all(20), child: Text(i.name, style: T.small))))),
          TextButton(key: const Key('lightbox-close'), onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- chat import

/// Read a chat archive: pick a WhatsApp, Telegram or Signal export, send it to the
/// reader's own hub, see who was recognised, and add anyone who was not (a sender
/// mapping step: suggest and confirm, never automatic). Private: filed to the vault,
/// never sent to a cloud model.
class ChatImportView extends StatefulWidget {
  const ChatImportView({super.key, this.api, this.pick = pickChatExport, this.onOpen});
  final CircleDepthApi? api;
  final Future<PickedBytes?> Function() pick;
  final void Function(String personId)? onOpen;
  @override
  State<ChatImportView> createState() => _ChatImportViewState();
}

class _ChatImportViewState extends State<ChatImportView> {
  CircleDepthApi get _api => widget.api ?? _defaultApi(context);
  bool _busy = false;
  String? _error;
  ChatImportResult? _result;
  final List<ChatUnmatched> _unmatched = [];
  String? _message;

  Future<void> _import() async {
    final f = await widget.pick();
    if (f == null) return;
    if (f.bytes.length > maxChatBytes) {
      setState(() => _error = 'Export one chat rather than everything. Keep it under 12 MB.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
      _message = null;
    });
    try {
      final r = await _api.importChat(f.name, f.bytes);
      if (mounted) {
        setState(() {
          _result = r;
          _unmatched
            ..clear()
            ..addAll(r.unmatched);
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = _err(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addSender(ChatUnmatched u) async {
    final form = await showDialog<_SenderForm>(context: context, builder: (_) => _SenderDialog(speaker: u.speaker));
    if (form == null || _result == null) return;
    try {
      final r = await _api.addSender(importId: _result!.importId, speaker: u.speaker, name: form.name, circle: form.circle, role: form.role, cadence: form.cadence);
      if (mounted) {
        setState(() {
          _unmatched.removeWhere((x) => x.speaker == u.speaker);
          _message = '${r.name} joins the circle. ${r.messages} messages filed.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _message = _err(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('Read a chat archive', style: T.title),
      Text('Private: filed to your vault, never sent to a cloud model. A real conversation is the best evidence about a person.', style: T.small),
      const SizedBox(height: 10),
      FilledButton.icon(
        key: const Key('chat-pick'),
        onPressed: _busy ? null : _import,
        icon: const Icon(Icons.upload_file_rounded, size: 18),
        label: Text(_busy ? 'Filing, reading and rewriting the profiles...' : 'Choose a chat export (.zip or .txt)'),
      ),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, key: const Key('chat-error'), style: T.small.copyWith(color: C.red))),
      if (r != null) ...[
        const SizedBox(height: 12),
        Text('${r.messages} messages read${r.channel.isNotEmpty ? ', ${r.channel}' : ''}${r.filed ? ', filed to the vault' : ', NOT filed (connect Microsoft 365)'}', key: const Key('chat-summary'), style: T.body2),
        const SizedBox(height: 8),
        if (r.updated.isEmpty) Text('Nobody in the archive matched anyone in your Circle.', key: const Key('chat-none'), style: T.small.copyWith(color: C.amber))
        else ...[
          Text('PROFILES REWRITTEN FROM THE ARCHIVE', style: T.label),
          for (final u in r.updated)
            ListTile(
              key: Key('updated-${u.id}'),
              contentPadding: EdgeInsets.zero,
              title: Text(u.name, style: T.body),
              subtitle: u.note.isEmpty ? null : Text(u.note, style: T.small),
              trailing: Text('${u.messages} msgs', style: T.monoSmall),
              onTap: () => widget.onOpen?.call(u.id),
            ),
        ],
        if (_unmatched.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('IN THE ARCHIVE BUT NOT IN YOUR CIRCLE', style: T.label),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final u in _unmatched)
              ActionChip(key: Key('unmatched-${u.speaker}'), label: Text('${u.speaker} (${u.count}) + Add to Circle'), onPressed: () => _addSender(u)),
          ]),
        ],
        if (_message != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_message!, key: const Key('chat-message'), style: T.small)),
      ],
    ]);
  }
}

class _SenderForm {
  const _SenderForm(this.name, this.circle, this.role, this.cadence);
  final String name;
  final String circle;
  final String role;
  final String cadence;
}

class _SenderDialog extends StatefulWidget {
  const _SenderDialog({required this.speaker});
  final String speaker;
  @override
  State<_SenderDialog> createState() => _SenderDialogState();
}

class _SenderDialogState extends State<_SenderDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.speaker);
  final _role = TextEditingController();
  final _cadence = TextEditingController();
  String _circle = 'social';

  @override
  void dispose() {
    _name.dispose();
    _role.dispose();
    _cadence.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Add to the Circle'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(key: const Key('sender-name'), controller: _name, decoration: const InputDecoration(labelText: 'Name')),
            DropdownButton<String>(
              key: const Key('sender-circle'),
              isExpanded: true,
              value: _circle,
              items: [for (final c in ['family', 'professional', 'social']) DropdownMenuItem(value: c, child: Text(c))],
              onChanged: (v) => setState(() => _circle = v ?? _circle),
            ),
            TextField(key: const Key('sender-role'), controller: _role, decoration: const InputDecoration(labelText: 'Role or relationship')),
            TextField(key: const Key('sender-cadence'), controller: _cadence, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Contact every N days')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            key: const Key('sender-add'),
            onPressed: () => Navigator.pop(context, _SenderForm(_name.text.trim().isEmpty ? widget.speaker : _name.text.trim(), _circle, _role.text.trim(), _cadence.text.trim())),
            child: const Text('Add'),
          ),
        ],
      );
}

// ---------------------------------------------------------------- folder

/// Creates the person's folder in the reader's own vault, showing the path first.
class CreateFolderButton extends StatelessWidget {
  const CreateFolderButton({super.key, required this.personId, required this.name, required this.circle, this.met = '', this.api});
  final String personId;
  final String name;
  final String circle;
  final String met;
  final CircleDepthApi? api;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        key: const Key('create-folder'),
        icon: const Icon(Icons.create_new_folder_outlined, size: 16),
        label: const Text('Create their folder'),
        onPressed: () async {
          final messenger = ScaffoldMessenger.maybeOf(context);
          final a = api ?? _defaultApi(context);
          final folder = circleFolderFor(name: name, circle: circle, met: met);
          final sure = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Create their folder?'),
              content: Text(folder, key: const Key('folder-path')),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                FilledButton(key: const Key('folder-confirm'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
              ],
            ),
          );
          if (sure != true) return;
          try {
            await a.createFolder(personId, folder);
            messenger?.showSnackBar(SnackBar(content: Text('Created $folder')));
          } catch (e) {
            messenger?.showSnackBar(SnackBar(content: Text(_err(e))));
          }
        },
      );
}
