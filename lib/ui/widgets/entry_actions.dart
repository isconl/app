import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../services/small_actions.dart';
import '../../theme.dart';
import '../../util/markdown.dart';

String _err(Object e) => '$e'.replaceFirst('ApiException(0): ', '').replaceFirst('Exception: ', '');

/// BI26100512: edit, reflect (or sharpen) and delete for one journal entry or idea, from its detail sheet.
/// These need the live hub. Delete asks first and says what it does.
class EntryActions extends StatefulWidget {
  const EntryActions({super.key, required this.kind, required this.id, required this.body, this.api, this.onChanged, this.onDeleted});

  /// 'journal' or 'idea'.
  final String kind;
  final String id;
  final String body;
  final SmallActionsApi? api;

  /// After an edit, so the list can reload.
  final VoidCallback? onChanged;
  final VoidCallback? onDeleted;

  @override
  State<EntryActions> createState() => _EntryActionsState();
}

class _EntryActionsState extends State<EntryActions> {
  SmallActionsApi get _api => widget.api ?? HubSmallActionsApi(AppScope.of(context).api);
  bool _busy = false;
  String? _message;
  String? _note;

  bool get _journal => widget.kind == 'journal';

  Future<void> _run(Future<void> Function() job) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await job();
    } catch (e) {
      if (mounted) setState(() => _message = _err(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit() async {
    final ctl = TextEditingController(text: widget.body);
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit the entry'),
        content: TextField(key: const Key('entry-edit-text'), controller: ctl, minLines: 4, maxLines: 12, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(key: const Key('entry-edit-save'), onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('Save changes')),
        ],
      ),
    );
    // The controller is not disposed here: the dialog is still animating closed and reads it until it is gone.
    if (text == null || text.isEmpty || text == widget.body.trim()) return;
    await _run(() async {
      await _api.journalUpdate(widget.id, text);
      widget.onChanged?.call();
      if (mounted) setState(() => _message = 'Entry updated.');
    });
  }

  Future<void> _reflect() => _run(() async {
        final note = _journal ? await _api.journalReflect(widget.id) : await _api.ideaRefine(widget.id);
        if (mounted) setState(() => _note = note);
      });

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(_journal ? 'Delete this entry?' : 'Delete this idea?'),
            content: Text(_journal ? 'It leaves the journal. The vault history still holds its past.' : 'It leaves the pipeline.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(style: FilledButton.styleFrom(backgroundColor: C.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
            ],
          ),
        ) ==
        true;
    if (!ok) return;
    await _run(() async {
      if (_journal) {
        await _api.journalDelete(widget.id);
      } else {
        await _api.ideaDelete(widget.id);
      }
      widget.onDeleted?.call();
      if (mounted) setState(() => _message = 'Deleted.');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, children: [
        if (_journal) OutlinedButton(key: const Key('entry-edit'), onPressed: _busy ? null : _edit, child: const Text('Edit')),
        OutlinedButton(key: const Key('entry-reflect'), onPressed: _busy ? null : _reflect, child: Text(_journal ? 'Reflect' : 'Sharpen')),
        OutlinedButton(key: const Key('entry-delete'), onPressed: _busy ? null : _delete, child: Text('Delete', style: TextStyle(color: C.red))),
      ]),
      if (_message != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_message!, key: const Key('entry-message'), style: T.small)),
      if (_note != null) Padding(padding: const EdgeInsets.only(top: 8), child: Markdown(_note!)),
    ]);
  }
}

/// The model's read across the whole journal, or the idea pipeline, in a sheet.
class ReviewSheet extends StatefulWidget {
  const ReviewSheet({super.key, required this.kind, this.api});
  final String kind;
  final SmallActionsApi? api;

  @override
  State<ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<ReviewSheet> {
  SmallActionsApi get _api => widget.api ?? HubSmallActionsApi(AppScope.of(context).api);
  String? _text;
  String? _stats;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      if (widget.kind == 'journal') {
        final r = await _api.journalReview();
        if (mounted) {
          setState(() {
            _text = r.review;
            _stats = r.stats;
          });
        }
      } else {
        final t = await _api.ideasReview();
        if (mounted) setState(() => _text = t);
      }
    } catch (e) {
      if (mounted) setState(() => _error = _err(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Padding(padding: const EdgeInsets.all(16), child: Text(_error!, key: const Key('review-error'), style: T.small));
    if (_text == null) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_stats != null) Text(_stats!, style: T.tiny),
        const SizedBox(height: 6),
        Markdown(_text!),
      ]),
    );
  }
}
