import 'package:flutter/material.dart';

import '../widgets/space_header.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../widgets/common.dart';
import '../widgets/compass_home.dart';
import '../widgets/compass_reviews.dart';
import '../widgets/cycle_gauge.dart';
import '../widgets/parity3b_widgets.dart';
import '../widgets/plan_actions.dart';

/// Goals by horizon, with their linked tasks.
class PlanningView extends StatefulWidget {
  const PlanningView({super.key});

  @override
  State<PlanningView> createState() => _PlanningViewState();
}

/// Horizons in the order the Compass home shows them, shortest first.
const planningHorizons = ['sprint', 'cycle', 'quarter', 'year', '5y', 'decade'];

/// Goals grouped by horizon in [planningHorizons] order; unknown horizons go last, in the order met.
List<({String horizon, List<Map<String, dynamic>> plans})> plansByHorizon(List<Map<String, dynamic>> plans) {
  final by = <String, List<Map<String, dynamic>>>{};
  for (final plan in plans) {
    by.putIfAbsent(fmt.s(plan['HORIZON']).toLowerCase(), () => []).add(plan);
  }
  final keys = by.keys.toList()
    ..sort((a, b) {
      final ia = planningHorizons.indexOf(a);
      final ib = planningHorizons.indexOf(b);
      return (ia < 0 ? 99 : ia).compareTo(ib < 0 ? 99 : ib);
    });
  return [for (final k in keys) (horizon: k, plans: by[k]!)];
}

/// BI26101814: Compass is Now, Next and Later. Now holds the current cycle (the focus cards, the review and the sprint
/// and cycle goals), Next the quarter and year goals with the strategy read, Later the five-year, decade and any other
/// horizon. Nothing the old Focus, Horizons and Review parts showed is gone.
const compassTabs = ['Now', 'Next', 'Later'];

/// Which tab a horizon belongs to: 0 Now, 1 Next, 2 Later (unknown and undated horizons are Later).
int compassTabOf(String horizon) => switch (horizon.toLowerCase()) {
      'sprint' || 'cycle' => 0,
      'quarter' || 'year' => 1,
      _ => 2,
    };

/// The Compass search hits, for the shared header and its tests.
List<SpaceHit> compassHits(BuildContext context) => _PlanningViewState.hitsFor(context);

class _PlanningViewState extends State<PlanningView> {
  static const _horizons = planningHorizons;

  /// BI26101814: the search finds a goal or one of its tasks and sends Compass to the tab that holds it.
  static List<SpaceHit> hitsFor(BuildContext context) {
    final plans = fmt.lm(fmt.m(AppScope.of(context).store.plans.value)['plans']);
    return [
      for (final p in plans)
        if (fmt.s(p['TITLE']).isNotEmpty) ...[
          SpaceHit(title: fmt.s(p['TITLE']), subtitle: [fmt.s(p['HORIZON']), fmt.s(p['STATUS'])].where((x) => x.isNotEmpty).join(' · '), tab: compassTabOf(fmt.s(p['HORIZON']))),
          for (final t in fmt.lm(p['tasks']))
            if (fmt.s(t['TITLE']).isNotEmpty) SpaceHit(title: fmt.s(t['TITLE']), subtitle: 'task of ${fmt.s(p['TITLE'])}', tab: compassTabOf(fmt.s(p['HORIZON']))),
        ],
    ];
  }

  Widget _goals(BuildContext context, List<Map<String, dynamic>> plans, int tab, {String? empty}) {
    final groups = [for (final g in plansByHorizon(plans)) if (compassTabOf(g.horizon) == tab) g];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (groups.isEmpty && empty != null) EmptyState('No plans here', empty, icon: Icons.flag_rounded),
      for (final g in groups)
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: Key('horizon-${g.horizon}'),
            tilePadding: EdgeInsets.zero,
            // Sprint and cycle open, the longer horizons collapsed.
            initiallyExpanded: g.horizon == 'sprint' || g.horizon == 'cycle',
            title: Text('${g.horizon}  \u00B7  ${g.plans.length}', style: T.label),
            children: [for (final plan in g.plans) Padding(padding: const EdgeInsets.only(bottom: 8), child: _PlanTile(plan: plan))],
          ),
        ),
    ]);
  }

  Widget _tab(BuildContext context, Widget Function(List<Map<String, dynamic>> plans) body) {
    return SnapshotView(
      snapshot: AppScope.of(context).store.plans,
      builder: (context, data) => body(fmt.lm(fmt.m(data)['plans'])),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SpaceView(
          space: 'compass',
          searchHint: 'Search goals and plans',
          hits: hitsFor,
          tabs: [
            SpaceTab(
              compassTabs[0],
              _tab(context, (plans) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const CompassFocus(),
                    const SizedBox(height: 12),
                    const CycleGaugeCard(),
                    const AdherenceCard(),
                    const CompassReviews(),
                    _goals(context, plans, 0),
                  ])),
            ),
            SpaceTab(
              compassTabs[1],
              _tab(context, (plans) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if (plans.isEmpty)
                      const EmptyState('No plans yet', 'Set a goal per horizon - cycle, sprint, year - and the agent helps distill it into tasks.', icon: Icons.flag_rounded)
                    else ...[const StrategyRead(), const SizedBox(height: 8)],
                    _goals(context, plans, 1),
                  ])),
            ),
            SpaceTab(compassTabs[2], _tab(context, (plans) => _goals(context, plans, 2, empty: 'Five-year and decade goals appear here.'))),
          ],
        ),
        ViewFab(
          tooltip: 'Add a plan',
          icon: Icons.add_rounded,
          onPressed: () => _addSheet(context),
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
          const SizedBox(height: 8),
          PlanActions(plan: plan),
        ],
      ),
    );
  }
}
