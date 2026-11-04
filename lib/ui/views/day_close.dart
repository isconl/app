import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../services/day_close_planner.dart';
import '../../theme.dart';
import '../../util/day_close.dart';
import '../../util/fmt.dart' as fmt;
import '../widgets/common.dart';
import '../widgets/dashboard/dashboard.dart';
import 'personal_dash_model.dart';

/// BI26100143: close the day. What got done, what is still open (carry it to
/// tomorrow, reschedule it, or drop it), and one line worth remembering. Every
/// action goes through the outbox, so it works offline. Nothing is deleted:
/// a dropped task is marked dropped.
class DayCloseScreen extends StatefulWidget {
  const DayCloseScreen({super.key});

  @override
  State<DayCloseScreen> createState() => _DayCloseScreenState();
}

class _DayCloseScreenState extends State<DayCloseScreen> {
  final _handled = <String>{};
  final _line = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _line.dispose();
    super.dispose();
  }

  Future<void> _tomorrow(Map<String, dynamic> t) async {
    final services = AppScope.of(context);
    final id = fmt.s(t['ID']);
    setState(() => _handled.add(id));
    await services.mutations.updateTask(id, {'due_date': tomorrowIso(DateTime.now()), 'status': 'next'},
        label: 'Carry to tomorrow · ${fmt.truncate(fmt.s(t['TITLE']), 30)}');
  }

  Future<void> _reschedule(Map<String, dynamic> t) async {
    final services = AppScope.of(context);
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year, now.month, now.day + 1),
      firstDate: now,
      lastDate: DateTime(now.year + 2),
    );
    if (picked == null || !mounted) return;
    final id = fmt.s(t['ID']);
    setState(() => _handled.add(id));
    await services.mutations.updateTask(id, {'due_date': fmt.isoDate(picked), 'status': 'next'},
        label: 'Reschedule · ${fmt.truncate(fmt.s(t['TITLE']), 30)}');
  }

  Future<void> _drop(Map<String, dynamic> t) async {
    final sure = await confirmDialog(context, 'Drop this task?',
        '${fmt.s(t['TITLE'])} is marked dropped today. It stays on record.',
        action: 'Drop');
    if (!sure || !mounted) return;
    final services = AppScope.of(context);
    final id = fmt.s(t['ID']);
    setState(() => _handled.add(id));
    await services.mutations.updateTask(id, {'status': 'dropped'},
        label: 'Drop · ${fmt.truncate(fmt.s(t['TITLE']), 30)}');
  }

  Future<void> _carryAll(List<Map<String, dynamic>> open) async {
    final services = AppScope.of(context);
    final ids = [for (final t in open) fmt.s(t['ID'])];
    setState(() => _handled.addAll(ids));
    for (final t in open) {
      await services.mutations.updateTask(fmt.s(t['ID']), {'due_date': tomorrowIso(DateTime.now()), 'status': 'next'},
          label: 'Carry to tomorrow · ${fmt.truncate(fmt.s(t['TITLE']), 30)}');
    }
  }

  Future<void> _close() async {
    if (_saving) return;
    setState(() => _saving = true);
    final services = AppScope.of(context);
    final text = _line.text.trim();
    if (text.isNotEmpty) await services.mutations.addJournal(body: text, tags: 'day-close');
    await DayClosePrefs.instance.update(closedOn: fmt.isoDate(DateTime.now()), db: services.db);
    replanDayClose(services);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final now = DateTime.now();
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(title: const Text('Close the day')),
      body: ListenableBuilder(
        listenable: Listenable.merge([services.store.state, services.store.dayBlock]),
        builder: (context, _) {
          final tasks = fmt.lm(fmt.m(services.store.state.value)['tasks']);
          final done = doneToday(tasks, now);
          final open = [for (final t in stillOpen(tasks, now)) if (!_handled.contains(fmt.s(t['ID']))) t];
          final blocks = blocksProgress(fmt.lm(fmt.m(services.store.dayBlock.value)['blocks']), now);
          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 40),
            children: [
              DashTile(
                label: 'Done today',
                child: Row(children: [
                  RingGauge(
                    arcs: [RingArc(blocks.done.toDouble(), C.green)],
                    total: blocks.total.toDouble(),
                    center: '${done.length}',
                    caption: 'done',
                    size: 76,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: done.isEmpty
                        ? Text('Nothing marked done today.', style: T.small.copyWith(color: C.text3))
                        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            for (final t in done.take(4))
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Text(fmt.s(t['TITLE']), style: T.small.copyWith(color: C.text), maxLines: 1, overflow: TextOverflow.ellipsis),
                              ),
                            if (done.length > 4) Text('and ${done.length - 4} more', style: T.tiny),
                          ]),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              SectionLabel('Still open · ${open.length}'),
              if (open.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('Nothing left open.', style: T.small.copyWith(color: C.text3)),
                )
              else ...[
                for (final t in open)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Panel(
                      key: ValueKey('open-${fmt.s(t['ID'])}'),
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(fmt.s(t['TITLE']), style: T.body.copyWith(color: C.text)),
                        if (fmt.s(t['DUE_DATE']).isNotEmpty && fmt.s(t['DUE_DATE']) != '-')
                          Text(fmt.dueLabel(t['DUE_DATE']), style: T.tiny),
                        const SizedBox(height: 4),
                        Wrap(spacing: 4, children: [
                          TextButton(onPressed: () => _tomorrow(t), child: const Text('Tomorrow')),
                          TextButton(onPressed: () => _reschedule(t), child: const Text('Reschedule')),
                          TextButton(onPressed: () => _drop(t), child: Text('Drop', style: T.small.copyWith(color: C.red))),
                        ]),
                      ]),
                    ),
                  ),
                FilledButton(onPressed: () => _carryAll(open), child: const Text('Carry all to tomorrow')),
              ],
              const SizedBox(height: 16),
              Field(label: 'One thing worth remembering from today', controller: _line, maxLines: 3),
              const SizedBox(height: 8),
              FilledButton(
                key: const Key('close-day'),
                onPressed: _saving ? null : _close,
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _line,
                  builder: (_, v, _) => Text(v.text.trim().isEmpty ? 'Close the day' : 'Save and close the day'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
