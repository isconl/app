import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../widgets/common.dart';
import 'task_detail.dart';

const kStatuses = ['today', 'next', 'waiting', 'review', 'done'];

/// The board, grouped by status. Swipe right to complete, tap for detail,
/// long-press for the action sheet.
class TasksView extends StatefulWidget {
  const TasksView({super.key});

  @override
  State<TasksView> createState() => _TasksViewState();
}

class _TasksViewState extends State<TasksView> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return Stack(
      children: [
        SnapshotView(
          snapshot: services.store.state,
          builder: (context, data) {
            final all = fmt.lm(fmt.m(data)['tasks']);
            final tags = {
              for (final t in all)
                if (fmt.s(t['TAG']).isNotEmpty) fmt.s(t['TAG']): true
            }.keys.toList()
              ..sort();

            final tasks = _filter == 'all'
                ? all
                : all.where((t) => fmt.s(t['TAG']) == _filter).toList();

            final subtasks = <String, List<Map<String, dynamic>>>{};
            final mains = <Map<String, dynamic>>[];
            for (final t in tasks) {
              final parent = fmt.s(t['PARENT_ID']);
              if (parent.isEmpty) {
                mains.add(t);
              } else {
                subtasks.putIfAbsent(parent, () => []).add(t);
              }
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (tags.isNotEmpty)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Pill('all',
                            selected: _filter == 'all',
                            onTap: () => setState(() => _filter = 'all')),
                        const SizedBox(width: 6),
                        for (final tag in tags) ...[
                          Pill(tag,
                              selected: _filter == tag,
                              onTap: () => setState(() => _filter = tag)),
                          const SizedBox(width: 6),
                        ],
                      ],
                    ),
                  ),
                for (final status in kStatuses) ...[
                  Builder(builder: (context) {
                    final group = mains
                        .where((t) =>
                            fmt.s(t['STATUS']).toLowerCase() == status)
                        .toList();
                    if (group.isEmpty) return const SizedBox.shrink();
                    final visible =
                        status == 'done' ? group.take(6).toList() : group;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SectionLabel('$status · ${group.length}'),
                        ...visible.map((t) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: TaskRowTile(
                                task: t,
                                subtasks: subtasks[fmt.s(t['ID'])] ?? const [],
                              ),
                            )),
                      ],
                    );
                  }),
                ],
                if (mains.isEmpty)
                  const EmptyState(
                    'No tasks on the board',
                    'Add one below, or capture from anywhere with the share sheet.',
                    icon: Icons.task_alt_rounded,
                  ),
              ],
            );
          },
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            backgroundColor: C.greenDim,
            foregroundColor: Colors.white,
            onPressed: () => showAddTaskSheet(context),
            child: const Icon(Icons.add_rounded),
          ),
        ),
      ],
    );
  }
}

/// One task row: priority dot, title, due chip, jira chip, subtask carets.
class TaskRowTile extends StatelessWidget {
  const TaskRowTile({super.key, required this.task, this.subtasks = const []});
  final Map<String, dynamic> task;
  final List<Map<String, dynamic>> subtasks;

  @override
  Widget build(BuildContext context) {
    final id = fmt.s(task['ID']);
    final status = fmt.s(task['STATUS']).toLowerCase();
    final done = status == 'done';
    final queued = id == 'QUEUED';
    final due = fmt.s(task['DUE_DATE']);
    final dueDays = fmt.daysUntil(due);
    final jira = fmt.s(task['JIRA_KEY']);

    Widget tile = Panel(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      onTap: queued
          ? null
          : () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => TaskDetailScreen(taskId: id)),
              ),
      onLongPress: queued ? null : () => _actionSheet(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: StatusDot(
                  done ? C.text3 : C.forPriority(fmt.s(task['PRIORITY'])),
                  size: 8,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  fmt.s(task['TITLE']),
                  style: T.body2.copyWith(
                    color: done ? C.text3 : C.text,
                    decoration: done ? TextDecoration.lineThrough : null,
                    decorationColor: C.text3,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (queued)
                const Badge2('queued', color: C.amberBg, textColor: C.amber)
              else if (!done)
                GestureDetector(
                  onTap: () => _complete(context),
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: C.borderMid, width: 1.5),
                    ),
                    child: const Icon(Icons.check_rounded,
                        size: 15, color: C.text3),
                  ),
                ),
            ],
          ),
          if (due.isNotEmpty || jira.isNotEmpty || fmt.s(task['TAG']).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 18, top: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (due.isNotEmpty)
                    Badge2(
                      fmt.dueLabel(due),
                      color: dueDays != null && dueDays < 0
                          ? C.redBg
                          : dueDays == 0
                              ? C.amberBg
                              : C.surface,
                      textColor: dueDays != null && dueDays < 0
                          ? C.red
                          : dueDays == 0
                              ? C.amber
                              : C.text3,
                    ),
                  if (jira.isNotEmpty)
                    Badge2(jira, color: C.cyanBg, textColor: C.cyan),
                  if (fmt.s(task['TAG']).isNotEmpty)
                    Badge2(fmt.s(task['TAG'])),
                  if (fmt.s(task['ASSIGNEE']).isNotEmpty)
                    Badge2(fmt.s(task['ASSIGNEE']),
                        color: C.surface, textColor: C.text3),
                ],
              ),
            ),
          if (subtasks.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 18, top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final sub in subtasks)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Icon(
                            fmt.s(sub['STATUS']).toLowerCase() == 'done'
                                ? Icons.check_rounded
                                : Icons.subdirectory_arrow_right_rounded,
                            size: 13,
                            color: C.text3,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              fmt.s(sub['TITLE']),
                              style: T.small.copyWith(
                                color: fmt.s(sub['STATUS']).toLowerCase() ==
                                        'done'
                                    ? C.text3
                                    : C.text2,
                                decoration:
                                    fmt.s(sub['STATUS']).toLowerCase() ==
                                            'done'
                                        ? TextDecoration.lineThrough
                                        : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );

    if (queued || done) return tile;
    return Dismissible(
      key: ValueKey('task-$id'),
      direction: DismissDirection.startToEnd,
      confirmDismiss: (_) async {
        await _complete(context);
        return false; // the optimistic patch re-renders the row instead
      },
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 18),
        decoration: BoxDecoration(
          color: C.greenBg,
          borderRadius: BorderRadius.circular(Sz.rMd),
        ),
        child: const Icon(Icons.check_circle_rounded, color: C.green),
      ),
      child: tile,
    );
  }

  Future<void> _complete(BuildContext context) async {
    HapticFeedback.mediumImpact();
    final services = AppScope.of(context);
    final target =
        fmt.s(task['JIRA_KEY']).isNotEmpty ? 'review' : 'done';
    final res = await services.mutations.completeTask(task, target: target);
    if (!context.mounted) return;
    if (!res.ok) toast(context, res.error!, error: true);
    if (res.queued) toast(context, 'Marked $target - queued for sync');
  }

  void _actionSheet(BuildContext context) {
    HapticFeedback.mediumImpact();
    final services = AppScope.of(context);
    final id = fmt.s(task['ID']);
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
            ListTile(
              dense: true,
              leading: const Icon(Icons.edit_rounded, size: 18),
              title: Text('Edit', style: T.body2),
              onTap: () {
                Navigator.pop(ctx);
                showEditTaskSheet(context, task);
              },
            ),
            for (final status in kStatuses)
              if (status != fmt.s(task['STATUS']).toLowerCase())
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.swap_horiz_rounded, size: 18),
                  title: Text('Move to $status', style: T.body2),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final res = await services.mutations.updateTask(
                        id, {'status': status},
                        label:
                            'Move ${fmt.truncate(fmt.s(task['TITLE']), 30)} -> $status');
                    if (!context.mounted) return;
                    if (!res.ok) toast(context, res.error!, error: true);
                  },
                ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.delete_outline_rounded,
                  size: 18, color: C.red),
              title: Text('Delete', style: T.body2.copyWith(color: C.red)),
              onTap: () async {
                Navigator.pop(ctx);
                final sure = await confirmDialog(
                  context,
                  'Delete task?',
                  '"${fmt.s(task['TITLE'])}" will be removed from the vault'
                      '${fmt.s(task['JIRA_KEY']).isNotEmpty ? ' and Jira (${fmt.s(task['JIRA_KEY'])})' : ''}.',
                  action: 'Delete',
                  destructive: true,
                );
                if (!sure || !context.mounted) return;
                final res = await services.mutations.deleteTask(id);
                if (!context.mounted) return;
                res.ok
                    ? toast(context, 'Deleted')
                    : toast(context, res.error!, error: true);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

Future<void> showAddTaskSheet(BuildContext context) {
  final title = TextEditingController();
  final due = TextEditingController();
  final tag = TextEditingController();
  var priority = 'medium';
  var status = 'today';
  final services = AppScope.of(context);

  return showFormSheet(
    context,
    title: 'New task',
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Field(
              label: 'Title',
              controller: title,
              hint: 'What needs doing?',
              autofocus: true),
          Segmented(
            label: 'Status',
            options: const ['today', 'next', 'waiting'],
            value: status,
            onChanged: (v) => setSheet(() => status = v),
          ),
          Segmented(
            label: 'Priority',
            options: const ['low', 'medium', 'high'],
            value: priority,
            onChanged: (v) => setSheet(() => priority = v),
          ),
          Row(
            children: [
              Expanded(
                  child: Field(
                      label: 'Due (optional)',
                      controller: due,
                      hint: 'YYYY-MM-DD')),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: OutlinedButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      firstDate: DateTime.now()
                          .subtract(const Duration(days: 1)),
                      lastDate:
                          DateTime.now().add(const Duration(days: 730)),
                    );
                    if (picked != null) due.text = fmt.isoDate(picked);
                  },
                  child: const Icon(Icons.calendar_month_rounded, size: 16),
                ),
              ),
            ],
          ),
          Field(label: 'Tag (optional)', controller: tag, hint: 'e.g. viva'),
          const SizedBox(height: 4),
          FilledButton(
            onPressed: () async {
              final text = title.text.trim();
              if (text.isEmpty) return;
              Navigator.pop(ctx);
              final res = await services.mutations.addTask(
                title: text,
                priority: priority,
                status: status,
                due: due.text.trim(),
                tag: tag.text.trim(),
              );
              if (!context.mounted) return;
              if (!res.ok) {
                toast(context, res.error!, error: true);
              } else if (res.queued) {
                toast(context, 'Task queued - will sync to the vault');
              } else {
                toast(context, 'Task added');
              }
            },
            child: const Text('Add task'),
          ),
        ],
      ),
    ),
  );
}

Future<void> showEditTaskSheet(
    BuildContext context, Map<String, dynamic> task) {
  final title = TextEditingController(text: fmt.s(task['TITLE']));
  final due = TextEditingController(text: fmt.s(task['DUE_DATE']));
  final tag = TextEditingController(text: fmt.s(task['TAG']));
  var priority = fmt.s(task['PRIORITY']).toLowerCase();
  if (!['low', 'medium', 'high'].contains(priority)) priority = 'medium';
  final services = AppScope.of(context);
  final id = fmt.s(task['ID']);

  return showFormSheet(
    context,
    title: 'Edit $id',
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Field(label: 'Title', controller: title),
          Segmented(
            label: 'Priority',
            options: const ['low', 'medium', 'high'],
            value: priority,
            onChanged: (v) => setSheet(() => priority = v),
          ),
          Field(label: 'Due', controller: due, hint: 'YYYY-MM-DD'),
          Field(label: 'Tag', controller: tag),
          const SizedBox(height: 4),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final res = await services.mutations.updateTask(
                id,
                {
                  'title': title.text.trim(),
                  'priority': priority,
                  'due_date': due.text.trim(),
                  'tag': tag.text.trim(),
                },
                label: 'Edit · ${fmt.truncate(title.text.trim(), 40)}',
              );
              if (!context.mounted) return;
              if (!res.ok) {
                toast(context, res.error!, error: true);
              } else if (res.queued) {
                toast(context, 'Edit queued - will sync to the vault');
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}
