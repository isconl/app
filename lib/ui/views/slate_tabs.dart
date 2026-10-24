import 'package:flutter/material.dart';
import 'package:slate_ui/slate_ui.dart';

import '../../app_scope.dart';
import '../../services/slate_agents.dart';
import '../widgets/machines_card.dart';
import 'backlog.dart';
import 'tasks.dart';

/// BS26102104: slate on the phone as three tabs. Overview is the dashboard (today, sessions, machines and their jobs,
/// alerts), Grid is the projects-by-type table with each cell opening its rows, and Asks is everything waiting on Sconl.
/// Writes go through the hub with the user's own session; nothing here holds a slate token.

/// Alerts the Overview raises from what slate reports. Pure, so it is testable.
List<String> overviewAlerts(List<AgentMachine> machines, List<SessionInfo> sessions, DateTime now) => [
      for (final m in machines)
        if (m.status == 'offline') '${m.hostname} is offline (${heardLine(m.ageSecs)})',
      for (final m in machines)
        for (final j in m.jobs)
          if (j.stalled) 'Job ${j.title} on ${m.hostname} looks stalled',
      for (final s in sessions)
        if (s.isStalled(now)) 'Session ${s.id} has been silent for ${s.age(now).inMinutes} minutes',
    ];

/// `40%` or `40` to 0.4; null when the text carries no percentage.
double? progressFraction(String text) {
  final m = RegExp(r'(\d{1,3})(?:\.\d+)?\s*%?').firstMatch(text);
  if (m == null) return null;
  final v = int.parse(m.group(1)!);
  return v > 100 ? null : v / 100;
}

class SlateOverviewTab extends StatelessWidget {
  const SlateOverviewTab({super.key, required this.client, required this.agents, required this.commandStepUp, required this.writeStepUp, this.clock});
  final SlateClient client;
  final AgentsApi? agents;
  final StepUp commandStepUp;
  final WriteStepUp writeStepUp;
  final DateTime Function()? clock;

  Future<(TodayData, List<SessionInfo>, List<AgentMachine>)> _load(BuildContext context) async {
    final machinesApi = agents ?? HubAgentsApi(AppScope.of(context).api);
    final today = await client.today();
    final sessions = await client.sessions().catchError((_) => <SessionInfo>[]);
    final machines = await machinesApi.machines().catchError((_) => <AgentMachine>[]);
    return (today, sessions, machines);
  }

  @override
  Widget build(BuildContext context) => _Load<(TodayData, List<SessionInfo>, List<AgentMachine>)>(
        load: () => _load(context),
        builder: (context, data, reload) {
          final t = SlateTokens.of(context);
          final (today, sessions, machines) = data;
          final now = (clock ?? DateTime.now)();
          final alerts = overviewAlerts(machines, sessions, now);
          final live = sessions.where((s) => !s.isIdle(now)).toList();
          final onlineMachines = machines.where((m) => !m.offline).length;
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Today: ${today.closedToday} closed against a ${today.weeklyDailyAverage.toStringAsFixed(1)} a day average, ${today.inFlight} in flight.',
                  key: const Key('overview-today'),
                  style: TextStyle(color: today.belowPace ? t.warn : t.text2, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text('${live.length} sessions live · $onlineMachines of ${machines.length} machines online', key: const Key('overview-counts'), style: TextStyle(color: t.text3, fontSize: 12)),
                const SizedBox(height: 12),
                if (alerts.isNotEmpty) ...[
                  Text('Alerts', style: TextStyle(color: t.danger, fontSize: 14, fontWeight: FontWeight.w700)),
                  for (final a in alerts) Padding(key: Key('alert-$a'), padding: const EdgeInsets.only(top: 4), child: Text(a, style: TextStyle(color: t.text, fontSize: 13))),
                  const SizedBox(height: 12),
                ] else
                  Text('No alerts', key: const Key('overview-no-alerts'), style: TextStyle(color: t.text3, fontSize: 12)),
                MachinesCard(api: agents),
                for (final m in machines)
                  for (final j in m.jobs)
                    if (progressFraction(j.progress) != null)
                      Padding(
                        key: Key('bar-${m.hostname}-${j.id}'),
                        padding: const EdgeInsets.only(top: 8),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${j.title} · ${m.hostname}', style: TextStyle(color: t.text2, fontSize: 12)),
                          const SizedBox(height: 4),
                          LinearProgressIndicator(value: progressFraction(j.progress)),
                        ]),
                      ),
                const SizedBox(height: 16),
                Text('Today\'s goals are set by the orchestrator and are not served to the phone yet.', key: const Key('overview-goals-note'), style: TextStyle(color: t.text3, fontSize: 12)),
                const SizedBox(height: 12),
                Wrap(spacing: 8, children: [
                  OutlinedButton(key: const Key('open-command'), onPressed: () => _push(context, 'Command', SlateHome(client: client, commandStepUp: commandStepUp, writeStepUp: writeStepUp)), child: const Text('Sessions and commands')),
                  OutlinedButton(key: const Key('open-tasks'), onPressed: () => _push(context, 'Tasks', const TasksView()), child: const Text('Tasks')),
                  OutlinedButton(key: const Key('open-register'), onPressed: () => _push(context, 'Register', const BacklogView()), child: const Text('Register')),
                ]),
              ],
            ),
          );
        },
      );

  static void _push(BuildContext context, String title, Widget body) =>
      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => Scaffold(appBar: AppBar(title: Text(title)), body: body)));
}

/// Grid: the same table plan sessions use. Tap a cell (or a project's total) to see those rows.
class SlateGridTab extends StatelessWidget {
  const SlateGridTab({super.key, required this.client, required this.writeStepUp});
  final SlateClient client;
  final WriteStepUp writeStepUp;

  @override
  Widget build(BuildContext context) => _Load<MatrixData>(
        load: client.matrix,
        builder: (context, m, reload) {
          final t = SlateTokens.of(context);
          final head = TextStyle(color: t.text3, fontSize: 11, fontWeight: FontWeight.w600);
          final cell = TextStyle(color: t.text, fontSize: 12);
          DataCell tap(String project, String? type, int n) => DataCell(
                Text('$n', style: cell),
                onTap: n == 0 ? null : () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => GridRowsScreen(client: client, stepUp: writeStepUp, project: project, type: type))),
              );
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    key: const Key('grid-table'),
                    columnSpacing: 18,
                    columns: [
                      DataColumn(label: Text('project', style: head)),
                      for (final ty in m.types) DataColumn(label: Text(ty, style: head), numeric: true),
                      DataColumn(label: Text('total', style: head), numeric: true),
                    ],
                    rows: [
                      for (final p in m.projects)
                        DataRow(cells: [
                          DataCell(Text(p, style: cell)),
                          for (final ty in m.types) tap(p, ty, m.count(p, ty)),
                          tap(p, null, m.projectTotal(p)),
                        ]),
                      DataRow(cells: [
                        DataCell(Text('all', style: head)),
                        for (final ty in m.types) DataCell(Text('${m.typeTotal(ty)}', style: head)),
                        DataCell(Text('${m.total}', style: head)),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
}

/// The rows behind one grid cell (a project and a type, or a project's whole total).
class GridRowsScreen extends StatelessWidget {
  const GridRowsScreen({super.key, required this.client, required this.stepUp, required this.project, this.type});
  final SlateClient client;
  final WriteStepUp stepUp;
  final String project;
  final String? type;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('$project${type == null ? '' : ' · $type'}')),
        body: _Load<List<RowSummary>>(
          load: () => client.rows(type: type, project: project),
          builder: (context, rows, reload) => RefreshIndicator(
            onRefresh: reload,
            child: ListView(
              key: const Key('grid-rows'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                for (final r in rows)
                  _Tile(
                    id: r.id,
                    title: r.title,
                    meta: '${r.type} · ${r.status}',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => RowDetailScreen(client: client, stepUp: stepUp, id: r.id, project: r.project),
                    )),
                  ),
              ],
            ),
          ),
        ),
      );
}

enum AsksSection { decisions, activities, blockers, approvals }

/// Asks: everything waiting on Sconl. Decisions are answered on the decision screen; manual activities open as rows with
/// their step guide; blockers are cleared with evidence; runbook approvals have no route yet and say so.
class SlateAsksTab extends StatefulWidget {
  const SlateAsksTab({super.key, required this.client, required this.writeStepUp});
  final SlateClient client;
  final WriteStepUp writeStepUp;

  @override
  State<SlateAsksTab> createState() => _SlateAsksTabState();
}

class _SlateAsksTabState extends State<SlateAsksTab> {
  AsksSection _s = AsksSection.decisions;

  static String label(AsksSection s) => switch (s) {
        AsksSection.decisions => 'Decisions',
        AsksSection.activities => 'Activities',
        AsksSection.blockers => 'Blockers',
        AsksSection.approvals => 'Approvals',
      };

  @override
  Widget build(BuildContext context) {
    final c = widget.client, w = widget.writeStepUp;
    return Column(children: [
      SizedBox(
        height: 44,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            for (final s in AsksSection.values)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(key: Key('asks-${s.name}'), label: Text(label(s)), selected: _s == s, onSelected: (_) => setState(() => _s = s)),
              ),
          ]),
        ),
      ),
      Expanded(
        child: switch (_s) {
          AsksSection.decisions => DecisionsView(client: c, stepUp: w),
          AsksSection.activities => _Activities(client: c, stepUp: w),
          AsksSection.blockers => BlockersView(client: c, stepUp: w),
          AsksSection.approvals => const _Approvals(),
        },
      ),
    ]);
  }
}

class _Activities extends StatelessWidget {
  const _Activities({required this.client, required this.stepUp});
  final SlateClient client;
  final WriteStepUp stepUp;

  @override
  Widget build(BuildContext context) => _Load<List<RowSummary>>(
        load: () => client.rows(type: 'manual'),
        builder: (context, rows, reload) => RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            key: const Key('asks-activities-list'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Text('${rows.length} manual activities', style: TextStyle(color: SlateTokens.of(context).text2, fontSize: 12)),
              const SizedBox(height: 8),
              for (var i = 0; i < rows.length; i++)
                _Tile(
                  id: 'Activity ${i + 1} of ${rows.length}: ${rows[i].id}',
                  title: rows[i].title,
                  meta: rows[i].project,
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => RowDetailScreen(client: client, stepUp: stepUp, id: rows[i].id, project: rows[i].project),
                    ));
                    reload();
                  },
                ),
            ],
          ),
        ),
      );
}

class _Approvals extends StatelessWidget {
  const _Approvals();
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text('No runbook approvals yet. They appear here when slate serves them (BS26102102).',
              key: const Key('asks-approvals-empty'), textAlign: TextAlign.center, style: TextStyle(color: SlateTokens.of(context).text3)),
        ),
      );
}

/// Loads once, offers pull to refresh, and says plainly when slate did not answer.
class _Load<T> extends StatefulWidget {
  const _Load({required this.load, required this.builder});
  final Future<T> Function() load;
  final Widget Function(BuildContext, T, Future<void> Function()) builder;
  @override
  State<_Load<T>> createState() => _LoadState<T>();
}

class _LoadState<T> extends State<_Load<T>> {
  T? _data;
  Object? _error;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final d = await widget.load();
      if (mounted) setState(() { _data = d; _error = null; _done = true; });
    } catch (e) {
      if (mounted) setState(() { _error = e; _done = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_done) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text('Could not reach slate.', style: TextStyle(color: SlateTokens.of(context).danger)));
    return widget.builder(context, _data as T, _reload);
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.id, required this.title, required this.meta, this.onTap});
  final String id, title, meta;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final t = SlateTokens.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(id, style: TextStyle(color: t.text3, fontSize: 11)),
          Text(title, style: TextStyle(color: t.text, fontSize: 14)),
          Text(meta, style: TextStyle(color: t.text3, fontSize: 11)),
        ]),
      ),
    );
  }
}
