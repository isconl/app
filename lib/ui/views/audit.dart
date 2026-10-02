import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../widgets/common.dart';

/// The audit chain - rendered as a literal chain of dots down the left
/// edge; verified links glow green (the dashboard's signature detail).
class AuditView extends StatelessWidget {
  const AuditView({super.key});

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return SnapshotView(
      snapshot: services.store.audit,
      builder: (context, data) {
        final entries = fmt.lm(fmt.m(data)['entries']);
        if (entries.isEmpty) {
          return const EmptyState(
            'No audit entries',
            'Every externally-visible action the agent takes is logged '
                'to a hash-chained ledger.',
            icon: Icons.link_rounded,
          );
        }
        // Entries arrive newest-first. Verify linkage: entry[i].prev_hash
        // must equal entry[i+1].hash.
        final verified = <bool>[];
        for (var idx = 0; idx < entries.length; idx++) {
          if (idx == entries.length - 1) {
            verified.add(true); // oldest link has nothing local to compare
          } else {
            verified.add(fmt.s(entries[idx]['prev_hash']) ==
                fmt.s(entries[idx + 1]['hash']));
          }
        }
        final broken = verified.where((v) => !v).length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Panel(
              color: broken == 0 ? C.greenBg2 : C.redBg,
              borderColor: broken == 0
                  ? C.greenDim.withValues(alpha: 0.4)
                  : C.red.withValues(alpha: 0.4),
              child: Row(
                children: [
                  Icon(
                    broken == 0
                        ? Icons.verified_rounded
                        : Icons.link_off_rounded,
                    size: 16,
                    color: broken == 0 ? C.greenBright : C.red,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      broken == 0
                          ? 'Chain intact · ${entries.length} recent entries verified'
                          : '$broken broken link${broken == 1 ? '' : 's'} in view',
                      style: T.small,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            for (var idx = 0; idx < entries.length; idx++)
              _ChainEntry(
                entry: entries[idx],
                verified: verified[idx],
                isFirst: idx == 0,
                isLast: idx == entries.length - 1,
              ),
          ],
        );
      },
    );
  }
}

class _ChainEntry extends StatelessWidget {
  const _ChainEntry({
    required this.entry,
    required this.verified,
    required this.isFirst,
    required this.isLast,
  });

  final Map<String, dynamic> entry;
  final bool verified;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final meta = Map<String, dynamic>.from(entry)
      ..removeWhere((k, _) =>
          ['ts', 'action', 'hash', 'prev_hash'].contains(k.toLowerCase()));
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // the chain
          SizedBox(
            width: 22,
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    width: 1.5,
                    color: isFirst ? Colors.transparent : C.border,
                  ),
                ),
                StatusDot(verified ? C.green : C.red,
                    glow: verified, size: 7),
                Expanded(
                  child: Container(
                    width: 1.5,
                    color: isLast ? Colors.transparent : C.border,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Panel(
                padding: const EdgeInsets.all(11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(fmt.s(entry['action']),
                              style: T.w500(
                                  T.small.copyWith(color: C.text))),
                        ),
                        Text(fmt.ago(entry['ts']), style: T.monoSmall),
                      ],
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        meta.entries
                            .map((e) => '${e.key}=${e.value}')
                            .join('  '),
                        style: T.monoSmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      '${fmt.s(entry['hash'])} ← ${fmt.s(entry['prev_hash'])}',
                      style: T.monoSmall.copyWith(
                          fontSize: 9,
                          color: verified ? C.text3 : C.red),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
