import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_scope.dart';
import '../../services/rank_feedback.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;

/// PI26101601: the drag handle, and what a drop asks. Long-press the handle to drag. A drop above another row opens one
/// sheet with three choices; Cancel (or dismissing it) leaves the row where it was. Nothing is reordered locally:
/// slate answers in a sentence, and the list is redrawn from slate's order.
class RankHandle extends StatelessWidget {
  const RankHandle({super.key, required this.index});
  final int index;

  @override
  Widget build(BuildContext context) => ReorderableDelayedDragStartListener(
        index: index,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(Icons.drag_indicator_rounded, size: 20, color: C.text3, semanticLabel: 'Hold and drag to reorder'),
        ),
      );
}

/// The bottom sheet. Returns the choice, or null on Cancel.
Future<RankAnswer?> showRankSheet(BuildContext context, {required String title}) {
  HapticFeedback.mediumImpact();
  return showModalBottomSheet<RankAnswer>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text('Why did you move "${fmt.truncate(title, 40)}"?', style: T.title),
        ),
        for (final a in RankAnswer.values)
          ListTile(
            key: Key('rank-${a.wire}'),
            leading: Icon(a == RankAnswer.once ? Icons.push_pin_outlined : Icons.bolt_rounded, color: C.green),
            title: Text(a.label),
            onTap: () => Navigator.pop(ctx, a),
          ),
        ListTile(key: const Key('rank-cancel'), title: const Text('Cancel'), onTap: () => Navigator.pop(ctx)),
      ]),
    ),
  );
}

/// A drop: ask, send, and show slate's own sentence. [send] is injectable for tests; the app sends through the outbox.
Future<void> handleRankDrop(
  BuildContext context, {
  required List<Map<String, dynamic>> items,
  required int oldIndex,
  required int newIndex,
  required VoidCallback reload,
  Future<RankAnswer?> Function(BuildContext, String)? ask,
  Future<({bool queued, String? error, String sentence})> Function(String moved, RankAnswer, String? above, String title)? send,
}) async {
  final ids = [for (final t in items) fmt.s(t['ID'] ?? t['id'])];
  final above = rowAbove(ids, oldIndex, newIndex);
  final moved = items[oldIndex];
  final title = fmt.s(moved['TITLE'] ?? moved['title']);
  final answer = await (ask ?? (c, t) => showRankSheet(c, title: t))(context, title);
  if (answer == null || !context.mounted) return;
  final sender = send ??
      (m, a, ab, t) async {
        final r = await AppScope.of(context).mutations.rankFeedback(moved: m, answer: a.wire, above: ab, title: t);
        return (queued: r.queued, error: r.error, sentence: fmt.s(fmt.m(r.payload)['sentence']));
      };
  final r = await sender(ids[oldIndex], answer, above, title);
  if (!context.mounted) return;
  final text = r.error != null ? r.error! : r.queued ? 'Saved. It will be sent when you are online.' : (r.sentence.isEmpty ? 'Done.' : r.sentence);
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(key: const Key('rank-answer'), content: Text(text)));
  if (r.error == null) reload();
}
