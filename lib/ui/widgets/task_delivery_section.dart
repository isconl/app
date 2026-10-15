import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/task_delivery.dart';
import '../../theme.dart';
import 'common.dart';
import 'documents_widgets.dart';

/// The rest of the console's task page: the covering note, who it goes to,
/// coverage with Provision, the files it produced with relink, and the delivery
/// state. Writes here need a connection and an explicit tap; recording a send
/// shows the recipient list first and never happens on its own.
class TaskDeliverySection extends StatefulWidget {
  const TaskDeliverySection({
    super.key,
    required this.taskId,
    required this.task,
    required this.client,
    required this.online,
    required this.openUrl,
    this.onChanged,
    this.today,
  });

  final String taskId;

  /// The task row as the detail route returns it (DELIVERY, STATUS, SENT_TO ...).
  final Map<String, dynamic> task;
  final TaskDeliveryClient client;
  final bool online;
  final Future<void> Function(String url) openUrl;

  /// Called after a write so the screen can refresh the task.
  final Future<void> Function()? onChanged;

  /// Today's date for the send form (tests pin it).
  final String Function()? today;

  @override
  State<TaskDeliverySection> createState() => _TaskDeliverySectionState();
}

class _TaskDeliverySectionState extends State<TaskDeliverySection> {
  List<Recipient> _recipients = const [];
  TaskDocs _docs = const TaskDocs();
  TaskCoverage? _coverage;
  bool _loaded = false;
  bool _failed = false;
  bool _busy = false;
  String? _message;
  late Map<String, dynamic> _task = widget.task;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(TaskDeliverySection old) {
    super.didUpdateWidget(old);
    if (old.task != widget.task) _task = widget.task;
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait<Object?>([
        widget.client.recipients(),
        widget.client.deliverables(widget.taskId),
        widget.client.coverage(widget.taskId),
      ]);
      if (!mounted) return;
      setState(() {
        _recipients = r[0] as List<Recipient>;
        _docs = r[1] as TaskDocs;
        _coverage = r[2] as TaskCoverage?;
        _loaded = true;
        _failed = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loaded = true;
          _failed = true;
        });
      }
    }
  }

  Future<void> _run(String done, Future<Object?> Function() action, {Map<String, dynamic>? patch}) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await action();
      if (patch != null) _task = {..._task, ...patch};
      _message = result is String ? result : done;
      await widget.onChanged?.call();
      await _load();
    } catch (e) {
      _message = '$e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyNote() async {
    try {
      final text = await widget.client.note(widget.taskId);
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) setState(() => _message = 'The covering note is copied.');
    } catch (e) {
      if (mounted) setState(() => _message = '$e');
    }
  }

  Future<void> _recordSend() async {
    final r = await showDialog<_SendRecord>(
      context: context,
      builder: (_) => _SendDialog(recipients: _recipients, task: _task, today: (widget.today ?? _todayIso)()),
    );
    if (r == null) return;
    await _run(
      'Recorded as sent. The task stays open until you close it.',
      () => widget.client.recordSend(widget.taskId, sentTo: r.to, sentVia: r.via, sentAt: r.at, note: r.note),
      patch: {'DELIVERY': 'sent', 'SENT_TO': r.to, 'SENT_VIA': r.via, 'SENT_AT': r.at, 'DELIVERY_NOTE': r.note},
    );
  }

  static String _todayIso() => DateTime.now().toIso8601String().substring(0, 10);

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Padding(padding: EdgeInsets.all(16), child: Center(child: MiniSpinner()));
    final state = deliveryStateOf(_task);
    final sent = state == 'sent';
    final enabled = widget.online && !_busy;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_failed)
        Panel(child: Text('Could not load delivery details. Check your connection.', key: const Key('delivery-failed'), style: T.small)),
      if (!widget.online) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Offline: these details need a connection to change.', style: T.tiny)),

      const SectionLabel('Delivery'),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Badge2(deliveryLabels[state] ?? state, color: sent ? C.greenBg : C.surface, textColor: sent ? C.greenBright : C.text2),
          ]),
          if (sent) ...[
            const SizedBox(height: 8),
            Text(
              'Sent to ${_s(_task['SENT_TO'], 'someone')}${_s(_task['SENT_VIA']).isEmpty ? '' : ' via ${_s(_task['SENT_VIA'])}'}'
              '${_s(_task['SENT_AT']).isEmpty ? '' : ' on ${_s(_task['SENT_AT']).substring(0, _s(_task['SENT_AT']).length.clamp(0, 10))}'}',
              key: const Key('delivery-sent'),
              style: T.body2,
            ),
            if (_s(_task['DELIVERY_NOTE']).isNotEmpty) Text(_s(_task['DELIVERY_NOTE']), style: T.small),
            const SizedBox(height: 4),
            Text('Still open until you close it. Being sent is not being accepted.', style: T.tiny),
          ],
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (state != 'reviewed' && !sent)
              OutlinedButton(
                key: const Key('mark-reviewed'),
                onPressed: enabled
                    ? () => _run('Marked reviewed. It is ready to go.', () => widget.client.setDelivery(widget.taskId, 'reviewed'),
                        patch: {'DELIVERY': 'reviewed'})
                    : null,
                child: const Text('Mark reviewed'),
              ),
            FilledButton(
              key: const Key('record-send'),
              onPressed: enabled ? _recordSend : null,
              child: Text(sent ? 'Edit the record' : 'Record send'),
            ),
            if (sent)
              OutlinedButton(
                key: const Key('not-sent'),
                onPressed: enabled
                    ? () => _run('Back to reviewed.', () => widget.client.setDelivery(widget.taskId, 'reviewed'), patch: {'DELIVERY': 'reviewed'})
                    : null,
                child: const Text('Not sent after all'),
              ),
          ]),
        ]),
      ),

      const SectionLabel('Covering note'),
      Panel(
        child: Row(children: [
          Expanded(child: Text(_docs.noteText.isEmpty ? 'No note on file for this task yet.' : _preview(_docs.noteText), style: T.small, key: const Key('note-preview'))),
          TextButton(key: const Key('copy-note'), onPressed: widget.online ? _copyNote : null, child: const Text('Copy')),
        ]),
      ),

      const SectionLabel('Recipients'),
      Panel(
        child: _recipients.isEmpty
            ? Text('No one on record yet.', style: T.small)
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final r in _recipients) Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text('${r.name}${r.role.isEmpty ? '' : ', ${r.role}'}', style: T.body2)),
              ]),
      ),

      const SectionLabel('Coverage'),
      Panel(
        child: _coverage == null
            ? Text('Not on the coverage list.', style: T.small)
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_coverage!.covered ? 'Covered: it has its deliverable and its words.' : 'Missing: ${_coverage!.gaps.join(', ')}',
                    key: const Key('coverage-text'), style: T.body2.copyWith(color: _coverage!.covered ? C.greenBright : C.amber)),
                if (!_coverage!.covered) ...[
                  const SizedBox(height: 8),
                  OutlinedButton(
                    key: const Key('provision'),
                    onPressed: enabled ? () => _run('Created the deliverable and linked it.', () => widget.client.provision(widget.taskId)) : null,
                    child: const Text('Provision the deliverable'),
                  ),
                ],
              ]),
      ),

      const SectionLabel('Deliverables'),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (_docs.all.isEmpty) Text('Nothing produced for this one yet.', style: T.small),
          for (final d in _docs.all)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(d.name, style: T.body2),
                    Text(
                      '${d.isGuess ? 'best guess' : 'attached'}${d.role == 'note' ? ', covering note' : ''}'
                      '${d.bytes > 0 ? ', ${(d.bytes / 1024).round()} KB' : ''}'
                      '${d.onedrive == false ? ', not on OneDrive yet' : d.stale ? ', OneDrive copy is behind' : ''}',
                      style: T.tiny.copyWith(color: (d.onedrive == false || d.stale) ? C.amber : C.text3),
                    ),
                    if (d.rel.isNotEmpty && widget.online) DeliverableActions(rel: d.rel, name: d.name, onChanged: () => _load()),
                  ]),
                ),
                if (d.webUrl.isNotEmpty) TextButton(key: Key('open-${d.name}'), onPressed: () => widget.openUrl(d.webUrl), child: const Text('Open')),
              ]),
            ),
          if (_docs.dead > 0) Text('${_docs.dead} linked file${_docs.dead == 1 ? '' : 's'} no longer on disk', style: T.tiny.copyWith(color: C.amber)),
          const SizedBox(height: 6),
          OutlinedButton(
            key: const Key('relink'),
            onPressed: enabled ? () => _run('Relinked.', () => widget.client.relink()) : null,
            child: const Text('Relink the board'),
          ),
        ]),
      ),
      if (_message != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_message!, key: const Key('delivery-message'), style: T.small)),
    ]);
  }

  static String _s(Object? v, [String fallback = '']) {
    final s = v == null ? '' : '$v';
    return (s.isEmpty || s == '-') ? fallback : s;
  }

  static String _preview(String t) => t.length <= 220 ? t : '${t.substring(0, 217)}...';
}

class _SendRecord {
  const _SendRecord(this.to, this.via, this.at, this.note);
  final String to;
  final String via;
  final String at;
  final String note;
}

class _SendDialog extends StatefulWidget {
  const _SendDialog({required this.recipients, required this.task, required this.today});
  final List<Recipient> recipients;
  final Map<String, dynamic> task;
  final String today;

  @override
  State<_SendDialog> createState() => _SendDialogState();
}

class _SendDialogState extends State<_SendDialog> {
  late String _to = _initialTo();
  late String _via = sendVias.contains('${widget.task['SENT_VIA']}') ? '${widget.task['SENT_VIA']}' : 'email';
  late final TextEditingController _at = TextEditingController(text: _initialAt());
  late final TextEditingController _note = TextEditingController(text: _clean(widget.task['DELIVERY_NOTE']));

  static String _clean(Object? v) {
    final s = v == null ? '' : '$v';
    return s == '-' ? '' : s;
  }

  String _initialTo() {
    final names = widget.recipients.map((r) => r.name).toList();
    final cur = _clean(widget.task['SENT_TO']);
    if (cur.isNotEmpty && names.contains(cur)) return cur;
    return names.isEmpty ? '' : names.first;
  }

  String _initialAt() {
    final s = _clean(widget.task['SENT_AT']);
    return s.isEmpty ? widget.today : s.substring(0, s.length.clamp(0, 10));
  }

  @override
  void dispose() {
    _at.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Record the send'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('This records a handover you have made. It does not send anything.', style: T.small),
            const SizedBox(height: 10),
            if (widget.recipients.isEmpty)
              Text('No one is on record to send to yet.', key: const Key('send-no-recipients'), style: T.small)
            else
              DropdownButton<String>(
                key: const Key('send-to'),
                isExpanded: true,
                value: _to,
                items: [for (final r in widget.recipients) DropdownMenuItem(value: r.name, child: Text('${r.name}${r.role.isEmpty ? '' : ' (${r.role})'}', overflow: TextOverflow.ellipsis))],
                onChanged: (v) => setState(() => _to = v ?? _to),
              ),
            DropdownButton<String>(
              key: const Key('send-via'),
              isExpanded: true,
              value: _via,
              items: [for (final v in sendVias) DropdownMenuItem(value: v, child: Text(v))],
              onChanged: (v) => setState(() => _via = v ?? _via),
            ),
            TextField(key: const Key('send-at'), controller: _at, decoration: const InputDecoration(labelText: 'When (YYYY-MM-DD)')),
            TextField(key: const Key('send-note'), controller: _note, decoration: const InputDecoration(labelText: 'Note (optional)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            key: const Key('send-confirm'),
            onPressed: _to.isEmpty ? null : () => Navigator.pop(context, _SendRecord(_to, _via, _at.text.trim(), _note.text.trim())),
            child: Text('Record sent to ${_to.isEmpty ? '...' : _to}'),
          ),
        ],
      );
}
