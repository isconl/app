import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../shell.dart' show ShellAppBar;
import '../widgets/common.dart';

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
