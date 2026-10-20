import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../data/store.dart' show Snapshot;
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../shell.dart' show ShellAppBar;
import '../widgets/common.dart';
import '../widgets/space_header.dart';

/// Corporate Engagements, from /api/corporate.
///
/// v1: one screen, every known engagement (career/_active.yaml's `orgs:`
/// registry) as a card, the active one expanded with live stats pulled
/// from scope's corporate.js aggregator (open/overdue tasks, decisions,
/// risks, people). Read-only -- status toggling and per-engagement
/// connections (Gmail/M365) are a later phase (see
/// hub/docs/corporate-engagements-plan.md §6.5).
///
/// Deliberately a generic template, not a Viva-specific screen: nothing
/// here names an org. Viva Valentia is simply the first (today, only)
/// entry in the registry this reads.
class CorporateView extends StatelessWidget {
  const CorporateView({super.key});

  static const tabLabels = ['Entities', 'Work', 'People'];

  /// BI26101815: the search finds an engagement by name or role, and any task, decision, risk or person of an engagement
  /// whose detail the app already holds, and opens the tab that holds it.
  static List<SpaceHit> hitsFor(BuildContext context) {
    final store = AppScope.of(context).store;
    final out = <SpaceHit>[];
    for (final eng in fmt.lm(fmt.m(store.corporate.value)['engagements'])) {
      final id = fmt.s(eng['id']);
      final name = fmt.s(eng['name']);
      if (name.isNotEmpty) out.add(SpaceHit(title: name, subtitle: fmt.s(eng['role']), tab: 0));
      final d = fmt.m(store.detail('corporate', id, '/api/corporate/detail?id=$id').value);
      for (final t in [...fmt.lm(d['tasks']), ...fmt.lm(d['decisions']), ...fmt.lm(d['risks'])]) {
        if (fmt.s(t['title']).isNotEmpty) out.add(SpaceHit(title: fmt.s(t['title']), subtitle: name, tab: 1));
      }
      for (final p in fmt.lm(d['people'])) {
        if (fmt.s(p['name']).isNotEmpty) out.add(SpaceHit(title: fmt.s(p['name']), subtitle: [fmt.s(p['role']), name].where((x) => x.isNotEmpty).join(' · '), tab: 2));
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return SpaceView(
      space: 'corporate',
      searchHint: 'Search corporates, tasks and people',
      hits: hitsFor,
      tabs: const [
        SpaceTab('Entities', _EntitiesTab()),
        SpaceTab('Work', _AcrossTab(work: true)),
        SpaceTab('People', _AcrossTab(work: false)),
      ],
    );
  }
}

class _EntitiesTab extends StatelessWidget {
  const _EntitiesTab();

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return SnapshotView(
      snapshot: services.store.corporate,
      builder: (context, data) {
        final map = fmt.m(data);
        final engagements = fmt.lm(map['engagements']);
        if (engagements.isEmpty) {
          return const EmptyState(
            'No engagements on record',
            'Corporate engagements appear here from the career vault '
                '(career/_active.yaml).',
            icon: Icons.apartment_rounded,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final eng in engagements)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _EngagementCard(engagement: eng),
              ),
          ],
        );
      },
    );
  }
}

/// Work (tasks, decisions and risks) or People across every engagement, one section per engagement, from each one's
/// detail (already cached for the detail screen).
class _AcrossTab extends StatelessWidget {
  const _AcrossTab({required this.work});
  final bool work;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return SnapshotView(
      snapshot: services.store.corporate,
      builder: (context, data) {
        final engagements = fmt.lm(fmt.m(data)['engagements']);
        if (engagements.isEmpty) {
          return EmptyState(work ? 'No work on record' : 'No people on record', 'Engagements appear here from the career vault.', icon: Icons.apartment_rounded);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final eng in engagements)
            _AcrossSection(
              key: ValueKey('${work ? 'work' : 'people'}-${fmt.s(eng['id'])}'),
              name: fmt.s(eng['name']),
              snapshot: services.store.detail('corporate', fmt.s(eng['id']), '/api/corporate/detail?id=${fmt.s(eng['id'])}'),
              work: work,
            ),
        ]);
      },
    );
  }
}

class _AcrossSection extends StatelessWidget {
  const _AcrossSection({super.key, required this.name, required this.snapshot, required this.work});
  final String name;
  final Snapshot snapshot;
  final bool work;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: snapshot,
      builder: (context, _) {
        final d = fmt.m(snapshot.value);
        final rows = work
            ? [
                for (final t in fmt.lm(d['tasks'])) KvRow(fmt.s(t['status']), fmt.s(t['title'])),
                for (final x in fmt.lm(d['decisions'])) KvRow(fmt.s(x['id']), fmt.s(x['title'])),
                for (final x in fmt.lm(d['risks'])) KvRow(fmt.s(x['id']), fmt.s(x['title'])),
              ]
            : [for (final p in fmt.lm(d['people'])) KvRow(fmt.s(p['role']), fmt.s(p['name']))];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SectionLabel(name),
          if (rows.isEmpty)
            Panel(child: Text(snapshot.value == null ? 'Loading…' : (work ? 'No tasks, decisions or risks.' : 'No people.'), style: T.small.copyWith(color: C.text3)))
          else
            Panel(child: Column(children: rows)),
        ]);
      },
    );
  }
}

class _EngagementCard extends StatelessWidget {
  const _EngagementCard({required this.engagement});
  final Map<String, dynamic> engagement;

  static Color statusColor(String status) => switch (status.toLowerCase()) {
        'active' => C.green,
        'prospective' => C.amber,
        'past' => C.text3,
        _ => C.text3,
      };

  @override
  Widget build(BuildContext context) {
    final status = fmt.s(engagement['status']);
    final active = fmt.b(engagement['active']);
    final stats = fmt.m(engagement['stats']);
    final color = statusColor(status);

    return Panel(
      borderColor: active ? C.cyan.withValues(alpha: 0.4) : C.border,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) =>
                CorporateDetailView(orgId: fmt.s(engagement['id']))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(fmt.s(engagement['name']),
                    style: T.w600(T.body2)),
              ),
              if (status.isNotEmpty)
                Badge2(status,
                    color: color.withValues(alpha: 0.12), textColor: color),
            ],
          ),
          if (fmt.s(engagement['role']).isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(fmt.s(engagement['role']),
                style: T.small.copyWith(color: C.text3)),
          ],
          if (active && stats.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StatChip('open tasks', fmt.i(stats['open'])),
                if (fmt.i(stats['overdue']) > 0)
                  _StatChip('overdue', fmt.i(stats['overdue']), warn: true),
                _StatChip('decisions', fmt.i(stats['decisions'])),
                if (fmt.i(stats['decisionsPending']) > 0)
                  _StatChip('pending', fmt.i(stats['decisionsPending']),
                      warn: true),
                _StatChip('risks', fmt.i(stats['risks'])),
                _StatChip('people', fmt.i(stats['people'])),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip(this.label, this.value, {this.warn = false});
  final String label;
  final int value;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final color = warn ? C.amber : C.text3;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: warn ? C.amberBg : C.surface,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text('$value $label',
          style: T.monoSmall.copyWith(color: warn ? C.amber : color)),
    );
  }
}

/// One engagement, in full -- BC26082007. Parameterized by org id, nothing
/// here names a specific org. Fetched via /api/corporate/detail?id=.
///
/// **Scope note:** the connections panel and status control below are
/// deliberately read-only/informational in this pass. The plan doc
/// (§6.4 vs §6.5) splits this UI (Phase 4) from the write paths that would
/// back a real connect/disconnect or status-toggle action (Phase 5,
/// `corporate/status` + `corporate/connect` -- neither endpoint exists
/// yet, confirmed 21 Aug: `scope/lib/corporate.js` is explicitly
/// read-only by its own header comment). Shipping a button that looks
/// interactive but silently does nothing would be worse than not shipping
/// it -- Phase 5 wires these controls up for real.
class CorporateDetailView extends StatelessWidget {
  const CorporateDetailView({super.key, required this.orgId});
  final String orgId;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final snap = services.store
        .detail('corporate', orgId, '/api/corporate/detail?id=$orgId');
    return Scaffold(
      appBar: ShellAppBar(title: orgId, showBrand: false),
      body: SnapshotView(
        snapshot: snap,
        builder: (context, data) {
          final eng = fmt.m(data);
          final active = fmt.b(eng['active']);
          final status = fmt.s(eng['status']);
          final stats = fmt.m(eng['stats']);
          final people = fmt.lm(eng['people']);
          final decisions = fmt.lm(eng['decisions']);
          final risks = fmt.lm(eng['risks']);
          final tasks = fmt.lm(eng['tasks']);
          final doctrine = fmt.m(eng['doctrine']);
          final always = fmt.l(doctrine['always']);
          final never = fmt.l(doctrine['never']);
          final note = fmt.s(eng['note']);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(fmt.s(eng['name']), style: T.title),
                    if (fmt.s(eng['role']).isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(fmt.s(eng['role']),
                          style: T.small.copyWith(color: C.text3)),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (status.isNotEmpty)
                          Badge2(status,
                              color: _EngagementCard.statusColor(status)
                                  .withValues(alpha: 0.12),
                              textColor:
                                  _EngagementCard.statusColor(status)),
                      ],
                    ),
                  ],
                ),
              ),
              if (!active && note.isNotEmpty)
                Panel(
                  child: Text(note, style: T.small.copyWith(color: C.text3)),
                ),
              if (active && stats.isNotEmpty) ...[
                const SectionLabel('Stats'),
                Panel(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _StatChip('open tasks', fmt.i(stats['open'])),
                      if (fmt.i(stats['overdue']) > 0)
                        _StatChip('overdue', fmt.i(stats['overdue']),
                            warn: true),
                      _StatChip('decisions', fmt.i(stats['decisions'])),
                      if (fmt.i(stats['decisionsPending']) > 0)
                        _StatChip('pending', fmt.i(stats['decisionsPending']),
                            warn: true),
                      _StatChip('risks', fmt.i(stats['risks'])),
                      _StatChip('people', fmt.i(stats['people'])),
                    ],
                  ),
                ),
              ],
              if (tasks.isNotEmpty) ...[
                const SectionLabel('Tasks'),
                Panel(
                  child: Column(
                    children: [
                      for (final t in tasks)
                        KvRow(fmt.s(t['status']), fmt.s(t['title'])),
                    ],
                  ),
                ),
              ],
              if (people.isNotEmpty) ...[
                const SectionLabel('People'),
                Panel(
                  child: Column(
                    children: [
                      for (final p in people)
                        KvRow(fmt.s(p['role']), fmt.s(p['name'])),
                    ],
                  ),
                ),
              ],
              if (decisions.isNotEmpty || risks.isNotEmpty) ...[
                const SectionLabel('Decisions & risks'),
                Panel(
                  child: Column(
                    children: [
                      for (final d in decisions)
                        KvRow(fmt.s(d['id']), fmt.s(d['title'])),
                      for (final r in risks)
                        KvRow(fmt.s(r['id']), fmt.s(r['title'])),
                    ],
                  ),
                ),
              ],
              if (always.isNotEmpty || never.isNotEmpty) ...[
                const SectionLabel('Doctrine'),
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final a in always)
                        Text('✓ ${fmt.s(a)}',
                            style: T.small.copyWith(color: C.green)),
                      for (final n in never)
                        Text('✗ ${fmt.s(n)}',
                            style: T.small.copyWith(color: C.red)),
                    ],
                  ),
                ),
              ],
              const SectionLabel('Connections'),
              const Panel(
                child: _ConnectionsPanel(),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Read-only per the class-level note above -- Gmail/M365/Jira wiring
/// status has no backend yet (Phase 5), so this shows the three services
/// as not-yet-connected rather than faking live data or a button with
/// nothing behind it.
class _ConnectionsPanel extends StatelessWidget {
  const _ConnectionsPanel();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        KvRow('Gmail', 'Not connected'),
        KvRow('Microsoft 365', 'Not connected'),
        KvRow('Jira', 'Not connected'),
        SizedBox(height: 6),
        Text('Connecting a service is not available yet.',
            style: TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}
