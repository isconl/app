import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import 'common.dart';

/// BI26100504: the Jira write side on the phone, the same review-then-push gate the console has. Everything here goes
/// through hub (`/api/jira/preview`, `/push`, `/pending`), the app never holds Jira credentials, and nothing is pushed
/// without an explicit Push or Approve tap. Pushing needs a connection; a failed push keeps the draft on screen.
///
/// Not here: `/api/jira/compose` (the AI draft) and `/api/jira/schedule` (move a date or owner on a live issue). Hub
/// answers both with 501 today, because neither has been built in the fleet. The sheet does not show buttons for them.

typedef JiraCheck = ({String id, bool ok, String label, String hint});

/// The readiness checklist, re-evaluated on every edit exactly as the console does. The server runs the same gate again
/// at push time, so this is guidance, not the authority.
List<JiraCheck> jiraReadiness(Map<String, String> e) {
  final summary = (e['summary'] ?? '').trim();
  return [
    (
      id: 'summary',
      ok: summary.length >= 12 && summary.split(RegExp(r'\s+')).length >= 3,
      label: 'Summary states an outcome',
      hint: 'Under three words reads as a placeholder to everyone else on the board.',
    ),
    (
      id: 'description',
      ok: (e['description'] ?? '').trim().length >= 40,
      label: 'Description is filled in',
      hint: 'Explain the task so someone else can pick it up.',
    ),
    (
      id: 'duedate',
      ok: RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(e['duedate'] ?? ''),
      label: 'Has a date',
      hint: 'An undated issue does not appear in any timeline.',
    ),
    (
      id: 'tag',
      ok: (e['tag'] ?? '').isNotEmpty,
      label: 'Tagged',
      hint: 'Tag it so work, personal and space items stay separable on one board.',
    ),
    (
      id: 'assignee',
      ok: (e['assignee'] ?? '').isNotEmpty,
      label: 'Has an owner',
      hint: 'Unassigned issues belong to nobody.',
    ),
  ];
}

/// One line for a pending item: its summary, or "KEY: from to to" for a transition draft, or the action name.
String pendingLabel(Map<String, dynamic> p) {
  final pl = fmt.m(p['payload']);
  if (fmt.s(pl['summary']).isNotEmpty) return fmt.s(pl['summary']);
  final key = fmt.s(pl['key']);
  if (key.isNotEmpty) {
    if (fmt.s(pl['from']).isNotEmpty && fmt.s(pl['to']).isNotEmpty) return '$key: ${fmt.s(pl['from'])} to ${fmt.s(pl['to'])}';
    if (fmt.s(pl['transitionName']).isNotEmpty) return '$key: ${fmt.s(pl['transitionName'])}';
    return key;
  }
  return fmt.s(p['action']);
}

/// Only items still waiting for a decision.
List<Map<String, dynamic>> pendingOnly(dynamic data) => [
      for (final p in fmt.lm(fmt.m(data)['pending']))
        if (fmt.s(p['status']) == 'pending') p,
    ];

/// The queue of writes agents have drafted, each with Approve and Deny. Hidden when there is nothing waiting.
class JiraPendingSection extends StatefulWidget {
  const JiraPendingSection({super.key, this.onChanged});
  final VoidCallback? onChanged;

  @override
  State<JiraPendingSection> createState() => _JiraPendingSectionState();
}

class _JiraPendingSectionState extends State<JiraPendingSection> {
  List<Map<String, dynamic>>? _items;
  bool _failed = false;
  String? _busy;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final r = await AppScope.of(context).api.getJson('/api/jira/pending');
      if (!mounted) return;
      setState(() {
        _items = pendingOnly(r);
        _failed = false;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _decide(Map<String, dynamic> p, {required bool approve}) async {
    final id = fmt.s(p['id']);
    final sure = await confirmDialog(
      context,
      approve ? 'Approve this Jira write?' : 'Deny this write?',
      approve
          ? 'The real Jira call fires immediately: ${pendingLabel(p)}'
          : 'It is discarded and nothing reaches Jira: ${pendingLabel(p)}',
      action: approve ? 'Approve' : 'Deny',
      destructive: !approve,
    );
    if (!sure || !mounted) return;
    setState(() => _busy = id);
    try {
      final res = fmt.m(await AppScope.of(context).mutations.post(
        approve ? '/api/jira/pending/approve' : '/api/jira/pending/deny',
        {'id': id, 'decidedBy': 'Architect'},
      ));
      if (!mounted) return;
      if (res['success'] == true) {
        toast(context, approve ? 'Approved. Jira key: ${fmt.s(res['key']).isEmpty ? 'done' : fmt.s(res['key'])}' : 'Write denied and discarded.');
        widget.onChanged?.call();
      } else {
        toast(context, '${approve ? 'Approve' : 'Deny'} failed: ${fmt.s(res['error']).isEmpty ? 'unknown' : fmt.s(res['error'])}', error: true);
      }
    } catch (_) {
      if (mounted) toast(context, 'That needs the live server - you are offline.', error: true);
    }
    if (mounted) setState(() => _busy = null);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items == null) {
      return _failed ? Text('Pending approvals could not be loaded.', style: T.small.copyWith(color: C.text3)) : const SizedBox.shrink();
    }
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel('Pending approvals · ${items.length}'),
        for (final p in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Panel(
              key: Key('pending-${fmt.s(p['id'])}'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(pendingLabel(p), style: T.body2),
                  const SizedBox(height: 4),
                  Text('${fmt.s(p['action'])} · by ${fmt.s(p['requester']).isEmpty ? 'agent' : fmt.s(p['requester'])} · ${fmt.s(p['createdAt']).length >= 16 ? fmt.s(p['createdAt']).substring(0, 16) : fmt.s(p['createdAt'])}', style: T.monoSmall),
                  const SizedBox(height: 8),
                  Row(children: [
                    FilledButton(
                      key: Key('approve-${fmt.s(p['id'])}'),
                      onPressed: _busy == null ? () => _decide(p, approve: true) : null,
                      child: const Text('Approve'),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      key: Key('deny-${fmt.s(p['id'])}'),
                      onPressed: _busy == null ? () => _decide(p, approve: false) : null,
                      child: const Text('Deny'),
                    ),
                  ]),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Open the review sheet for one task. Returns true when an issue was created.
Future<bool?> showJiraReview(BuildContext context, String taskId) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Sz.rXl)),
      side: BorderSide(color: C.border),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: JiraReviewSheet(taskId: taskId),
    ),
  );
}

/// Preview what would be created, edit it, see the checklist, and push. A failed push shows hub's error and keeps what
/// was typed.
class JiraReviewSheet extends StatefulWidget {
  const JiraReviewSheet({super.key, required this.taskId});
  final String taskId;

  @override
  State<JiraReviewSheet> createState() => _JiraReviewSheetState();
}

class _JiraReviewSheetState extends State<JiraReviewSheet> {
  final _summary = TextEditingController();
  final _description = TextEditingController();
  final _due = TextEditingController();
  String _assignee = '';
  String _tag = '';
  String _priority = 'medium';
  List<Map<String, dynamic>> _users = const [];
  List<String> _tags = const [];
  String _project = '';
  bool _loading = true;
  bool _pushing = false;
  String? _error;
  String? _createdKey;

  Map<String, String> get _edits => {
        'summary': _summary.text,
        'description': _description.text,
        'duedate': _due.text.trim(),
        'assignee': _assignee,
        'tag': _tag,
      };

  @override
  void initState() {
    super.initState();
    for (final c in [_summary, _description, _due]) {
      c.addListener(() => setState(() {}));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _preview());
  }

  @override
  void dispose() {
    _summary.dispose();
    _description.dispose();
    _due.dispose();
    super.dispose();
  }

  Future<void> _preview() async {
    try {
      final d = fmt.m(await AppScope.of(context).api.postJson('/api/jira/preview', {'taskId': widget.taskId}));
      if (!mounted) return;
      if (d['success'] != true) {
        setState(() {
          _loading = false;
          _error = fmt.s(d['error']).isEmpty ? 'Could not prepare the issue.' : fmt.s(d['error']);
        });
        return;
      }
      final p = fmt.m(d['payload']);
      final labels = p['labels'] is List ? (p['labels'] as List) : const [];
      setState(() {
        _summary.text = fmt.s(p['summary']);
        _description.text = fmt.s(p['description']);
        _due.text = fmt.s(p['duedate']);
        _assignee = fmt.s(p['assignee']);
        _tag = labels.isEmpty ? '' : fmt.s(labels.first);
        _priority = fmt.s(p['priority']).isEmpty ? 'medium' : fmt.s(p['priority']);
        _users = fmt.lm(d['users']);
        _tags = [for (final t in (d['tags'] is List ? d['tags'] as List : const [])) fmt.s(t)];
        _project = fmt.s(d['project']);
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not reach the server to prepare the issue.';
        });
      }
    }
  }

  Future<void> _push({required bool force}) async {
    if (force) {
      final sure = await confirmDialog(
        context,
        'Push it incomplete?',
        'This issue is missing things, and it cannot be deleted from this project once created.',
        action: 'Push anyway',
        destructive: true,
      );
      if (!sure || !mounted) return;
    }
    setState(() {
      _pushing = true;
      _error = null;
    });
    try {
      final d = fmt.m(await AppScope.of(context).mutations.post('/api/jira/push', {
        'taskId': widget.taskId,
        'force': force,
        'summary': _summary.text,
        'description': _description.text,
        'duedate': _due.text.trim(),
        'assignee': _assignee,
        'priority': _priority,
        'labels': _tag.isEmpty ? <String>[] : [_tag],
      }));
      if (!mounted) return;
      if (d['success'] == true) {
        setState(() => _createdKey = fmt.s(d['key']));
        toast(context, 'Created ${fmt.s(d['key'])}');
        AppScope.of(context).store.jira.refresh();
        Navigator.pop(context, true);
        return;
      }
      setState(() => _error = fmt.s(d['error']).isEmpty ? 'Jira rejected it.' : fmt.s(d['error']));
    } catch (_) {
      if (mounted) setState(() => _error = 'Pushing needs the live server - you are offline. Your draft is kept.');
    }
    if (mounted) setState(() => _pushing = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(padding: EdgeInsets.all(40), child: Center(child: MiniSpinner()));
    }
    final checks = jiraReadiness(_edits);
    final failing = checks.where((c) => !c.ok).length;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_project.isEmpty ? 'New Jira issue' : 'New Jira issue · $_project', style: T.title),
            const SizedBox(height: 4),
            Text('Read it before it becomes permanent. Nothing is created until you tap Create.', style: T.small.copyWith(color: C.text3)),
            const SizedBox(height: 12),
            Field(label: 'Summary', controller: _summary, key: const Key('jira-summary')),
            Field(label: 'Description', controller: _description, maxLines: 5, key: const Key('jira-description')),
            Field(label: 'Due date (YYYY-MM-DD)', controller: _due, key: const Key('jira-due')),
            if (_tags.isNotEmpty) Segmented(label: 'Tag', options: _tags, value: _tag, onChanged: (v) => setState(() => _tag = v)),
            Segmented(label: 'Priority', options: const ['low', 'medium', 'high'], value: _priority, onChanged: (v) => setState(() => _priority = v)),
            if (_users.isNotEmpty)
              DropdownButton<String>(
                key: const Key('jira-assignee'),
                isExpanded: true,
                hint: const Text('Owner'),
                value: _users.any((u) => fmt.s(u['accountId']) == _assignee) ? _assignee : null,
                items: [for (final u in _users) DropdownMenuItem(value: fmt.s(u['accountId']), child: Text(fmt.s(u['displayName'])))],
                onChanged: (v) => setState(() => _assignee = v ?? ''),
              ),
            const SizedBox(height: 8),
            for (final c in checks)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(c.ok ? Icons.check_rounded : Icons.circle_outlined, size: 14, color: c.ok ? C.green : C.text3),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(c.ok ? c.label : '${c.label}. ${c.hint}', key: Key('check-${c.id}'), style: T.small.copyWith(color: c.ok ? C.text2 : C.text3)),
                    ),
                  ],
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, key: const Key('jira-error'), style: T.small.copyWith(color: C.red)),
            ],
            const SizedBox(height: 12),
            if (_createdKey != null)
              Text('Created $_createdKey', style: T.body2)
            else
              FilledButton(
                key: const Key('jira-create'),
                onPressed: _pushing ? null : () => _push(force: failing > 0),
                child: Text(_pushing
                    ? 'Creating...'
                    : failing == 0
                        ? 'Create in Jira'
                        : '$failing thing${failing > 1 ? 's' : ''} missing - push anyway'),
              ),
          ],
        ),
      ),
    );
  }
}
