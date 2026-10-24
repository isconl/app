import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../services/rank_feedback.dart';
import '../../theme.dart';
import '../widgets/common.dart';

/// PI26101601: Settings > Learned ranking. What slate has learned from the drags, in its own words, each with the day it
/// fades and a way to undo it.
class LearnedRankingPage extends StatefulWidget {
  const LearnedRankingPage({super.key, this.api});
  final RankApi? api;

  @override
  State<LearnedRankingPage> createState() => _LearnedRankingPageState();
}

class _LearnedRankingPageState extends State<LearnedRankingPage> {
  RankApi? _api;
  late Future<List<LearnedAdjustment>> _f;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_api == null) {
      _api = widget.api ?? HttpRankApi(AppScope.of(context).api);
      _f = _api!.adjustments();
    }
  }

  Future<void> _undo(LearnedAdjustment a) async {
    try {
      await _api!.undo(a.id);
      if (mounted) setState(() { _f = _api!.adjustments(); });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not undo: $e')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Learned ranking')),
        body: FutureBuilder<List<LearnedAdjustment>>(
          future: _f,
          builder: (ctx, snap) {
            if (snap.hasError) return const EmptyState('Could not load', 'Slate did not answer.', icon: Icons.cloud_off_rounded);
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final list = snap.data!;
            if (list.isEmpty) {
              return const EmptyState('Nothing learned yet', 'Nothing learned yet. Drag a task to teach the order.', icon: Icons.swap_vert_rounded);
            }
            return ListView(children: [
              for (final a in list)
                Dismissible(
                  key: ValueKey('adj-${a.id}'),
                  direction: DismissDirection.endToStart,
                  background: Container(color: C.red, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 16), child: const Icon(Icons.undo_rounded, color: Colors.white)),
                  confirmDismiss: (_) async {
                    await _undo(a);
                    return false;
                  },
                  child: ListTile(
                    key: Key('adjustment-${a.id}'),
                    title: Text(a.sentence),
                    subtitle: a.fadeLine.isEmpty ? null : Text(a.fadeLine, style: T.small),
                    trailing: TextButton(key: Key('undo-${a.id}'), onPressed: () => _undo(a), child: const Text('Undo')),
                  ),
                ),
            ]);
          },
        ),
      );
}
