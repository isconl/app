import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
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
