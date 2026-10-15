import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../services/recall.dart';
import '../../theme.dart';
import 'common.dart';

/// BI26101109: the Recall card at the top of the Learning view. Nothing shows when nothing is due. One question at a
/// time, one tap per answer, the result and the reason at once; a miss offers "Reopen at this part".
class RecallCard extends StatefulWidget {
  const RecallCard({super.key, this.api, required this.onReopen});
  final RecallApi? api;

  /// Opens the module at the section a missed question came from.
  final void Function(RecallReopen target) onReopen;

  @override
  State<RecallCard> createState() => _RecallCardState();
}

class _RecallCardState extends State<RecallCard> {
  RecallApi get _api => widget.api ?? HubRecallApi(AppScope.of(context).api);
  List<RecallPrompt> _prompts = const [];
  RecallSummary _summary = const RecallSummary();
  int _at = 0;
  int? _picked;
  RecallResult? _result;
  bool _busy = false;
  bool _loaded = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final due = await _api.due();
      final sum = await _api.summary();
      if (mounted) {
        setState(() {
          _prompts = due;
          _summary = sum;
          _at = 0;
          _picked = null;
          _result = null;
          _loaded = true;
        });
      }
    } catch (_) {
      // Offline or an older hub: no card, no error. The reader just is not asked today.
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _answer(int i) async {
    final p = _prompts[_at];
    setState(() {
      _busy = true;
      _picked = i;
      _message = null;
    });
    try {
      final r = await _api.answer(p.qId, i);
      if (mounted) setState(() => _result = r);
    } catch (e) {
      if (mounted) {
        setState(() {
          _picked = null;
          _message = '$e'.replaceFirst('ApiException(0): ', '');
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _next() {
    setState(() {
      _at++;
      _picked = null;
      _result = null;
      _message = null;
    });
    if (_at >= _prompts.length) _load();
  }

  Future<void> _flag() async {
    final p = _prompts[_at];
    setState(() => _busy = true);
    try {
      await _api.flag(p.qId);
      if (mounted) setState(() => _message = 'Removed. A replacement is on its way.');
      _next();
    } catch (e) {
      if (mounted) setState(() => _message = '$e'.replaceFirst('ApiException(0): ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final done = _at >= _prompts.length;
    if (done && _summary.dueToday == 0 && _summary.retiredThisMonth == 0) return const SizedBox.shrink();
    if (done) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(_summary.line, key: const Key('recall-summary'), style: T.tiny),
      );
    }
    final p = _prompts[_at];
    final r = _result;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Panel(
        key: const Key('recall-card'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('Recall', style: T.title),
            const Spacer(),
            Text('${_at + 1} of ${_prompts.length}', style: T.tiny),
          ]),
          const SizedBox(height: 4),
          Text(_summary.line, style: T.tiny),
          const SizedBox(height: 10),
          Text(p.question, key: const Key('recall-question'), style: T.body2),
          const SizedBox(height: 8),
          for (var i = 0; i < p.choices.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: OutlinedButton(
                key: Key('recall-choice-$i'),
                style: OutlinedButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  side: BorderSide(color: _picked == i ? (r == null ? C.border : (r.correct ? C.green : C.red)) : C.border),
                ),
                onPressed: (_busy || r != null) ? null : () => _answer(i),
                child: Text(p.choices[i], textAlign: TextAlign.left),
              ),
            ),
          if (r != null) ...[
            const SizedBox(height: 4),
            Text(r.correct ? 'Right.' : 'Not quite. The answer is: ${r.answer}', key: const Key('recall-result'), style: T.body2.copyWith(color: r.correct ? C.green : C.amber)),
            if (r.why.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(r.why, key: const Key('recall-why'), style: T.small)),
            if (r.retired) Padding(padding: const EdgeInsets.only(top: 2), child: Text('Three in a row. This module is done with recall.', style: T.small)),
            Wrap(spacing: 8, children: [
              if (r.reopen != null) TextButton(key: const Key('recall-reopen'), onPressed: () => widget.onReopen(r.reopen!), child: const Text('Reopen at this part')),
              TextButton(key: const Key('recall-next'), onPressed: _next, child: Text(_at + 1 >= _prompts.length ? 'Done' : 'Next')),
            ]),
          ],
          if (p.generated)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(key: const Key('recall-flag'), onPressed: _busy ? null : _flag, child: Text('Drafted by the model. This question is wrong', style: T.tiny)),
            ),
          if (_message != null) Text(_message!, key: const Key('recall-message'), style: T.small),
        ]),
      ),
    );
  }
}
