import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../shell.dart' show SecondaryScreen;
import '../views/vitals.dart';
import 'common.dart';
import 'data_health_card.dart';

/// BI26092630: the Hub's Vitals card, after the block card. `VITALS · 92` with the score in its tone
/// colour, then up to three worst checks, or "All clear". Tapping opens the Vitals page. Where the
/// server has no `/api/vitals` yet, the old data-health card shows in its place.
class VitalsCard extends StatefulWidget {
  const VitalsCard({super.key});

  @override
  State<VitalsCard> createState() => _VitalsCardState();
}

class _VitalsCardState extends State<VitalsCard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final s = AppScope.of(context).store.vitals;
      s.hydrate().then((_) {
        if (mounted) s.refresh();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final snap = AppScope.of(context).store.vitals;
    return ListenableBuilder(
      listenable: snap,
      builder: (context, _) {
        final v = fmt.m(snap.value);
        if (v.isEmpty || v['score'] == null) {
          // No Vitals yet (404, or nothing cached): the old card, so nothing is lost.
          return const DataHealthCard();
        }
        final score = fmt.i(v['score']);
        final worst = worstChecks(v);
        return Panel(
          margin: const EdgeInsets.only(bottom: 10),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SecondaryScreen(title: 'Vitals', child: VitalsView())),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('VITALS · ', style: T.label),
                  Text('$score',
                      key: const Key('vitals-score'),
                      style: T.label.copyWith(color: vitalsToneColor(score), fontWeight: FontWeight.w700)),
                  const Spacer(),
                  const Icon(Icons.chevron_right_rounded, size: 18, color: C.text3),
                ],
              ),
              const SizedBox(height: 8),
              if (worst.isEmpty)
                Text('All clear', style: T.small.copyWith(color: C.text3))
              else
                for (final c in worst)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: StatusDot(vitalsStatusColor(fmt.s(c['status']))),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(fmt.s(c['title']), style: T.small.copyWith(color: C.text))),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(fmt.s(c['value']), style: T.monoSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}
