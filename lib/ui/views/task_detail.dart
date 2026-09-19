import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../../util/markdown.dart';
import '../shell.dart' show ShellAppBar;
import '../widgets/common.dart';

/// Deep view of one task: effort, career context, brief, draft, Jira card.
/// Cached per task, so previously opened tasks read fully offline.
class TaskDetailScreen extends StatefulWidget {
  const TaskDetailScreen({super.key, required this.taskId});
  final String taskId;

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  bool _briefBusy = false;
  bool _draftBusy = false;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final snap = services.store.detail(
        'task', widget.taskId, '/api/tasks/detail?taskId=${widget.taskId}');
    return Scaffold(
      appBar: ShellAppBar(title: widget.taskId, showBrand: false),
      body: SnapshotView(
        snapshot: snap,
        builder: (context, data) {
          final detail = fmt.m(data);
          final task = fmt.m(detail['task']);
          final effort = fmt.m(detail['effort']);
          final tools = fmt.lm(detail['tools']);
          final brief = fmt.m(detail['brief']);
          final draft = fmt.m(detail['draft']);
          final jira = fmt.s(task['JIRA_KEY']);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(fmt.s(task['TITLE']), style: T.title),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        Badge2(fmt.s(task['STATUS']),
                            color: C.greenBg, textColor: C.greenBright),
                        Badge2(fmt.s(task['PRIORITY']),
                            color: C.surface,
                            textColor:
                                C.forPriority(fmt.s(task['PRIORITY']))),
                        if (fmt.s(task['DUE_DATE']).isNotEmpty)
                          Badge2('due ${fmt.dueLabel(task['DUE_DATE'])}'),
                        if (jira.isNotEmpty)
                          Badge2(jira, color: C.cyanBg, textColor: C.cyan),
                        if (fmt.s(task['TAG']).isNotEmpty)
                          Badge2(fmt.s(task['TAG'])),
                      ],
                    ),
                    if (fmt.s(task['WHY']).isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(fmt.s(task['WHY']),
                          style: T.small.copyWith(color: C.text3)),
                    ],
                  ],
                ),
              ),
              if (effort.isNotEmpty) ...[
                const SectionLabel('Effort'),
                Panel(
                  child: Column(
                    children: [
                      KvRow('Range', fmt.s(effort['range'])),
                      KvRow('One sitting', fmt.s(effort['sitting'])),
                    ],
                  ),
                ),
              ],
              if (tools.isNotEmpty) ...[
                const SectionLabel('Recommended tools'),
                Panel(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final tool in tools) Badge2(fmt.s(tool['label'])),
                    ],
                  ),
                ),
              ],
              const SectionLabel('Brief'),
              if (brief.isNotEmpty)
                Panel(child: _briefBody(brief))
              else
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          'No brief yet. The agent can break this task into steps.',
                          style: T.small),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _briefBusy || !services.sync.online
                            ? null
                            : () => _generate(snap, isBrief: true),
                        icon: _briefBusy
                            ? const MiniSpinner()
                            : const Icon(Icons.bolt_rounded, size: 16),
                        label: Text(services.sync.online
                            ? 'Generate brief'
                            : 'Needs connection'),
                      ),
                    ],
                  ),
                ),
              const SectionLabel('Draft'),
              if (draft.isNotEmpty)
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (fmt.s(draft['recipient']).isNotEmpty)
                        KvRow('To', fmt.s(draft['recipient'])),
                      const SizedBox(height: 6),
                      Markdown(fmt.s(draft['text']).isEmpty
                          ? fmt.s(draft['body'])
                          : fmt.s(draft['text'])),
                    ],
                  ),
                )
              else
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('No message draft for this task.', style: T.small),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _draftBusy || !services.sync.online
                            ? null
                            : () => _generate(snap, isBrief: false),
                        icon: _draftBusy
                            ? const MiniSpinner()
                            : const Icon(Icons.edit_note_rounded, size: 16),
                        label: Text(services.sync.online
                            ? 'Draft message'
                            : 'Needs connection'),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
            ],
          );
        },
      ),
    );
  }

  Widget _briefBody(Map<String, dynamic> brief) {
    final steps = fmt.l(brief['steps']);
    final done = fmt.s(brief['done']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (done.isNotEmpty) ...[
          Text('DONE MEANS', style: T.label),
          const SizedBox(height: 4),
          Text(done, style: T.body2),
          const SizedBox(height: 12),
        ],
        if (steps.isNotEmpty) ...[
          Text('STEPS', style: T.label),
          const SizedBox(height: 4),
          for (var idx = 0; idx < steps.length; idx++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 22,
                    child: Text('${idx + 1}.',
                        style: T.body2.copyWith(
                            color: C.green, fontWeight: FontWeight.w600)),
                  ),
                  Expanded(
                      child: Text(
                          fmt.s(steps[idx] is Map
                              ? (steps[idx] as Map)['text'] ?? steps[idx]
                              : steps[idx]),
                          style: T.body2)),
                ],
              ),
            ),
        ],
        if (steps.isEmpty && done.isEmpty)
          Markdown(fmt.s(brief['text']).isEmpty
              ? brief.toString()
              : fmt.s(brief['text'])),
      ],
    );
  }

  Future<void> _generate(dynamic snap, {required bool isBrief}) async {
    final services = AppScope.of(context);
    setState(() => isBrief ? _briefBusy = true : _draftBusy = true);
    try {
      await services.mutations.post(
        isBrief ? '/api/tasks/brief' : '/api/tasks/draft',
        {'taskId': widget.taskId},
      );
      await snap.refresh();
    } catch (e) {
      if (mounted) {
        toast(context, 'Generation failed: the model may be unavailable.',
            error: true);
      }
    } finally {
      if (mounted) {
        setState(() => isBrief ? _briefBusy = false : _draftBusy = false);
      }
    }
  }
}
