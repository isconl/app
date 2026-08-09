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
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
