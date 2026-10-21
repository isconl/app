import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import 'common.dart';

/// BI26100910: the "Changed since you read it" cards on Today, from `GET /api/study/refreshers` (at most three, newest
/// first). A card shows the title and its two summary lines. "Refresh (3 questions)" walks the three questions one at a
/// time, each with a "Show answer" tap; after the third, Done posts `refreshed`. "Got it" posts `dismissed` and
/// removes the card at once, and puts it back if the post fails. An empty list shows nothing at all.
const refreshersSeenPath = '/api/study/refreshers/seen';

class RefresherCards extends StatefulWidget {
  const RefresherCards({super.key});

  @override
  State<RefresherCards> createState() => _RefresherCardsState();
}

class _RefresherCardsState extends State<RefresherCards> {
  final Set<String> _hidden = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final s = AppScope.of(context).store.studyRefreshers;
      s.hydrate().then((_) {
        if (mounted) s.refresh();
      });
    });
  }

  /// Post that a card was seen. Returns true when the server took it.
  Future<bool> _seen(String id, String how) async {
    try {
      await AppScope.of(context).mutations.post(refreshersSeenPath, {'id': id, 'how': how});
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _dismiss(String id) async {
    setState(() => _hidden.add(id));
    final ok = await _seen(id, 'dismissed');
    if (!ok && mounted) {
      setState(() => _hidden.remove(id));
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Could not save that. The card is back.')));
    }
  }

  Future<void> _finish(String id) async {
    setState(() => _hidden.add(id));
    final ok = await _seen(id, 'refreshed');
    if (!ok && mounted) {
      setState(() => _hidden.remove(id));
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Could not save that. The card is back.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final snap = AppScope.of(context).store.studyRefreshers;
    return ListenableBuilder(
      listenable: snap,
      builder: (context, _) {
        final cards = fmt.lm(fmt.m(snap.value)['cards']).where((c) => !_hidden.contains(fmt.s(c['id']))).toList();
        if (cards.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionLabel('Changed since you read it'),
            for (final c in cards)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _RefresherCard(
                  key: ValueKey('refresher-${fmt.s(c['id'])}'),
                  card: c,
                  onGotIt: () => _dismiss(fmt.s(c['id'])),
                  onDone: () => _finish(fmt.s(c['id'])),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _RefresherCard extends StatefulWidget {
  const _RefresherCard({super.key, required this.card, required this.onGotIt, required this.onDone});
  final Map<String, dynamic> card;
  final VoidCallback onGotIt;
  final VoidCallback onDone;

  @override
  State<_RefresherCard> createState() => _RefresherCardState();
}

class _RefresherCardState extends State<_RefresherCard> {
  bool _asking = false;
  int _i = 0;
  bool _showAnswer = false;

  List<Map<String, dynamic>> get _questions => fmt.lm(widget.card['questions']);

  @override
  Widget build(BuildContext context) {
    final summary = (widget.card['summary'] is List ? widget.card['summary'] as List : const []).map((e) => fmt.s(e)).where((s) => s.isNotEmpty).take(2);
    final qs = _questions;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(fmt.s(widget.card['title']), style: T.body.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          if (!_asking) ...[
            for (final line in summary) Padding(padding: const EdgeInsets.only(bottom: 2), child: Text(line, style: T.small.copyWith(color: C.text2))),
            const SizedBox(height: 10),
            Row(
              children: [
                if (qs.isNotEmpty)
                  FilledButton(
                    key: const Key('refresher-start'),
                    onPressed: () => setState(() => _asking = true),
                    child: Text('Refresh (${qs.length} questions)'),
                  ),
                const SizedBox(width: 8),
                TextButton(key: const Key('refresher-gotit'), onPressed: widget.onGotIt, child: const Text('Got it')),
              ],
            ),
          ] else ...[
            Text('Question ${_i + 1} of ${qs.length}', style: T.small.copyWith(color: C.text3)),
            const SizedBox(height: 4),
            Text(fmt.s(qs[_i]['question'])),
            const SizedBox(height: 8),
            if (_showAnswer) Text(fmt.s(qs[_i]['answer']), style: T.small.copyWith(color: C.text2)),
            const SizedBox(height: 10),
            if (!_showAnswer)
              OutlinedButton(key: const Key('refresher-show'), onPressed: () => setState(() => _showAnswer = true), child: const Text('Show answer'))
            else if (_i + 1 < qs.length)
              FilledButton(key: const Key('refresher-next'), onPressed: () => setState(() { _i++; _showAnswer = false; }), child: const Text('Next'))
            else
              FilledButton(key: const Key('refresher-done'), onPressed: widget.onDone, child: const Text('Done')),
          ],
        ],
      ),
    );
  }
}
