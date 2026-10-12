import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../api/client.dart' show OfflineException;
import '../../data/module_ops.dart';
import '../../data/outbox.dart' show OutboxService;
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import 'common.dart';

/// BI26100110: module lifecycle on the phone, the same controls as the hub web console (BI26100109). A module has a
/// lifecycle state (draft, live, superseded, retired, archived) and may be missing from disk. Live modules carry no
/// badge. Retire and restore open a confirm sheet that shows the dry-run manifest, and nothing changes until Confirm;
/// offline the change is queued in the outbox and shows as pending. Superseded and retired modules are not in the
/// reading list: they sit under a History expander on the course, where retired ones can be restored. Whether the
/// session may do it is the server's call, and a refusal is shown as the server's own reason.
List<({String label, Color color})> lifecycleBadges(Map<String, dynamic> lesson, {ModuleOp? op}) {
  final state = fmt.s(lesson['lifecycle']).toLowerCase();
  final out = <({String label, Color color})>[];
  if (state.isNotEmpty && state != 'live') {
    out.add((
      label: state,
      color: switch (state) {
        'retired' => C.red,
        'superseded' => C.amber,
        _ => C.text3,
      },
    ));
  }
  if (lesson['missing'] == true) out.add((label: 'missing', color: C.red));
  // BI26101204: a retire or restore still waiting in the outbox, or refused by the server.
  if (op != null) out.add((label: op.failed ? '${op.op} refused' : '${op.op} pending', color: op.failed ? C.red : C.amber));
  return out;
}

class LifecycleBadges extends StatelessWidget {
  const LifecycleBadges(this.lesson, {super.key});
  final Map<String, dynamic> lesson;

  @override
  Widget build(BuildContext context) {
    OutboxService? outbox;
    try {
      outbox = AppScope.of(context).outbox;
    } catch (_) {}
    if (outbox == null) return _badges(null);
    return ListenableBuilder(
      listenable: outbox,
      builder: (context, _) => _badges(outbox!.moduleOps[fmt.s(lesson['moduleId'])]),
    );
  }

  Widget _badges(ModuleOp? op) {
    final badges = lifecycleBadges(lesson, op: op);
    if (badges.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(spacing: 6, children: [
            for (final b in badges)
              Container(
                key: Key('lifecycle-${b.label}'),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(border: Border.all(color: b.color), borderRadius: BorderRadius.circular(8)),
                child: Text(b.label, style: T.tiny.copyWith(color: b.color)),
              ),
          ]),
          // The server's own reason for a refusal, where the reader will see it.
          if (op != null && op.failed && op.reason.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 2), child: Text(op.reason, key: const Key('lifecycle-reason'), style: T.tiny.copyWith(color: C.red))),
        ],
      ),
    );
  }
}

/// Open the confirm sheet for [op] ('retire' or 'restore') on [lesson]. Does nothing for a lesson with no module id.
Future<void> showModuleLifecycleSheet(BuildContext context, {required String op, required String courseId, required Map<String, dynamic> lesson}) {
  if (fmt.s(lesson['moduleId']).isEmpty) return Future.value();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.surface,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _LifecycleSheet(op: op, courseId: courseId, lesson: lesson, services: AppScope.of(context)),
    ),
  );
}

class _LifecycleSheet extends StatefulWidget {
  const _LifecycleSheet({required this.op, required this.courseId, required this.lesson, required this.services});
  final String op;
  final String courseId;
  final Map<String, dynamic> lesson;
  final AppServices services;

  @override
  State<_LifecycleSheet> createState() => _LifecycleSheetState();
}

class _LifecycleSheetState extends State<_LifecycleSheet> {
  Map<String, dynamic>? _preview;
  String? _error;
  bool _offline = false;
  bool _busy = false;
  final _why = TextEditingController();

  String get _word => widget.op == 'retire' ? 'Retire' : 'Restore';
  String get _moduleId => fmt.s(widget.lesson['moduleId']);

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  @override
  void dispose() {
    _why.dispose();
    super.dispose();
  }

  Future<void> _loadPreview() async {
    try {
      final d = await widget.services.mutations.moduleManifestPreview(op: widget.op, moduleId: _moduleId);
      if (!mounted) return;
      setState(() {
        if (d['ok'] == true) {
          _preview = d;
        } else {
          final errs = (d['errors'] is List ? (d['errors'] as List).map((e) => fmt.s(e)).join(' ') : '').trim();
          _error = errs.isNotEmpty ? errs : (fmt.s(d['error']).isNotEmpty ? fmt.s(d['error']) : 'This change cannot be made.');
        }
      });
    } on OfflineException {
      if (mounted) setState(() => _offline = true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final why = _why.text.trim().isEmpty ? 'from the app' : _why.text.trim();
    final r = await widget.services.mutations.moduleLifecycle(op: widget.op, moduleId: _moduleId, why: why);
    if (!mounted) return;
    if (r.ok) {
      toast(context, r.queued ? 'Queued. It applies when you are back online.' : (widget.op == 'retire' ? 'Module retired' : 'Module restored'));
      Navigator.pop(context);
    } else {
      setState(() {
        _busy = false;
        _error = r.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final changes = fmt.lm(_preview?['changes']);
    final affected = fmt.i(fmt.m(_preview?['summary'])['affectedLearners']);
    final title = fmt.s(widget.lesson['TITLE']).isNotEmpty ? fmt.s(widget.lesson['TITLE']) : fmt.s(widget.lesson['title'] ?? widget.lesson['file']);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$_word this module?', style: T.title),
            const SizedBox(height: 6),
            Text(title, style: T.body2.copyWith(fontWeight: FontWeight.w600)),
            Text('${widget.courseId} · ${fmt.s(widget.lesson['file'])}', style: T.small.copyWith(color: C.text3)),
            const SizedBox(height: 12),
            if (_error != null)
              Text(_error!, key: const Key('lifecycle-error'), style: T.small.copyWith(color: C.red))
            else if (_offline)
              Text('You are offline, so the manifest cannot be shown. If you confirm, the change is queued and applies when you are back online.', key: const Key('lifecycle-offline'), style: T.small)
            else if (_preview == null)
              const Text('Reading the manifest…')
            else ...[
              Text('What changes:', style: T.small.copyWith(color: C.text3)),
              for (final c in changes) Text('${fmt.s(c['before'])} to ${fmt.s(c['after'])}', key: const Key('lifecycle-change')),
              if (changes.isEmpty) const Text('Nothing.'),
              const SizedBox(height: 6),
              Text(
                '$affected learner${affected == 1 ? '' : 's'} with progress on it. ${widget.op == 'retire' ? 'Their progress is kept; the module leaves the course and stays in history.' : 'It returns to the course.'}',
                key: const Key('lifecycle-affected'),
                style: T.small.copyWith(color: C.text2),
              ),
            ],
            const SizedBox(height: 10),
            TextField(key: const Key('lifecycle-why'), controller: _why, decoration: const InputDecoration(hintText: 'Why this change')),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(key: const Key('lifecycle-cancel'), onPressed: _busy ? null : () => Navigator.pop(context), child: Text('Cancel', style: T.body2.copyWith(color: C.text3))),
                const SizedBox(width: 8),
                FilledButton(
                  key: const Key('lifecycle-confirm'),
                  // A refused preview leaves nothing to confirm. Offline, or after a failed confirm, the person can still try.
                  onPressed: _busy || (_error != null && _preview == null) ? null : _confirm,
                  child: Text(_busy ? 'Working' : 'Confirm ${_word.toLowerCase()}'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The History expander on a course: the modules the reading list no longer shows (retired and superseded), with their
/// badge, and Restore on the retired ones.
class ModuleHistory extends StatelessWidget {
  const ModuleHistory({super.key, required this.courseId, required this.hidden});
  final String courseId;
  final List<Map<String, dynamic>> hidden;

  @override
  Widget build(BuildContext context) {
    if (hidden.isEmpty) return const SizedBox.shrink();
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const Key('module-history'),
        tilePadding: EdgeInsets.zero,
        title: Text('History · ${hidden.length}', style: T.small.copyWith(color: C.text3)),
        children: [
          for (final l in hidden)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(fmt.s(l['TITLE']).isNotEmpty ? fmt.s(l['TITLE']) : fmt.s(l['title'] ?? l['file']), style: T.body2),
                        LifecycleBadges(l),
                        if (fmt.s(l['supersededBy']).isNotEmpty) Text('replaced by ${fmt.s(l['supersededBy'])}', style: T.tiny.copyWith(color: C.text3)),
                      ],
                    ),
                  ),
                  if (fmt.s(l['lifecycle']).toLowerCase() == 'retired' && fmt.s(l['moduleId']).isNotEmpty)
                    TextButton(
                      key: Key('history-restore-${fmt.s(l['moduleId'])}'),
                      onPressed: () => showModuleLifecycleSheet(context, op: 'restore', courseId: courseId, lesson: l),
                      child: const Text('Restore'),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
