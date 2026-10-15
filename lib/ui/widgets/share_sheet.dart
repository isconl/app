import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../app_scope.dart';
import '../../services/platform.dart' show SharedFile;
import '../../services/share_intake.dart';
import '../../theme.dart';

/// Saves through the app's own outbox: works offline, syncs later.
class AppShareSink implements ShareSink {
  AppShareSink(this.services);
  final AppServices services;

  @override
  Future<bool> addInbox({required String body, String title = ''}) async =>
      (await services.mutations.addInbox(body: body, title: title, channel: 'mobile', sender: 'share-sheet')).ok;

  @override
  Future<bool> addTask({required String title}) async => (await services.mutations.addTask(title: title)).ok;

  @override
  Future<bool> addJournal({required String body}) async => (await services.mutations.addJournal(body: body)).ok;

  @override
  Future<String> keepFile(SharedFile f) async {
    final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'shared'));
    if (!await dir.exists()) await dir.create(recursive: true);
    final out = p.join(dir.path, p.basename(f.path));
    await File(f.path).copy(out);
    return out;
  }
}

/// The compact sheet that opens when something is shared into the app: what was shared, four destinations (Inbox
/// first), an optional note, and Save. Nothing is saved until Save is tapped.
Future<void> showShareSheet(BuildContext context, ShareItem item, {ShareSink? sink}) {
  final s = sink ?? AppShareSink(AppScope.of(context));
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ShareSheet(item: item, sink: s),
    ),
  );
}

class ShareSheet extends StatefulWidget {
  const ShareSheet({super.key, required this.item, required this.sink, this.onDone});
  final ShareItem item;
  final ShareSink sink;

  /// Called after a successful save; by default the sheet closes itself.
  final VoidCallback? onDone;

  @override
  State<ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<ShareSheet> {
  ShareDestination _dest = ShareDestination.inbox;
  final _note = TextEditingController();
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    final r = await saveShare(widget.sink, widget.item, _dest, _note.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = r.message;
    });
    if (r.ok) {
      widget.onDone?.call();
      if (widget.onDone == null) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(r.message)));
        Navigator.of(context).maybePop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Save to iSconl', style: T.title),
          const SizedBox(height: 8),
          Container(
            key: const Key('share-preview'),
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(border: Border.all(color: C.border), borderRadius: BorderRadius.circular(Sz.rMd)),
            child: Row(children: [
              Icon(item.hasFiles ? (item.files.first.isImage ? Icons.image_outlined : Icons.picture_as_pdf_outlined) : (item.link != null ? Icons.link : Icons.notes), size: 20, color: C.text2),
              const SizedBox(width: 8),
              Expanded(child: Text(item.preview, maxLines: 3, overflow: TextOverflow.ellipsis, style: T.body2)),
            ]),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, children: [
            for (final d in destinationsFor(item))
              ChoiceChip(key: Key('dest-${d.name}'), label: Text(d.label), selected: _dest == d, onSelected: (_) => setState(() => _dest = d)),
          ]),
          const SizedBox(height: 10),
          TextField(
            key: const Key('share-note'),
            controller: _note,
            minLines: 1,
            maxLines: 4,
            decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'A note (optional)'),
          ),
          if (_message != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_message!, key: const Key('share-message'), style: T.small)),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: _busy ? null : () => Navigator.of(context).maybePop(), child: const Text('Cancel')),
            const SizedBox(width: 8),
            FilledButton(key: const Key('share-save'), onPressed: _busy ? null : _save, child: const Text('Save')),
          ]),
        ]),
      ),
    );
  }
}

/// BI26100138: the capture sheet the widget's Capture button and the Capture icon shortcut open: one box, saved to
/// the inbox through the outbox (so it works offline), nothing else to choose.
Future<void> showQuickCapture(BuildContext context, {ShareSink? sink}) {
  final s = sink ?? AppShareSink(AppScope.of(context));
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: QuickCapture(sink: s),
    ),
  );
}

class QuickCapture extends StatefulWidget {
  const QuickCapture({super.key, required this.sink, this.onDone});
  final ShareSink sink;
  final VoidCallback? onDone;

  @override
  State<QuickCapture> createState() => _QuickCaptureState();
}

class _QuickCaptureState extends State<QuickCapture> {
  final _text = TextEditingController();
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final body = _text.text.trim();
    if (body.isEmpty) {
      setState(() => _message = 'Write something first.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    final ok = await widget.sink.addInbox(body: body);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = ok ? 'Saved to Inbox.' : 'Could not save it. Try again.';
    });
    if (ok) {
      widget.onDone?.call();
      if (widget.onDone == null) Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Capture', style: T.title),
            const SizedBox(height: 8),
            TextField(
              key: const Key('capture-text'),
              controller: _text,
              autofocus: true,
              minLines: 3,
              maxLines: 8,
              decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'What is on your mind?'),
            ),
            if (_message != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_message!, key: const Key('capture-message'), style: T.small)),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: _busy ? null : () => Navigator.of(context).maybePop(), child: const Text('Cancel')),
              const SizedBox(width: 8),
              FilledButton(key: const Key('capture-save'), onPressed: _busy ? null : _save, child: const Text('Save')),
            ]),
          ]),
        ),
      );
}
