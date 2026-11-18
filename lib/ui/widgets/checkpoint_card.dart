import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../shell.dart' show openNavRoute;
import 'common.dart';

/// BI26092624: the web's checkpoint on the mobile Hub, between the date block and the ring console.
/// The copy (label, heading, subhead, status) comes from `GET /api/checkpoint`; nothing is composed
/// here but the layout. The snapshot is cached, so it shows offline. With no cache and no endpoint
/// the section is not drawn at all.
class CheckpointCard extends StatefulWidget {
  const CheckpointCard({super.key});

  @override
  State<CheckpointCard> createState() => _CheckpointCardState();
}

class _CheckpointCardState extends State<CheckpointCard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final s = AppScope.of(context).store.checkpoint;
      s.hydrate().then((_) {
        if (mounted) s.refresh();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final snap = AppScope.of(context).store.checkpoint;
    return ListenableBuilder(
      listenable: snap,
      builder: (context, _) {
        final v = fmt.m(snap.value);
        final heading = fmt.s(v['heading']);
        if (heading.isEmpty) return const SizedBox.shrink();
        final route = fmt.s(v['route']);
        final subhead = fmt.s(v['subhead']);
        final status = fmt.s(v['status']);
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Panel(
            padding: EdgeInsets.zero,
            // BI26100541: a faint green wash for contrast (about 9% green over the panel).
            color: Color.alphaBlend(C.green.withValues(alpha: 0.09), C.panel),
            onTap: route.isEmpty ? null : () => openNavRoute(context, route),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(key: const Key('checkpoint-edge'), width: 3, color: C.green),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(Sz.pad),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            fmt.s(v['label']).toUpperCase(),
                            key: const Key('checkpoint-label'),
                            style: T.small.copyWith(letterSpacing: 1.2, color: C.greenBright, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            heading,
                            key: const Key('checkpoint-heading'),
                            style: T.title.copyWith(fontWeight: FontWeight.w600, color: C.text),
                          ),
                          if (subhead.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              subhead,
                              key: const Key('checkpoint-subhead'),
                              style: T.body2.copyWith(fontWeight: FontWeight.w400, color: C.text2),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          if (status.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(status, key: const Key('checkpoint-status'), style: T.statusMono),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
