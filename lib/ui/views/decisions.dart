import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../widgets/common.dart';

/// Decision log + risk register, from /api/decisions.
///
/// This reads the dedicated endpoint rather than the generic /api/refs it used
/// to, because the server does real work there that the phone should not
/// re-derive: which decisions are STALE (the work landed, the log still says
/// pending) and which are AGING (pending five days or more). Those two flags
/// are the whole reason to look at this view, so they lead.
///
/// Playbooks still come from /api/refs - they carry no such state.
class DecisionsView extends StatelessWidget {
  const DecisionsView({super.key});

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return SnapshotView(
      snapshot: services.store.decisions,
      builder: (context, data) {
        final map = fmt.m(data);
        final decisions = fmt.lm(map['decisions']);
        final risks = fmt.lm(map['risks']);
        final org = fmt.s(map['org']);

        final stale = decisions.where((d) => fmt.b(d['stale'])).toList();
        final aging = decisions
            .where((d) => !fmt.b(d['stale']) && fmt.i(d['aging']) > 0)
            .toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (org.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('Decision log · $org', style: T.monoSmall),
              ),

            if (stale.isNotEmpty) ...[
              const SectionLabel('Behind reality'),
              Panel(
                color: C.amberBg,
                borderColor: C.amber.withValues(alpha: 0.4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.history_toggle_off_rounded,
                            size: 15, color: C.amber),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${fmt.plural(stale.length, 'decision')} still '
                            'marked pending, but the work that cites them is done.',
                            style: T.small.copyWith(color: C.amber),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    for (final d in stale)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${fmt.s(d['id'])} · ${fmt.truncate(fmt.s(d['title']), 70)}',
                          style: T.monoSmall.copyWith(color: C.text2),
                        ),
                      ),
                  ],
                ),
              ),
            ],

            SectionLabel('Decisions · ${decisions.length}'),
            if (decisions.isEmpty)
              const EmptyState(
                'No decisions logged',
                'Decisions (D-xxx) appear here from the active org\'s '
                    'decision log in the career vault.',
                icon: Icons.gavel_rounded,
              )
            else
              ...decisions.map((d) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _DecisionTile(decision: d),
                  )),

            if (aging.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 6),
                child: Text(
                  '${fmt.plural(aging.length, 'decision')} pending five days or more.',
                  style: T.tiny.copyWith(color: C.amber),
                ),
              ),

            if (risks.isNotEmpty) ...[
              SectionLabel('Risks · ${risks.length}'),
              ...risks.map((r) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _RiskTile(risk: r),
                  )),
            ],

            // Playbooks have no server-side state, so they ride along from the
            // refs mirror and stay readable offline.
            ListenableBuilder(
              listenable: services.store.refs,
              builder: (context, _) {
                final refs = fmt.m(fmt.m(services.store.refs.value)['refs']);
                final playbooks = refs.entries
                    .where((e) => fmt.s(fmt.m(e.value)['kind']) == 'playbook')
                    .toList()
                  ..sort((a, b) => a.key.compareTo(b.key));
                if (playbooks.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SectionLabel('Playbooks · ${playbooks.length}'),
                    Panel(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (var idx = 0; idx < playbooks.length; idx++) ...[
                            if (idx > 0) const Divider(),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: Sz.pad, vertical: 10),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 52,
                                    child: Text(playbooks[idx].key,
                                        style: T.monoSmall
                                            .copyWith(color: C.cyan)),
                                  ),
                                  Expanded(
                                    child: Text(
                                        fmt.s(fmt
                                            .m(playbooks[idx].value)['title']),
                                        style: T.small),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _DecisionTile extends StatelessWidget {
  const _DecisionTile({required this.decision});
  final Map<String, dynamic> decision;

  static Color statusColor(String status) => switch (status.toLowerCase()) {
        'open' || 'pending' || 'chasing' || 'draft' => C.amber,
        'closed' || 'decided' || 'mitigated' || 'done' || 'approved' => C.green,
        'tripped' || 'critical' || 'blocked' || 'rejected' => C.red,
        _ => C.text3,
      };

  @override
  Widget build(BuildContext context) {
    final status = fmt.s(decision['status']);
    final citing = fmt.lm(decision['citing']);
    final stale = fmt.b(decision['stale']);
    final aging = fmt.i(decision['aging']);

    return Panel(
      borderColor: stale ? C.amber.withValues(alpha: 0.4) : C.border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(fmt.s(decision['id']),
                  style: T.mono.copyWith(color: C.green)),
              const SizedBox(width: 8),
              if (status.isNotEmpty)
                Badge2(status,
                    color: statusColor(status).withValues(alpha: 0.12),
                    textColor: statusColor(status)),
              const Spacer(),
              if (fmt.s(decision['date']).isNotEmpty)
                Text(fmt.shortDate(decision['date']), style: T.monoSmall),
            ],
          ),
          const SizedBox(height: 7),
          Text(fmt.s(decision['title']), style: T.body2.copyWith(color: C.text)),
          if (stale) ...[
            const SizedBox(height: 7),
            Text('Work delivered, log still pending.',
                style: T.tiny.copyWith(color: C.amber)),
          ] else if (aging > 0) ...[
            const SizedBox(height: 7),
            Text('Pending ${fmt.plural(aging, 'day')}.',
                style: T.tiny.copyWith(color: C.amber)),
          ],
          if (citing.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                for (final t in citing.take(6))
                  Badge2(fmt.s(t['id']),
                      color: fmt.s(t['status']) == 'done'
                          ? C.greenBg
                          : C.surface,
                      textColor: fmt.s(t['status']) == 'done'
                          ? C.greenBright
                          : C.text3),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _RiskTile extends StatelessWidget {
  const _RiskTile({required this.risk});
  final Map<String, dynamic> risk;

  @override
  Widget build(BuildContext context) {
    final severity = fmt.s(risk['severity']);
    final color = switch (severity.toLowerCase()) {
      'high' || 'critical' => C.red,
      'medium' || 'moderate' => C.amber,
      _ => C.text3,
    };
    final protection = fmt.s(risk['protection']);
    final evidence = fmt.s(risk['evidence']);

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(fmt.s(risk['id']), style: T.mono.copyWith(color: C.red)),
              const SizedBox(width: 8),
              if (severity.isNotEmpty)
                Badge2(severity,
                    color: color.withValues(alpha: 0.12), textColor: color),
            ],
          ),
          const SizedBox(height: 7),
          Text(fmt.s(risk['title']), style: T.body2.copyWith(color: C.text)),
          if (protection.isNotEmpty) ...[
            const SizedBox(height: 6),
            KvRow('Protection', protection),
          ],
          if (evidence.isNotEmpty) KvRow('Evidence', evidence),
        ],
      ),
    );
  }
}
