import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../services/small_actions.dart';
import '../../theme.dart';
import '../views/learning_export_stub.dart' if (dart.library.io) '../views/learning_export_native.dart' as export_impl;

String _err(Object e) => '$e'.replaceFirst('ApiException(0): ', '').replaceFirst('Exception: ', '');

Future<String?> _ask(BuildContext context, String title, String label, {String value = '', String hint = ''}) {
  final ctl = TextEditingController(text: value);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(key: const Key('ask-text'), controller: ctl, autofocus: true, decoration: InputDecoration(labelText: label, helperText: hint.isEmpty ? null : hint)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(key: const Key('ask-ok'), onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('OK')),
      ],
    ),
  );
}

/// BI26100512: rename, move, download and delete for one OneDrive item (a file or a folder). Delete asks first and
/// says it goes to the recycle bin; nothing here is a hard delete. These need the live hub.
class FileActions extends StatefulWidget {
  const FileActions({super.key, required this.itemId, required this.name, this.isFolder = false, this.api, this.onChanged});
  final String itemId;
  final String name;
  final bool isFolder;
  final SmallActionsApi? api;

  /// After a change that moves or removes the item, so the listing reloads.
  final VoidCallback? onChanged;

  @override
  State<FileActions> createState() => _FileActionsState();
}

class _FileActionsState extends State<FileActions> {
  SmallActionsApi get _api => widget.api ?? HubSmallActionsApi(AppScope.of(context).api);
  bool _busy = false;
  String? _message;

  Future<void> _run(Future<String?> Function() job) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final m = await job();
      if (mounted && m != null) setState(() => _message = m);
    } catch (e) {
      if (mounted) setState(() => _message = _err(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rename() async {
    final n = await _ask(context, 'Rename', 'New name', value: widget.name);
    if (n == null || n.isEmpty || n == widget.name) return;
    await _run(() async {
      await _api.rename(widget.itemId, n);
      widget.onChanged?.call();
      return 'Renamed to $n.';
    });
  }

  Future<void> _move() async {
    final to = await _ask(context, 'Move "${widget.name}"', 'Destination folder', hint: 'A OneDrive path such as Circle/Social/jane. Leave blank or type root for the top.');
    if (to == null) return;
    await _run(() async {
      await _api.move(widget.itemId, to);
      widget.onChanged?.call();
      return 'Moved to ${to.isEmpty ? 'root' : to}.';
    });
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Delete "${widget.name}"?'),
            content: Text(widget.isFolder ? 'The folder and everything in it go to the OneDrive recycle bin, where it can be restored.' : 'It goes to the OneDrive recycle bin, where it can be restored.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(style: FilledButton.styleFrom(backgroundColor: C.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
            ],
          ),
        ) ==
        true;
    if (!ok) return;
    await _run(() async {
      await _api.deleteItem(widget.itemId);
      widget.onChanged?.call();
      return 'Deleted. It is in the recycle bin.';
    });
  }

  Future<void> _download() => _run(() async {
        final f = await _api.download(widget.itemId, widget.name);
        final name = f.filename.isEmpty ? widget.name : f.filename;
        final ok = await export_impl.saveAndOpenExport(name, f.bytes, mime: 'application/octet-stream');
        return ok ? null : 'Saved, but nothing on this device opens that file.';
      });

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (!widget.isFolder) OutlinedButton(key: const Key('file-download'), onPressed: _busy ? null : _download, child: const Text('Download')),
          OutlinedButton(key: const Key('file-rename'), onPressed: _busy ? null : _rename, child: const Text('Rename')),
          OutlinedButton(key: const Key('file-move'), onPressed: _busy ? null : _move, child: const Text('Move')),
          OutlinedButton(key: const Key('file-delete'), onPressed: _busy ? null : _delete, child: Text('Delete', style: TextStyle(color: C.red))),
        ]),
        if (_message != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_message!, key: const Key('file-message'), style: T.small)),
      ]);
}

/// New folder and upload (a text file) into the folder being viewed.
class FolderToolbar extends StatefulWidget {
  const FolderToolbar({super.key, required this.path, this.api, this.onChanged});
  final String path;
  final SmallActionsApi? api;
  final VoidCallback? onChanged;

  @override
  State<FolderToolbar> createState() => _FolderToolbarState();
}

class _FolderToolbarState extends State<FolderToolbar> {
  SmallActionsApi get _api => widget.api ?? HubSmallActionsApi(AppScope.of(context).api);
  bool _busy = false;
  String? _message;

  Future<void> _mkdir() async {
    final n = await _ask(context, 'New folder', 'Folder name');
    if (n == null || n.isEmpty) return;
    if (HubSmallActionsApi.badName(n)) {
      setState(() => _message = 'A name cannot contain \\ / : * ? " < > |');
      return;
    }
    setState(() => _busy = true);
    try {
      await _api.mkdir(widget.path, n);
      widget.onChanged?.call();
      if (mounted) setState(() => _message = 'Folder created.');
    } catch (e) {
      if (mounted) setState(() => _message = _err(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _upload() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['txt', 'md', 'csv', 'json', 'tsv'], withData: true);
    final f = r?.files.single;
    if (f == null || f.bytes == null) return;
    setState(() {
      _busy = true;
      _message = 'Uploading ${f.name}...';
    });
    try {
      await _api.uploadText(widget.path, f.name, String.fromCharCodes(f.bytes!));
      widget.onChanged?.call();
      if (mounted) setState(() => _message = '${f.name} uploaded.');
    } catch (e) {
      if (mounted) setState(() => _message = 'Upload failed: ${_err(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, children: [
            TextButton.icon(key: const Key('new-folder'), onPressed: _busy ? null : _mkdir, icon: const Icon(Icons.create_new_folder_outlined, size: 16), label: const Text('New folder')),
            TextButton.icon(key: const Key('upload-text'), onPressed: _busy ? null : _upload, icon: const Icon(Icons.upload_file_outlined, size: 16), label: const Text('Upload a text file')),
          ]),
          if (_message != null) Text(_message!, key: const Key('toolbar-message'), style: T.small),
        ]),
      );
}
