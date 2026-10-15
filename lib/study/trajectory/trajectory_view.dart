import 'package:flutter/material.dart';

import '../../theme.dart';
import 'trajectory_model.dart';

String _day(DateTime? d, String fallback) {
  if (d == null) return fallback.isEmpty ? 'not set' : fallback;
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${m[d.month - 1]} ${d.year}';
}

/// The Trajectory sections of a module, drawn from the served block: ORIENT's
/// question and horizons, PROBE's forecast gate, APPLY's scenario table with
/// likelihood bars, 1 to 5 dots and scores, pattern chips, and ANCHOR's
/// re-score date with a stale badge.
///
/// The table stays hidden until the learner has entered their own forecast, the
/// same way a model answer stays hidden (standard 4.1.0).
class TrajectoryReader extends StatefulWidget {
  const TrajectoryReader({
    super.key,
    required this.trajectory,
    required this.saved,
    required this.onSaveProbe,
    this.now = DateTime.now,
  });

  final Trajectory trajectory;

  /// The learner's saved forecast for this module, if any.
  final ProbeEntry? saved;

  /// Stores the forecast (per learner and module, with its date).
  final Future<void> Function(int pct) onSaveProbe;
  final DateTime Function() now;

  @override
  State<TrajectoryReader> createState() => _TrajectoryReaderState();
}

class _TrajectoryReaderState extends State<TrajectoryReader> {
  final _probe = TextEditingController();
  String? _error;
  bool _busy = false;
  ProbeEntry? _saved;

  @override
  void initState() {
    super.initState();
    _saved = widget.saved;
  }

  @override
  void didUpdateWidget(TrajectoryReader old) {
    super.didUpdateWidget(old);
    if (widget.saved != null && old.saved?.pct != widget.saved!.pct) _saved = widget.saved;
  }

  @override
  void dispose() {
    _probe.dispose();
    super.dispose();
  }

  Future<void> _lock() async {
    final n = parseProbe(_probe.text);
    if (n == null) {
      setState(() => _error = 'Enter a whole number from 0 to 100.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSaveProbe(n);
      if (mounted) setState(() => _saved = ProbeEntry(n, widget.now()));
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save your forecast. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.trajectory;
    final now = widget.now();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 18),
      Text('ORIENT', style: T.label),
      const SizedBox(height: 6),
      Text(t.question, key: const Key('traj-question'), style: T.body),
      const SizedBox(height: 8),
      Text('90 days: ${_day(t.horizon90d, '')}   12 months: ${_day(t.horizon12m, '')}',
          key: const Key('traj-horizons'), style: T.small),
      if (t.patterns.isNotEmpty) ...[
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final p in t.patterns)
            Chip(
              key: Key('pattern-${p.id}'),
              label: Text(p.strength.isEmpty ? p.id : '${p.id} · ${p.strength}', style: T.tiny),
              visualDensity: VisualDensity.compact,
            ),
        ]),
      ],
      const SizedBox(height: 18),
      Text('PROBE', style: T.label),
      const SizedBox(height: 6),
      if (_saved == null) ...[
        Text('Before you see the scenarios: what is the chance, as a whole-number percentage, that the answer to the question is yes?',
            style: T.body2),
        const SizedBox(height: 8),
        Row(children: [
          SizedBox(
            width: 110,
            child: TextField(
              key: const Key('probe-field'),
              controller: _probe,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(suffixText: '%', isDense: true, border: OutlineInputBorder()),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            key: const Key('probe-save'),
            onPressed: _busy ? null : _lock,
            child: const Text('Lock in'),
          ),
        ]),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_error!, key: const Key('probe-error'), style: T.tiny.copyWith(color: C.red)),
          ),
        const SizedBox(height: 8),
        Text('The scenario table opens once you have locked in your number.',
            key: const Key('table-locked'), style: T.tiny),
      ] else ...[
        Text('Your forecast: ${_saved!.pct}% on ${_day(_saved!.at.toLocal(), '')}',
            key: const Key('probe-saved'), style: T.body),
        const SizedBox(height: 14),
        Text('APPLY', style: T.label),
        const SizedBox(height: 8),
        for (final s in t.scenarios) _ScenarioRow(scenario: s),
        if (!t.sconlOnly && t.register.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('REGISTER', style: T.label),
          for (final r in t.register) Padding(padding: const EdgeInsets.only(top: 4), child: Text(r, style: T.small)),
        ],
      ],
      const SizedBox(height: 18),
      Text('ANCHOR', style: T.label),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(
          child: Text('Re-score on ${_day(t.rescoreOn, t.rescoreOnText)}',
              key: const Key('traj-rescore'), style: T.body2),
        ),
        if (t.isStale(now))
          Container(
            key: const Key('stale-badge'),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              border: Border.all(color: C.amber),
              borderRadius: BorderRadius.circular(Sz.rSm),
            ),
            child: Text('stale forecast', style: T.tiny.copyWith(color: C.amber)),
          ),
      ]),
    ]);
  }
}

class _ScenarioRow extends StatefulWidget {
  const _ScenarioRow({required this.scenario});
  final TrajectoryScenario scenario;

  @override
  State<_ScenarioRow> createState() => _ScenarioRowState();
}

class _ScenarioRowState extends State<_ScenarioRow> {
  bool _open = false;

  Widget _dots(String label, int n, Key key) => Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: T.tiny),
        const SizedBox(width: 4),
        Row(key: key, children: [
          for (var i = 1; i <= 5; i++)
            Icon(i <= n ? Icons.circle : Icons.circle_outlined, size: 8, color: i <= n ? C.greenBright : C.text3),
        ]),
      ]);

  @override
  Widget build(BuildContext context) {
    final s = widget.scenario;
    return InkWell(
      key: Key('scenario-${s.id}'),
      onTap: () => setState(() => _open = !_open),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(border: Border.all(color: C.border), borderRadius: BorderRadius.circular(Sz.rSm)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(s.name, style: T.body)),
            Text(s.scoreLabel, key: Key('score-${s.id}'), style: T.mono),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: LinearProgressIndicator(key: Key('bar-${s.id}'), minHeight: 4, value: s.p / 100),
            ),
            const SizedBox(width: 8),
            Text('${s.p}%', style: T.monoSmall),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 14, children: [
            _dots('impact', dotCount(s.impact), Key('impact-${s.id}')),
            _dots('control', dotCount(s.control), Key('control-${s.id}')),
          ]),
          if (s.signal.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Signal: ${s.signal}', style: T.small),
          ],
          if (s.now.isNotEmpty) Text('Do now: ${s.now}', style: T.small),
          if (_open) ...[
            const SizedBox(height: 8),
            Text('Basis', style: T.label),
            Text(s.basis, key: Key('basis-${s.id}'), style: T.small),
            if (s.indicators.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Indicators', style: T.label),
              for (final i in s.indicators) Text('• $i', style: T.small),
            ],
          ],
        ]),
      ),
    );
  }
}
