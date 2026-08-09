import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../widgets/common.dart';

/// Goals by horizon, with their linked tasks.
class PlanningView extends StatelessWidget {
  const PlanningView({super.key});

  static const _horizons = [
    'cycle', 'sprint', 'quarter', 'year', '5y', 'decade'
  ];

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return Stack(
      children: [
        SnapshotView(
          snapshot: services.store.plans,
          builder: (context, data) {
            final plans = fmt.lm(fmt.m(data)['plans']);
            if (plans.isEmpty) {
              return const EmptyState(
                'No plans yet',
                'Set a goal per horizon - cycle, sprint, year - and the '
                    'agent helps distill it into tasks.',
                icon: Icons.flag_rounded,
              );
            }
            final byHorizon = <String, List<Map<String, dynamic>>>{};
            for (final plan in plans) {
              byHorizon
                  .putIfAbsent(
                      fmt.s(plan['HORIZON']).toLowerCase(), () => [])
                  .add(plan);
            }
            final keys = byHorizon.keys.toList()
              ..sort((a, b) {
                final ia = _horizons.indexOf(a);
                final ib = _horizons.indexOf(b);
                return (ia < 0 ? 99 : ia).compareTo(ib < 0 ? 99 : ib);
              });
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final horizon in keys) ...[
                  SectionLabel(horizon),
                  for (final plan in byHorizon[horizon]!)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _PlanTile(plan: plan),
                    ),
                ],
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
            onPressed: () => _addSheet(context),
            child: const Icon(Icons.add_rounded),
          ),
        ),
      ],
    );
  }

  Future<void> _addSheet(BuildContext context) {
    final title = TextEditingController();
    final note = TextEditingController();
    var horizon = 'cycle';
    final services = AppScope.of(context);
    return showFormSheet(
      context,
      title: 'New goal',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Field(label: 'Goal', controller: title, autofocus: true),
            Segmented(
              label: 'Horizon',
              options: _horizons,
              value: horizon,
              onChanged: (v) => setSheet(() => horizon = v),
            ),
            Field(label: 'Note (optional)', controller: note, maxLines: 3),
            FilledButton(
              onPressed: () async {
                if (title.text.trim().isEmpty) return;
                Navigator.pop(ctx);
                final res = await services.mutations.addPlan(
                  title: title.text.trim(),
                  horizon: horizon,
                  note: note.text.trim(),
                );
                if (!context.mounted) return;
                if (!res.ok) {
                  toast(context, res.error!, error: true);
                } else if (res.queued) {
                  toast(context, 'Goal queued - will sync');
                }
              },
              child: const Text('Add goal'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({required this.plan});
  final Map<String, dynamic> plan;

  @override
  Widget build(BuildContext context) {
    final tasks = fmt.lm(plan['tasks']);
    final done = tasks
        .where((t) => fmt.s(t['STATUS']).toLowerCase() == 'done')
        .length;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text(fmt.s(plan['TITLE']), style: T.w500(T.body2))),
              if (fmt.s(plan['STATUS']).isNotEmpty)
                Badge2(fmt.s(plan['STATUS']),
                    color: C.greenBg, textColor: C.greenBright),
            ],
          ),
          if (tasks.isNotEmpty) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                  value: tasks.isEmpty ? 0 : done / tasks.length,
                  minHeight: 4),
            ),
            const SizedBox(height: 6),
            Text('$done of ${tasks.length} tasks done', style: T.monoSmall),
            const SizedBox(height: 4),
            for (final task in tasks.take(4))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Icon(
                      fmt.s(task['STATUS']).toLowerCase() == 'done'
                          ? Icons.check_rounded
                          : Icons.circle_outlined,
                      size: 12,
                      color: fmt.s(task['STATUS']).toLowerCase() == 'done'
                          ? C.green
                          : C.text3,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        fmt.s(task['TITLE']),
                        style: T.small.copyWith(
                          color:
                              fmt.s(task['STATUS']).toLowerCase() == 'done'
                                  ? C.text3
                                  : C.text2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (fmt.s(plan['NOTE']).isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(fmt.s(plan['NOTE']),
                style: T.small.copyWith(color: C.text3),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    );
  }
}
