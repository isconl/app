import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import 'common.dart';

/// The chat rail's "Context" tab: today's habit pulse plus the single most
/// urgent open task, at a glance while the rail is parked in Chat or Reader
/// mode. Ported from dashboard/app.js's renderRailContext() (~6407-6489) --
/// same two numbers (habit completion, active-priority task), rebuilt as
/// plain Flutter widgets on this app's own design system rather than the
/// legacy dashboard's animated "quantum radar" SVG/CSS, which is decorative
/// chrome specific to that codebase, not part of the underlying behaviour.
class ContextPanel extends StatefulWidget {
  const ContextPanel({super.key});

  @override
  State<ContextPanel> createState() => _ContextPanelState();
}

class _ContextPanelState extends State<ContextPanel> {
  @override
  void initState() {
    super.initState();
    // Neither snapshot is guaranteed hydrated yet -- the rail can be the
    // first thing on screen, before HubView/RhythmView ever mount.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final services = AppScope.of(context);
      services.store.state.hydrate().then((_) {
        if (mounted) services.store.state.refresh();
      });
      services.store.rhythm.hydrate().then((_) {
        if (mounted) services.store.rhythm.refresh();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([services.store.state, services.store.rhythm]),
      builder: (context, _) {
        final state = fmt.m(services.store.state.value);
        final tasks = fmt.lm(state['tasks']);
        final open = tasks
            .where((t) => fmt.s(t['STATUS']).toLowerCase() != 'done')
            .toList();
        final critical =
            open.where((t) => fmt.s(t['PRIORITY']).toLowerCase() == 'critical');
        final high =
            open.where((t) => fmt.s(t['PRIORITY']).toLowerCase() == 'high');
        final isCritical = critical.isNotEmpty;
        final top = critical.isNotEmpty
            ? critical.first
            : high.isNotEmpty
                ? high.first
                : open.isNotEmpty
                    ? open.first
                    : const <String, dynamic>{};

        final rhythm = fmt.m(services.store.rhythm.value);
        final habits = fmt.lm(rhythm['habits']);
        final logs = fmt.m(rhythm['logs']);
        final todayLog = fmt.m(logs[fmt.isoDate(DateTime.now())]);
        final doneToday =
            habits.where((h) => fmt.b(todayLog[fmt.s(h['id'])])).length;
        final habitPct =
            habits.isEmpty ? 0 : (doneToday * 100 / habits.length).round();

        return ListView(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
          children: [
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const SectionLabel('Execution pulse'),
                      const Spacer(),
                      if (isCritical)
                        const Badge2('CRITICAL',
                            color: C.redBg, textColor: C.red),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('$habitPct%',
                          style: T.headline.copyWith(
                              color: isCritical ? C.red : C.greenBright)),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                            '$doneToday / ${habits.length} habits today',
                            style: T.monoSmall),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SectionLabel(
                          isCritical ? 'Critical vector' : 'Active priority'),
                      const Spacer(),
                      if (top.isNotEmpty)
                        Badge2(
                          fmt.s(top['PRIORITY']).isEmpty
                              ? 'normal'
                              : fmt.s(top['PRIORITY']),
                          color: isCritical ? C.redBg : C.greenBg,
                          textColor: isCritical ? C.red : C.greenBright,
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    top.isEmpty
                        ? 'Queue clear — no active vectors'
                        : fmt.s(top['TITLE']),
                    style: T.w600(T.body2.copyWith(color: C.text)),
                  ),
                  if (top.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    KvRow('Status', fmt.s(top['STATUS']).isEmpty ? 'idle' : fmt.s(top['STATUS'])),
                    KvRow(
                        'Due',
                        fmt.s(top['DUE_DATE']).isEmpty
                            ? 'no target date'
                            : fmt.dueLabel(top['DUE_DATE'])),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
