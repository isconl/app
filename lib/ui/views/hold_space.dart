import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../data/db.dart';
import '../../data/hold_data.dart';
import '../../data/hold_device.dart';
import '../../data/hold_uploads.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../widgets/common.dart';
import '../widgets/space_header.dart';
import 'files.dart';

/// BH26101801: hold as the file manager of the Systems space. The shared search entry sits above exactly three tabs:
/// Browse (the hold tree), Recent (what was opened, added or changed, and the uploads in flight) and Device (the
/// device's own storage, in both directions). OneDrive stays behind a read-only "Archive" link on Browse.
///
/// Built against [HoldApi] so the fake server drives it until BH26102001 lands the live routes.
class HoldSpace extends StatefulWidget {
  const HoldSpace({super.key, this.api, this.queue, this.picker});

  /// Overrides for tests; the app passes none and gets the live client, the persisted queue and the system picker.
  final HoldApi? api;
  final UploadQueue? queue;
  final DevicePicker? picker;

  @override
  State<HoldSpace> createState() => _HoldSpaceState();
}

class _HoldSpaceState extends State<HoldSpace> {
  HoldApi? _api;
  UploadQueue? _queue;
  late final DevicePicker _picker = widget.picker ?? const SystemDevicePicker();
  String _lastDir = '';
  int _refresh = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_api != null) return;
    _api = widget.api ?? HttpHoldApi(AppScope.of(context).api);
    _queue = widget.queue ?? UploadQueue(_api!, DbUploadStore(AppScope.of(context).db));
    if (widget.queue == null) _queue!.restore();
    _queue!.addListener(_onQueue);
  }

  int _doneSeen = 0;
  void _onQueue() {
    final done = _queue!.jobs.where((j) => j.state == UploadState.done).length;
    if (done != _doneSeen && mounted) {
      _doneSeen = done;
      setState(() => _refresh++); // a finished upload shows up in Browse and Recent
    }
  }

  @override
  void dispose() {
    _queue?.removeListener(_onQueue);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final api = _api!, queue = _queue!;
    return SpaceView(
      space: 'hold',
      searchHint: 'Search files in hold',
      onSearch: (ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => _HoldSearch(api: api, onOpen: (e) => _openEntry(ctx, api, e)))),
      tabs: [
        SpaceTab('Browse', _BrowseTab(key: ValueKey('browse-$_refresh'), api: api, queue: queue, picker: _picker, onDir: (d) => _lastDir = d)),
        SpaceTab('Recent', _RecentTab(key: ValueKey('recent-$_refresh'), api: api, queue: queue)),
        SpaceTab('Device', _DeviceTab(api: api, queue: queue, picker: _picker, destination: () => _lastDir)),
      ],
    );
  }
}

/// Keeps the upload queue in the local database so it outlives the app.
class DbUploadStore implements UploadStore {
  DbUploadStore(this.db);
  final AppDb db;
  static const _key = 'hold.uploads.v1';

  @override
  Future<String?> read() async {
    try {
      final v = (await db.getSnapshot(_key))?.$1;
      return v is Map ? v['jobs'] as String? : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String json) async {
    try {
      await db.putSnapshot(_key, {'jobs': json});
    } catch (_) {}
  }
}

// ── shared bits ─────────────────────────────────────────────────────────────

IconData _iconFor(HoldEntry e) => switch (e.kind) {
      'folder' => Icons.folder_rounded,
      'image' => Icons.image_rounded,
      'pdf' => Icons.picture_as_pdf_rounded,
      'audio' => Icons.audiotrack_rounded,
      'video' => Icons.movie_rounded,
      'text' => Icons.description_rounded,
      'office' => Icons.article_rounded,
      _ => Icons.insert_drive_file_rounded,
    };

String _meta(HoldEntry e) {
  final parts = <String>[
    if (!e.isFolder) fmt.bytesLabel(e.size),
    if (e.modified != null) fmt.ago(e.modified!.millisecondsSinceEpoch ~/ 1000),
  ];
  return parts.join(' · ');
}

void _toast(BuildContext c, String m, {String? action, VoidCallback? onAction}) {
  ScaffoldMessenger.maybeOf(c)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m), action: action == null ? null : SnackBarAction(label: action, onPressed: onAction ?? () {})));
}

String _join(String dir, String name) => dir.isEmpty ? name : '$dir/$name';

Future<String?> _askText(BuildContext context, String title, {String initial = '', String label = 'Name'}) async {
  final c = TextEditingController(text: initial);
  final r = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(key: const Key('hold-name-field'), controller: c, autofocus: true, decoration: InputDecoration(labelText: label), onSubmitted: (v) => Navigator.pop(ctx, v)),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), TextButton(key: const Key('hold-name-ok'), onPressed: () => Navigator.pop(ctx, c.text), child: const Text('OK'))],
    ),
  );
  final v = r?.trim();
  return v == null || v.isEmpty ? null : v;
}

/// A small folder chooser: walks hold's folders and returns the one picked ('' is the root).
Future<String?> pickHoldFolder(BuildContext context, HoldApi api, {String start = '', String title = 'Choose a folder'}) {
  return showDialog<String>(context: context, builder: (ctx) => _FolderPicker(api: api, start: start, title: title));
}

class _FolderPicker extends StatefulWidget {
  const _FolderPicker({required this.api, required this.start, required this.title});
  final HoldApi api;
  final String start, title;
  @override
  State<_FolderPicker> createState() => _FolderPickerState();
}

class _FolderPickerState extends State<_FolderPicker> {
  late String _path = widget.start;
  List<HoldEntry>? _folders;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _folders = null;
      _error = null;
    });
    try {
      final p = await widget.api.list(_path, limit: 200);
      if (mounted) setState(() => _folders = [for (final e in p.items) if (e.isFolder) e]);
    } on HoldException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        height: 320,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(_path.isEmpty ? 'hold' : 'hold / ${_path.replaceAll('/', ' / ')}', style: T.small.copyWith(color: C.text3)),
          const SizedBox(height: 6),
          Expanded(
            child: _error != null
                ? ErrorRetry(_error!, onRetry: _load)
                : _folders == null
                    ? const Center(child: MiniSpinner())
                    : ListView(children: [
                        if (_path.isNotEmpty)
                          ListTile(dense: true, leading: const Icon(Icons.arrow_upward_rounded), title: const Text('Up'), onTap: () {
                            _path = _path.contains('/') ? _path.substring(0, _path.lastIndexOf('/')) : '';
                            _load();
                          }),
                        for (final f in _folders!)
                          ListTile(dense: true, key: Key('pick-${f.name}'), leading: const Icon(Icons.folder_rounded), title: Text(f.name), onTap: () {
                            _path = f.path;
                            _load();
                          }),
                        if (_folders!.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('No folders here.')),
                      ]),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(key: const Key('pick-here'), onPressed: () => Navigator.pop(context, _path), child: const Text('Use this folder')),
      ],
    );
  }
}

// ── actions on one entry ───────────────────────────────────────────────────

Future<void> _openEntry(BuildContext context, HoldApi api, HoldEntry e) async {
  await showFormSheet<void>(context, title: e.name, builder: (ctx) => _PreviewBody(api: api, entry: e));
}

class _PreviewBody extends StatefulWidget {
  const _PreviewBody({required this.api, required this.entry});
  final HoldApi api;
  final HoldEntry entry;
  @override
  State<_PreviewBody> createState() => _PreviewBodyState();
}

class _PreviewBodyState extends State<_PreviewBody> {
  Uint8List? _bytes;
  String? _error;

  @override
  void initState() {
    super.initState();
    final k = widget.entry.kind;
    if ((k == 'image' && widget.entry.size <= 12 * 1024 * 1024) || k == 'text') {
      widget.api.read(widget.entry.path, length: k == 'text' ? 64 * 1024 : null).then((b) {
        if (mounted) setState(() => _bytes = b);
      }, onError: (Object e) {
        if (mounted) setState(() => _error = '$e');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    Widget preview;
    if (_error != null) {
      preview = ErrorRetry(_error!);
    } else if (e.kind == 'image' && _bytes != null) {
      preview = ClipRRect(borderRadius: BorderRadius.circular(Sz.rMd), child: Image.memory(_bytes!, key: const Key('hold-preview-image'), fit: BoxFit.contain, height: 260));
    } else if (e.kind == 'text' && _bytes != null) {
      preview = Panel(child: Text(utf8.decode(_bytes!, allowMalformed: true), key: const Key('hold-preview-text'), style: T.small, maxLines: 14, overflow: TextOverflow.ellipsis));
    } else if (e.kind == 'image' || e.kind == 'text') {
      preview = const Padding(padding: EdgeInsets.all(24), child: Center(child: MiniSpinner()));
    } else {
      preview = EmptyState('No inline preview', 'Download ${e.name} to the device to open it in its own app.', icon: _iconFor(e));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      preview,
      const SizedBox(height: 12),
      KvRow('Size', fmt.bytesLabel(e.size)),
      KvRow('Changed', e.modified == null ? 'unknown' : fmt.fullDate(e.modified!)),
      KvRow('Path', e.path),
    ]);
  }
}

Future<void> _entryActions(BuildContext context, HoldApi api, UploadQueue queue, DevicePicker picker, HoldEntry e, VoidCallback changed) async {
  await showFormSheet<void>(
    context,
    title: fmt.truncate(e.name, 60),
    builder: (ctx) {
      Widget tile(IconData i, String t, Future<void> Function() go, {Key? key}) => ListTile(
            key: key,
            dense: true,
            leading: Icon(i, size: 20),
            title: Text(t),
            onTap: () async {
              Navigator.pop(ctx);
              await go();
            },
          );
      Future<void> guarded(Future<void> Function() f) async {
        try {
          await f();
          changed();
        } on HoldException catch (x) {
          if (context.mounted) _toast(context, x.message);
        }
      }

      return Column(children: [
        tile(Icons.visibility_rounded, 'Open', () => e.isFolder ? Future.value() : _openEntry(context, api, e), key: const Key('act-open')),
        tile(Icons.drive_file_rename_outline_rounded, 'Rename', () async {
          final n = await _askText(context, 'Rename', initial: e.name);
          if (n != null && n != e.name) await guarded(() => api.rename(e.path, n));
        }, key: const Key('act-rename')),
        tile(Icons.drive_file_move_rounded, 'Move to…', () async {
          final d = await pickHoldFolder(context, api, start: e.parent, title: 'Move to');
          if (d != null) await guarded(() => api.move(e.path, d));
        }, key: const Key('act-move')),
        if (!e.isFolder)
          tile(Icons.copy_rounded, 'Copy to…', () async {
            final d = await pickHoldFolder(context, api, start: e.parent, title: 'Copy to');
            if (d != null) await guarded(() => api.copy(e.path, d));
          }, key: const Key('act-copy')),
        tile(Icons.link_rounded, 'Share link (24 h)', () async {
          try {
            final s = await api.share(e.path);
            if (context.mounted) _toast(context, 'Link expires ${fmt.fullDate(s.expires)}: ${s.url}');
          } on HoldException catch (x) {
            if (context.mounted) _toast(context, x.message);
          }
        }, key: const Key('act-share')),
        if (!e.isFolder)
          tile(Icons.download_rounded, 'Download to device', () async {
            try {
              final b = await api.read(e.path);
              final ok = await picker.save(e.name, b);
              if (context.mounted) _toast(context, ok ? 'Saved ${e.name} to the device.' : 'This device cannot save files from here.');
            } on HoldException catch (x) {
              if (context.mounted) _toast(context, x.message);
            }
          }, key: const Key('act-download')),
        tile(Icons.delete_outline_rounded, 'Delete (to trash)', () => _deleteWithUndo(context, api, [e], changed), key: const Key('act-delete')),
      ]);
    },
  );
}

Future<void> _deleteWithUndo(BuildContext context, HoldApi api, List<HoldEntry> items, VoidCallback changed) async {
  try {
    for (final e in items) {
      await api.delete(e.path);
    }
  } on HoldException catch (x) {
    if (context.mounted) _toast(context, x.message);
    return;
  }
  changed();
  if (!context.mounted) return;
  _toast(context, items.length == 1 ? 'Moved "${items.first.name}" to the trash.' : 'Moved ${items.length} items to the trash.', action: 'Undo', onAction: () async {
    for (final e in items) {
      try {
        await api.restore(e.path);
      } on HoldException catch (_) {}
    }
    changed();
  });
}

// ── Browse ─────────────────────────────────────────────────────────────────

class _BrowseTab extends StatefulWidget {
  const _BrowseTab({super.key, required this.api, required this.queue, required this.picker, required this.onDir});
  final HoldApi api;
  final UploadQueue queue;
  final DevicePicker picker;
  final void Function(String) onDir;
  @override
  State<_BrowseTab> createState() => _BrowseTabState();
}

class _BrowseTabState extends State<_BrowseTab> {
  String _path = '';
  List<HoldEntry> _items = [];
  String? _next, _error;
  bool _loading = true, _grid = false, _desc = false;
  HoldSort _sort = HoldSort.name;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    setState(() {
      _loading = true;
      if (!more) _error = null;
    });
    try {
      final p = await widget.api.list(_path, sort: _sort, descending: _desc, cursor: more ? _next : null);
      if (!mounted) return;
      setState(() {
        _items = more ? [..._items, ...p.items] : p.items;
        _next = p.next;
        _loading = false;
      });
    } on HoldException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }
    widget.onDir(_path);
  }

  void _cd(String path) {
    _selected.clear();
    _path = path;
    _load();
  }

  Future<void> _upload() async {
    final picked = await widget.picker.pick();
    if (picked.isEmpty) return;
    final taken = {for (final e in _items) e.name};
    for (final f in picked) {
      final job = widget.queue.add(_path, f.name, f.source, taken: taken);
      taken.add(job.name);
    }
    if (mounted) _toast(context, 'Uploading ${fmt.plural(picked.length, "file")}. Progress is on the Recent tab.');
  }

  Future<void> _newFolder() async {
    final n = await _askText(context, 'New folder');
    if (n == null) return;
    try {
      await widget.api.mkdir(_join(_path, n));
      await _load();
    } on HoldException catch (e) {
      if (mounted) _toast(context, e.message);
    }
  }

  Future<void> _bulk(String verb) async {
    final chosen = [for (final e in _items) if (_selected.contains(e.path)) e];
    if (chosen.isEmpty) return;
    if (verb == 'delete') {
      await _deleteWithUndo(context, widget.api, chosen, _load);
    } else {
      final d = await pickHoldFolder(context, widget.api, start: _path, title: verb == 'move' ? 'Move to' : 'Copy to');
      if (d == null) return;
      try {
        for (final e in chosen) {
          verb == 'move' ? await widget.api.move(e.path, d) : await widget.api.copy(e.path, d);
        }
      } on HoldException catch (x) {
        if (mounted) _toast(context, x.message);
      }
    }
    _selected.clear();
    await _load();
  }

  void _tap(HoldEntry e) {
    if (_selected.isNotEmpty) {
      setState(() => _selected.contains(e.path) ? _selected.remove(e.path) : _selected.add(e.path));
    } else if (e.isFolder) {
      _cd(e.path);
    } else {
      _openEntry(context, widget.api, e);
    }
  }

  void _long(HoldEntry e) => setState(() => _selected.contains(e.path) ? _selected.remove(e.path) : _selected.add(e.path));

  @override
  Widget build(BuildContext context) {
    final crumbs = _path.isEmpty ? <String>[] : _path.split('/');
    return PopScope(
      canPop: _path.isEmpty && _selected.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_selected.isNotEmpty) {
          setState(_selected.clear);
        } else {
          _cd(_path.contains('/') ? _path.substring(0, _path.lastIndexOf('/')) : '');
        }
      },
      child: Stack(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _crumbs(crumbs),
          _toolbar(),
          if (_path.split('/').contains('_unsorted') && _items.any((e) => !e.isFolder)) _tidyBanner(),
          Expanded(child: _body()),
        ]),
        Positioned(
          right: 16,
          bottom: 16,
          child: FabStack(
            primary: FabAction(heroTag: 'hold-upload', tooltip: 'Upload from this device', icon: Icons.upload_rounded, onPressed: _upload),
            secondary: [FabAction(heroTag: 'hold-folder', tooltip: 'New folder', icon: Icons.create_new_folder_rounded, onPressed: _newFolder)],
          ),
        ),
      ]),
    );
  }

  Widget _crumbs(List<String> crumbs) => SingleChildScrollView(
        key: const Key('hold-crumbs'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
        child: Row(children: [
          TextButton(key: const Key('crumb-root'), onPressed: () => _cd(''), child: const Text('hold')),
          for (var i = 0; i < crumbs.length; i++) ...[
            const Icon(Icons.chevron_right_rounded, size: 16, color: C.text3),
            TextButton(onPressed: () => _cd(crumbs.sublist(0, i + 1).join('/')), child: Text(crumbs[i])),
          ],
        ]),
      );

  Widget _toolbar() {
    if (_selected.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(children: [
          Text('${_selected.length} selected', style: T.w600(T.body2)),
          const Spacer(),
          IconButton(key: const Key('bulk-move'), tooltip: 'Move', icon: const Icon(Icons.drive_file_move_rounded), onPressed: () => _bulk('move')),
          IconButton(key: const Key('bulk-copy'), tooltip: 'Copy', icon: const Icon(Icons.copy_rounded), onPressed: () => _bulk('copy')),
          IconButton(key: const Key('bulk-delete'), tooltip: 'Delete', icon: const Icon(Icons.delete_outline_rounded), onPressed: () => _bulk('delete')),
          IconButton(tooltip: 'Clear selection', icon: const Icon(Icons.close_rounded), onPressed: () => setState(_selected.clear)),
        ]),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(children: [
        PopupMenuButton<HoldSort>(
          key: const Key('hold-sort'),
          tooltip: 'Sort',
          initialValue: _sort,
          onSelected: (s) {
            _sort = s;
            _load();
          },
          child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(children: [const Icon(Icons.sort_rounded, size: 18, color: C.text3), const SizedBox(width: 6), Text('Sort: ${_sort.name}', style: T.small.copyWith(color: C.text3))])),
          itemBuilder: (_) => [for (final s in HoldSort.values) PopupMenuItem(value: s, child: Text(s.name))],
        ),
        IconButton(key: const Key('hold-dir'), tooltip: _desc ? 'Descending' : 'Ascending', icon: Icon(_desc ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded, size: 18), onPressed: () {
          _desc = !_desc;
          _load();
        }),
        const Spacer(),
        IconButton(key: const Key('hold-view'), tooltip: _grid ? 'List view' : 'Grid view', icon: Icon(_grid ? Icons.view_list_rounded : Icons.grid_view_rounded, size: 20), onPressed: () => setState(() => _grid = !_grid)),
      ]),
    );
  }

  Widget _tidyBanner() {
    final n = _items.where((e) => suggestSort(e) != null).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
      child: Panel(
        key: const Key('hold-tidy'),
        onTap: () => _tidy(),
        child: Row(children: [
          const Icon(Icons.auto_fix_high_rounded, size: 18, color: C.green),
          const SizedBox(width: 10),
          Expanded(child: Text('Tidy $n unsorted ${n == 1 ? "file" : "files"}: suggested names and folders, nothing moves until you accept.', style: T.small)),
        ]),
      ),
    );
  }

  Future<void> _tidy() async {
    final sugg = [for (final e in _items) if (suggestSort(e) != null) suggestSort(e)!];
    await showFormSheet<void>(
      context,
      title: 'Tidy unsorted files',
      builder: (ctx) => _TidySheet(api: widget.api, suggestions: sugg, onChanged: _load),
    );
  }

  Widget _body() {
    if (_error != null && _items.isEmpty) return ErrorRetry(_error!, onRetry: _load);
    if (_loading && _items.isEmpty) return const Center(child: MiniSpinner());
    if (_items.isEmpty) {
      return const EmptyState('Nothing here yet', 'Upload from this device, or make a folder with the buttons below.', icon: Icons.folder_open_rounded);
    }
    final more = _next == null
        ? null
        : Padding(padding: const EdgeInsets.all(8), child: TextButton(key: const Key('hold-more'), onPressed: () => _load(more: true), child: const Text('Load more')));
    final archive = Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
      child: TextButton.icon(
        key: const Key('hold-archive'),
        icon: const Icon(Icons.inventory_2_outlined, size: 18),
        label: const Text('Archive (OneDrive, read-only)'),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: const Text('Archive (OneDrive, read-only)')), body: const FilesView()))),
      ),
    );
    Widget cell(HoldEntry e) {
      final sel = _selected.contains(e.path);
      return _grid
          ? InkWell(
              key: Key('entry-${e.name}'),
              onTap: () => _tap(e),
              onLongPress: () => _long(e),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: sel ? C.greenBg : C.panel, border: Border.all(color: sel ? C.green : C.border), borderRadius: BorderRadius.circular(Sz.rMd)),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(_iconFor(e), size: 32, color: e.isFolder ? C.green : C.text2),
                  const SizedBox(height: 6),
                  Text(e.name, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: T.small),
                ]),
              ),
            )
          : Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Panel(
                key: Key('entry-${e.name}'),
                color: sel ? C.greenBg : C.panel,
                onTap: () => _tap(e),
                child: GestureDetector(
                  onLongPress: () => _long(e),
                  behavior: HitTestBehavior.opaque,
                  child: Row(children: [
                    Icon(sel ? Icons.check_circle_rounded : _iconFor(e), size: 22, color: sel || e.isFolder ? C.green : C.text2),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(e.name, style: T.w600(T.body2), maxLines: 1, overflow: TextOverflow.ellipsis), if (_meta(e).isNotEmpty) Text(_meta(e), style: T.small.copyWith(color: C.text3))])),
                    IconButton(key: Key('more-${e.name}'), tooltip: 'Actions', icon: const Icon(Icons.more_vert_rounded, size: 20), onPressed: () => _entryActions(context, widget.api, widget.queue, widget.picker, e, _load)),
                  ]),
                ),
              ),
            );
    }

    return RefreshIndicator(
      onRefresh: () => _load(),
      child: _grid
          ? GridView.count(key: const Key('hold-browse-list'), padding: const EdgeInsets.fromLTRB(14, 4, 14, 96), crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8, children: [for (final e in _items) cell(e)])
          : ListView(key: const Key('hold-browse-list'), padding: const EdgeInsets.fromLTRB(14, 4, 14, 0), children: [for (final e in _items) cell(e), ?more, archive]),
    );
  }
}

class _TidySheet extends StatefulWidget {
  const _TidySheet({required this.api, required this.suggestions, required this.onChanged});
  final HoldApi api;
  final List<SortSuggestion> suggestions;
  final VoidCallback onChanged;
  @override
  State<_TidySheet> createState() => _TidySheetState();
}

class _TidySheetState extends State<_TidySheet> {
  late final List<SortSuggestion> _left = [...widget.suggestions];
  String? _error;

  Future<void> _ensureFolder(String folder) async {
    final parts = folder.split('/');
    for (var i = 1; i <= parts.length; i++) {
      try {
        await widget.api.mkdir(parts.sublist(0, i).join('/'));
      } on HoldException catch (_) {
        // already there
      }
    }
  }

  Future<void> _accept(SortSuggestion s, {String? name, String? folder}) async {
    final f = folder ?? s.folder, n = name ?? s.name;
    try {
      await _ensureFolder(f);
      final taken = {for (final e in (await widget.api.list(f, limit: 500)).items) e.name};
      final finalName = conflictFreeName(n, taken);
      await widget.api.rename(s.entry.path, finalName.isEmpty ? n : finalName);
      await widget.api.move(_join(s.entry.parent, finalName), f);
      if (mounted) setState(() => _left.remove(s));
      widget.onChanged();
    } on HoldException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _edit(SortSuggestion s) async {
    final n = await _askText(context, 'Name', initial: s.name);
    if (n == null || !mounted) return;
    final f = await pickHoldFolder(context, widget.api, start: s.folder, title: 'Folder');
    if (f == null) return;
    await _accept(s, name: n, folder: f);
  }

  @override
  Widget build(BuildContext context) {
    if (_left.isEmpty) return const EmptyState('All tidy', 'Every suggestion was handled.', icon: Icons.check_circle_outline_rounded);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_error != null) ErrorRetry(_error!),
      for (final s in _left)
        Panel(
          key: Key('tidy-${s.entry.name}'),
          margin: const EdgeInsets.only(bottom: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.entry.name, style: T.small.copyWith(color: C.text3)),
            Text('→ ${s.folder}/${s.name}', style: T.w600(T.body2)),
            Row(children: [
              TextButton(key: Key('tidy-accept-${s.entry.name}'), onPressed: () => _accept(s), child: const Text('Accept')),
              TextButton(onPressed: () => _edit(s), child: const Text('Edit')),
              TextButton(onPressed: () => setState(() => _left.remove(s)), child: const Text('Skip')),
            ]),
          ]),
        ),
      FilledButton(
        key: const Key('tidy-all'),
        onPressed: () async {
          for (final s in [..._left]) {
            await _accept(s);
          }
        },
        child: Text('Accept all ${_left.length}'),
      ),
    ]);
  }
}

// ── Recent ─────────────────────────────────────────────────────────────────

class _RecentTab extends StatefulWidget {
  const _RecentTab({super.key, required this.api, required this.queue});
  final HoldApi api;
  final UploadQueue queue;
  @override
  State<_RecentTab> createState() => _RecentTabState();
}

class _RecentTabState extends State<_RecentTab> {
  List<HoldEntry>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.queue.addListener(_tick);
    _load();
  }

  @override
  void dispose() {
    widget.queue.removeListener(_tick);
    super.dispose();
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    try {
      final r = await widget.api.recent();
      if (mounted) {
        setState(() {
          _items = r;
          _error = null;
        });
      }
    } on HoldException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final jobs = widget.queue.jobs.where((j) => j.state != UploadState.done).toList();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(key: const Key('hold-recent-list'), padding: const EdgeInsets.fromLTRB(14, 8, 14, 96), children: [
        if (jobs.isNotEmpty) ...[
          const SectionLabel('Uploads'),
          for (final j in jobs) _jobTile(j),
        ],
        const SectionLabel('Recent files'),
        if (_error != null)
          ErrorRetry(_error!, onRetry: _load)
        else if (_items == null)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: MiniSpinner()))
        else if (_items!.isEmpty)
          const EmptyState('Nothing recent', 'Files you add, open or change show up here.', icon: Icons.history_rounded)
        else
          for (final e in _items!)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Panel(
                key: Key('recent-${e.name}'),
                onTap: () => _openEntry(context, widget.api, e),
                child: Row(children: [
                  Icon(_iconFor(e), size: 22, color: C.text2),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(e.name, style: T.w600(T.body2), maxLines: 1, overflow: TextOverflow.ellipsis), Text('${e.parent.isEmpty ? "hold" : e.parent} · ${_meta(e)}', style: T.small.copyWith(color: C.text3), maxLines: 1, overflow: TextOverflow.ellipsis)])),
                ]),
              ),
            ),
      ]),
    );
  }

  Widget _jobTile(UploadJob j) {
    final failed = j.state == UploadState.failed;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Panel(
        key: Key('job-${j.name}'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(j.name, style: T.w600(T.body2), maxLines: 1, overflow: TextOverflow.ellipsis)),
            Text(switch (j.state) { UploadState.queued => 'Queued', UploadState.running => '${(j.progress * 100).round()}%', UploadState.waiting => 'Retrying…', UploadState.failed => 'Failed', UploadState.done => 'Done' }, style: T.small.copyWith(color: failed ? C.red : C.text3)),
            if (failed) TextButton(key: Key('retry-${j.name}'), onPressed: () => widget.queue.retry(j), child: const Text('Retry')),
          ]),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: j.progress.clamp(0, 1).toDouble(), color: failed ? C.red : C.green, backgroundColor: C.border),
          if (j.error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(j.error, style: T.small.copyWith(color: C.text3))),
        ]),
      ),
    );
  }
}

// ── Device ─────────────────────────────────────────────────────────────────

class _DeviceTab extends StatefulWidget {
  const _DeviceTab({required this.api, required this.queue, required this.picker, required this.destination});
  final HoldApi api;
  final UploadQueue queue;
  final DevicePicker picker;
  final String Function() destination;
  @override
  State<_DeviceTab> createState() => _DeviceTabState();
}

class _DeviceTabState extends State<_DeviceTab> {
  String? _dest;
  String get dest => _dest ?? widget.destination();

  Future<void> _toHold() async {
    final picked = await widget.picker.pick();
    if (picked.isEmpty) return;
    Set<String> taken = {};
    try {
      taken = {for (final e in (await widget.api.list(dest, limit: 500)).items) e.name};
    } on HoldException catch (_) {}
    for (final f in picked) {
      final j = widget.queue.add(dest, f.name, f.source, taken: taken);
      taken.add(j.name);
    }
    if (mounted) _toast(context, 'Uploading ${fmt.plural(picked.length, "file")} to ${dest.isEmpty ? "hold" : dest}.');
  }

  Future<void> _fromHold() async {
    final recent = await widget.api.recent(limit: 200).catchError((_) => <HoldEntry>[]);
    if (!mounted) return;
    final chosen = await showDialog<HoldEntry>(
      context: context,
      builder: (ctx) => SimpleDialog(title: const Text('Save to this device'), children: [
        for (final e in recent.take(30)) SimpleDialogOption(key: Key('dl-${e.name}'), onPressed: () => Navigator.pop(ctx, e), child: Text(e.name)),
        if (recent.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No files yet. Browse hold and use Download to device on a file.')),
      ]),
    );
    if (chosen == null) return;
    try {
      final bytes = await widget.api.read(chosen.path);
      final ok = await widget.picker.save(chosen.name, bytes);
      if (mounted) _toast(context, ok ? 'Saved ${chosen.name} to the device.' : 'This device cannot save files from here.');
    } on HoldException catch (e) {
      if (mounted) _toast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(key: const Key('hold-device'), padding: const EdgeInsets.fromLTRB(14, 12, 14, 96), children: [
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('This device', style: T.w600(T.body2)),
          const SizedBox(height: 4),
          Text('Choose files from the device\'s own storage and copy them into hold, or save a hold file back to the device. Nothing leaves hold without you choosing it.', style: T.small.copyWith(color: C.text3)),
        ]),
      ),
      const SizedBox(height: 12),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Into: ${dest.isEmpty ? "hold (top level)" : dest}', key: const Key('device-dest'), style: T.small)),
            TextButton(key: const Key('device-change'), onPressed: () async {
              final d = await pickHoldFolder(context, widget.api, start: dest, title: 'Upload into');
              if (d != null) setState(() => _dest = d);
            }, child: const Text('Change')),
          ]),
          const SizedBox(height: 4),
          FilledButton.icon(key: const Key('device-upload'), icon: const Icon(Icons.upload_file_rounded), label: const Text('Choose files from this device'), onPressed: _toHold),
        ]),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(key: const Key('device-download'), icon: const Icon(Icons.download_rounded), label: const Text('Save a hold file to this device'), onPressed: _fromHold),
    ]);
  }
}

// ── Search ─────────────────────────────────────────────────────────────────

class _HoldSearch extends StatefulWidget {
  const _HoldSearch({required this.api, required this.onOpen});
  final HoldApi api;
  final void Function(HoldEntry) onOpen;
  @override
  State<_HoldSearch> createState() => _HoldSearchState();
}

class _HoldSearchState extends State<_HoldSearch> {
  final _field = TextEditingController();
  Timer? _debounce;
  List<HoldEntry> _hits = [];
  String _q = '';
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _field.dispose();
    super.dispose();
  }

  void _changed(String v) {
    _q = v.trim();
    _debounce?.cancel();
    if (_q.isEmpty) {
      setState(() => _hits = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        final r = await widget.api.search(_q);
        if (mounted && _q == v.trim()) {
          setState(() {
            _hits = r;
            _error = null;
          });
        }
      } on HoldException catch (e) {
        if (mounted) setState(() => _error = e.message);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: TextField(key: const Key('space-search-field'), controller: _field, autofocus: true, decoration: const InputDecoration(hintText: 'Search files in hold', border: InputBorder.none), style: T.body, onChanged: _changed)),
      body: _error != null
          ? ErrorRetry(_error!)
          : _q.isEmpty
              ? const EmptyState('Search', 'Type part of a file or folder name.', icon: Icons.search_rounded)
              : _hits.isEmpty
                  ? EmptyState('No matches', 'Nothing in hold matches "$_q".', icon: Icons.search_off_rounded)
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
                      itemCount: _hits.length,
                      itemBuilder: (ctx, i) => ListTile(
                        key: Key('space-hit-$i'),
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(_iconFor(_hits[i])),
                        title: Text(_hits[i].name, style: T.w600(T.body2)),
                        subtitle: Text(_hits[i].parent.isEmpty ? 'hold' : _hits[i].parent, style: T.small.copyWith(color: C.text3), maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () => widget.onOpen(_hits[i]),
                      ),
                    ),
    );
  }
}
