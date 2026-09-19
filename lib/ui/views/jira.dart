import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../widgets/common.dart';

/// Kanban, folded vertically for a phone: status sections with issue cards.
/// Transitions are GATE-territory: online-only, always confirmed.
class JiraView extends StatelessWidget {
  const JiraView({super.key});

  static const _columns = ['To Do', 'In Progress', 'In Review', 'Done'];

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return SnapshotView(
      snapshot: services.store.jira,
      builder: (context, data) {
        final issues = fmt.lm(fmt.m(data)['issues']);
        if (issues.isEmpty) {
          return const EmptyState(
            'No Jira issues',
            'Issues from the WSRU board appear here once Jira is connected.',
            icon: Icons.view_kanban_rounded,
          );
        }
        final byStatus = <String, List<Map<String, dynamic>>>{};
        for (final issue in issues) {
          final status = _statusOf(issue);
          byStatus.putIfAbsent(status, () => []).add(issue);
        }
        final known = byStatus.keys.toList()
          ..sort((a, b) {
            final ia = _columns.indexWhere(
                (c) => c.toLowerCase() == a.toLowerCase());
            final ib = _columns.indexWhere(
                (c) => c.toLowerCase() == b.toLowerCase());
            return (ia < 0 ? 99 : ia).compareTo(ib < 0 ? 99 : ib);
          });

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final status in known) ...[
              SectionLabel('$status · ${byStatus[status]!.length}'),
              for (final issue in byStatus[status]!)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _IssueCard(issue: issue),
                ),
            ],
          ],
        );
      },
    );
  }

  static String _statusOf(Map<String, dynamic> issue) {
    final direct = fmt.s(issue['status']);
    if (direct.isNotEmpty) return direct;
    return fmt.s(fmt.m(fmt.m(issue['fields'])['status'])['name']);
  }
}

class _IssueCard extends StatelessWidget {
  const _IssueCard({required this.issue});
  final Map<String, dynamic> issue;

  @override
  Widget build(BuildContext context) {
    final key = fmt.s(issue['key']);
    final fields = fmt.m(issue['fields']);
    final summary = fmt.s(issue['summary']).isEmpty
        ? fmt.s(fields['summary'])
        : fmt.s(issue['summary']);
    final assignee = fmt.s(issue['assignee']).isEmpty
        ? fmt.s(fmt.m(fields['assignee'])['displayName'])
        : fmt.s(issue['assignee']);
    final due = fmt.s(issue['duedate']).isEmpty
        ? fmt.s(fields['duedate'])
        : fmt.s(issue['duedate']);
    final priority = fmt.s(issue['priority']).isEmpty
        ? fmt.s(fmt.m(fields['priority'])['name'])
        : fmt.s(issue['priority']);

    return Panel(
      padding: const EdgeInsets.all(12),
      onLongPress: () => _actions(context, key),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Badge2(key, color: C.cyanBg, textColor: C.cyan),
              const Spacer(),
              if (priority.isNotEmpty)
                Badge2(priority,
                    color: C.surface,
                    textColor: C.forPriority(priority)),
            ],
          ),
          const SizedBox(height: 8),
          Text(summary, style: T.body2),
          const SizedBox(height: 8),
          Row(
            children: [
              if (assignee.isNotEmpty) ...[
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: C.greenBg,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: C.greenDim.withValues(alpha: 0.5)),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    assignee
                        .split(' ')
                        .where((w) => w.isNotEmpty)
                        .take(2)
                        .map((w) => w[0])
                        .join()
                        .toUpperCase(),
                    style: T.monoSmall.copyWith(
                        fontSize: 8, color: C.greenBright),
                  ),
                ),
                const SizedBox(width: 6),
                Text(assignee, style: T.monoSmall),
              ],
              const Spacer(),
              if (due.isNotEmpty)
                Text('due ${fmt.dueLabel(due)}',
                    style: T.monoSmall.copyWith(
                      color: (fmt.daysUntil(due) ?? 1) < 0
                          ? C.red
                          : C.text3,
                    )),
            ],
          ),
        ],
      ),
    );
  }

  void _actions(BuildContext context, String key) {
    final services = AppScope.of(context);
    if (!services.sync.online) {
      toast(context, 'Jira actions need the live server - you are offline.',
          error: true);
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: C.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Sz.rXl)),
        side: BorderSide(color: C.border),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            for (final transition in ['In Progress', 'In Review', 'Done'])
              ListTile(
                dense: true,
                leading:
                    const Icon(Icons.arrow_forward_rounded, size: 18),
                title: Text('Move to $transition', style: T.body2),
                onTap: () async {
                  Navigator.pop(ctx);
                  final sure = await confirmDialog(
                    context,
                    'Transition $key?',
                    'This writes to the company Jira board as Riley. '
                        'Move to "$transition"?',
                    action: 'Move',
                  );
                  if (!sure || !context.mounted) return;
                  try {
                    final res = await services.mutations.post(
                        '/api/jira/transition',
                        {'issueKey': key, 'transition': transition});
                    if (!context.mounted) return;
                    final map = fmt.m(res);
                    if (map['success'] == true) {
                      toast(context, '$key -> $transition');
                      services.store.jira.refresh();
                    } else {
                      toast(context,
                          fmt.s(map['error']).isEmpty
                              ? 'Transition failed'
                              : fmt.s(map['error']),
                          error: true);
                    }
                  } catch (e) {
                    if (context.mounted) {
                      toast(context, 'Transition failed: offline?',
                          error: true);
                    }
                  }
                },
              ),
            const Divider(height: 1),
            ListTile(
              dense: true,
              leading: const Icon(Icons.person_add_alt_1_rounded, size: 18),
              title: const Text('Assign...', style: T.body2),
              onTap: () {
                Navigator.pop(ctx);
                _pickAssignee(context, key);
              },
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.check_circle_outline_rounded,
                  size: 18, color: C.text2),
              title: const Text('Clear (move to Done)', style: T.body2),
              onTap: () async {
                Navigator.pop(ctx);
                final sure = await confirmDialog(
                  context,
                  'Clear $key?',
                  'Moves the issue to Done without deleting it - the honest '
                      'fallback when delete permission isn\'t granted.',
                  action: 'Clear',
                );
                if (!sure || !context.mounted) return;
                await _post(context, '/api/jira/clear', {'issueKey': key},
                    successMsg: '$key cleared');
              },
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.delete_outline_rounded,
                  size: 18, color: C.red),
              title: const Text('Delete...', style: T.body2),
              onTap: () async {
                Navigator.pop(ctx);
                await _deleteWithPermissionCheck(context, key);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteWithPermissionCheck(
      BuildContext context, String key) async {
    final services = AppScope.of(context);
    Map<String, dynamic> perms;
    try {
      perms = fmt.m(await services.api.getJson('/api/jira/permissions'));
    } catch (_) {
      perms = const {};
    }
    if (!context.mounted) return;
    final canDelete = perms['canDelete'] == true;
    if (!canDelete) {
      final useClear = await confirmDialog(
        context,
        'No delete permission',
        'This Jira account can\'t delete issues on this project. Clear '
            '$key to Done instead?',
        action: 'Clear instead',
      );
      if (useClear && context.mounted) {
        await _post(context, '/api/jira/clear', {'issueKey': key},
            successMsg: '$key cleared');
      }
      return;
    }
    final sure = await confirmDialog(
      context,
      'Delete $key?',
      'This permanently deletes the issue from the company Jira board. '
          'This cannot be undone.',
      action: 'Delete',
      destructive: true,
    );
    if (!sure || !context.mounted) return;
    await _post(context, '/api/jira/delete', {'issueKey': key},
        successMsg: '$key deleted');
  }

  Future<void> _pickAssignee(BuildContext context, String key) async {
    final services = AppScope.of(context);
    List<Map<String, dynamic>> users;
    try {
      final res = fmt.m(await services.api.getJson('/api/jira/assignable'));
      users = fmt.lm(res['users']);
    } catch (e) {
      if (context.mounted) {
        toast(context, 'Could not load assignable users', error: true);
      }
      return;
    }
    if (!context.mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Sz.rXl)),
        side: BorderSide(color: C.border),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        maxChildSize: 0.85,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            Text('Assign $key', style: T.title),
            const SizedBox(height: 10),
            ListTile(
              dense: true,
              leading: const Icon(Icons.person_off_outlined, size: 18),
              title: const Text('Unassign', style: T.body2),
              onTap: () async {
                Navigator.pop(ctx);
                await _post(context, '/api/jira/assign',
                    {'issueKey': key, 'accountId': null},
                    successMsg: '$key unassigned');
              },
            ),
            if (users.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 20),
                child: EmptyState('No assignable users',
                    'Nobody on this Jira project can be assigned right now.'),
              )
            else
              for (final u in users)
                ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 12,
                    backgroundColor: C.greenBg,
                    child: Text(
                      fmt.s(u['displayName'])
                          .split(' ')
                          .where((w) => w.isNotEmpty)
                          .take(2)
                          .map((w) => w[0])
                          .join()
                          .toUpperCase(),
                      style: T.monoSmall.copyWith(
                          fontSize: 9, color: C.greenBright),
                    ),
                  ),
                  title: Text(fmt.s(u['displayName']), style: T.body2),
                  subtitle: fmt.s(u['email']).isEmpty
                      ? null
                      : Text(fmt.s(u['email']), style: T.monoSmall),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _post(context, '/api/jira/assign',
                        {'issueKey': key, 'accountId': u['accountId']},
                        successMsg: 'Assigned to ${fmt.s(u['displayName'])}');
                  },
                ),
          ],
        ),
      ),
    );
  }

  Future<void> _post(
      BuildContext context, String path, Map<String, dynamic> body,
      {required String successMsg}) async {
    final services = AppScope.of(context);
    try {
      final res = await services.mutations.post(path, body);
      if (!context.mounted) return;
      final map = fmt.m(res);
      if (map['success'] == true || map['error'] == null) {
        toast(context, successMsg);
        services.store.jira.refresh();
      } else {
        toast(context, fmt.s(map['error']).isEmpty ? 'Action failed' : fmt.s(map['error']),
            error: true);
      }
    } catch (e) {
      if (context.mounted) toast(context, 'Action failed: $e', error: true);
    }
  }
}
