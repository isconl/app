import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../widgets/common.dart';

/// BI26100534: the Decisions tab of the Slate view. The rows that wait on a person, grouped by what kind of call
/// they need, read from hub's GET /api/slate/decisions (the app never talks to slate and holds no slate token).
/// Read-only in v1: answers happen in sessions. SnapshotView supplies pull to refresh, the last good data with its
/// age, and a plain error line when the load fails, so there is never a blank screen.
const _kindLabels = {
  'decision': 'Decisions',
  'hands': 'Hands',
  'ack': 'To acknowledge',
  'brainstorm': 'Brainstorms',
};

String kindLabel(String kind) => _kindLabels[kind] ?? kind;

class DecisionsView extends StatelessWidget {
  const DecisionsView({super.key});

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return SnapshotView(
      snapshot: services.store.slateDecisions,
      builder: (context, data) {
        final groups = fmt.lm(fmt.m(data)['groups']);
        if (groups.isEmpty) {
          return const EmptyState(
            'Nothing is waiting on you',
            'No row is waiting on a decision, a hands step or an acknowledgement right now.',
            icon: Icons.task_alt_rounded,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text(
                'Answers happen in sessions. This list only shows what is waiting.',
                style: TextStyle(color: C.text3, fontSize: 12.5),
              ),
            ),
            for (final g in groups) ...[
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 6),
                child: Text(
                  '${kindLabel(fmt.s(g['kind']))} · ${fmt.s(g['count'])}',
                  key: Key('decisions-group-${fmt.s(g['kind'])}'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              for (final r in fmt.lm(g['rows']))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${fmt.s(r['id'])} · ${fmt.s(r['project'])}',
                        style: const TextStyle(color: C.text3, fontSize: 12),
                      ),
                      Text(fmt.s(r['title'])),
                    ],
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}
