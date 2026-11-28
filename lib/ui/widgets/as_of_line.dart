import 'package:flutter/material.dart';

import '../../data/store.dart';
import '../../theme.dart';
import '../../util/freshness.dart';

/// BI26101521: the quiet "as of 20:31" at the bottom-right of a Hub card. Amber, with the reason, past the card's
/// freshness budget or when the data's own date shows a stale source. A tap refreshes the data.
///
/// [AsOfText] takes a fetch time directly, for a card that keeps its own data; [AsOfLine] reads a cached
/// [Snapshot] and refreshes it on a tap.
class AsOfText extends StatelessWidget {
  const AsOfText({super.key, required this.snapshotKey, required this.fetchedAt, this.sourceDate, this.onTap, this.now});

  /// The budget key (`day`, `checkpoint`, ...).
  final String snapshotKey;
  final DateTime? fetchedAt;

  /// The data's own date, when the payload carries one.
  final DateTime? sourceDate;
  final VoidCallback? onTap;

  /// For tests.
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    final line = asOfFor(key: snapshotKey, fetchedAt: fetchedAt, sourceDate: sourceDate, now: (now ?? DateTime.now)());
    if (line == null) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerRight,
      child: InkWell(
        key: Key('as-of-$snapshotKey'),
        borderRadius: BorderRadius.circular(Sz.rSm),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 2, 2),
          child: Text(line.text, style: T.tiny.copyWith(color: line.stale ? C.amber : C.text3)),
        ),
      ),
    );
  }
}

class AsOfLine extends StatelessWidget {
  const AsOfLine({super.key, required this.snapshot, required this.snapshotKey, this.sourceDate, this.now});

  final Snapshot snapshot;
  final String snapshotKey;
  final DateTime? sourceDate;
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: snapshot,
      builder: (context, _) => AsOfText(
        snapshotKey: snapshotKey,
        fetchedAt: snapshot.fetchedAt,
        sourceDate: sourceDate,
        onTap: () => snapshot.refresh(),
        now: now,
      ),
    );
  }
}
