import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/equicycle.dart';
import '../../util/fmt.dart' as fmt;
import 'common.dart';
import 'cycle_mix.dart' show currentCycleKey;

/// BI26100905: the cycle focus gauge on the phone, the same card the web console draws (BI26100709). The maths is
/// abacus's assess behind scope's /compass/gauge; this card only draws what hub's `GET /api/compass/gauge` returns, and
/// where the service is not set up or does not answer it says so instead of drawing a number, and never shows zeros for
/// "no data". The focus picker and the evidence log use hub's `/api/compass/focus` and `/api/compass/evidence`.
const gaugeModels = [
  ['isconl.cycle.leverage@1', 'Leverage'],
  ['isconl.cycle.revenue@1', 'Revenue'],
  ['isconl.cycle.health@1', 'Health'],
  ['isconl.cycle.learning@1', 'Learning'],
];

String pct(dynamic n) => '${((n is num ? n : 0) * 100).round()}%';

/// The trajectory badge: label and tone, or null when the gauge has no status.
({String label, Color tone})? gaugeStatus(dynamic trajectory) {
  final s = fmt.s(fmt.m(trajectory)['status']);
  return switch (s) {
    'behind' => (label: 'Behind', tone: C.amber),
    'ahead' => (label: 'Ahead', tone: C.green),
    'on_track' => (label: 'On track', tone: C.green),
    _ => null,
  };
}

class CycleGaugeCard extends StatefulWidget {
  /// [cycleKey] and [daysElapsed] default to today's cycle from the Equicycle tables; tests pass their own.
  const CycleGaugeCard({super.key, this.cycleKey, this.daysElapsed});
  final String? cycleKey;
  final int? daysElapsed;

  @override
  State<CycleGaugeCard> createState() => _CycleGaugeCardState();
}

class _CycleGaugeCardState extends State<CycleGaugeCard> {
  Map<String, dynamic>? _g;
  bool _needsFocus = false;

  String? get _key => widget.cycleKey ?? currentCycleKey();

  int get _elapsed {
    if (widget.daysElapsed != null) return widget.daysElapsed!;
    final p = EquicycleYears.instance.positionFor(DateTime.now());
    return p == null ? 0 : (p.day - 1).clamp(0, 28);
  }

  @override
  void initState() {
    super.initState();
    EquicycleYears.instance.addListener(_tableLanded);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final s = AppScope.of(context);
      EquicycleYears.instance.ensureLoaded(s.api, s.db);
      _load();
    });
  }

  @override
  void dispose() {
    EquicycleYears.instance.removeListener(_tableLanded);
    super.dispose();
  }

  void _tableLanded() {
    if (mounted && _g == null) _load();
  }

  Future<void> _load() async {
    final key = _key;
    if (key == null) return;
    try {
      final r = await AppScope.of(context).api.getJson('/api/compass/gauge?cycleKey=${Uri.encodeQueryComponent(key)}&daysElapsed=$_elapsed&daysTotal=28');
      if (!mounted) return;
      setState(() => _g = fmt.m(r));
    } catch (e) {
      if (!mounted) return;
      setState(() => _g = {'available': false, 'reason': 'The gauge could not be reached.'});
    }
  }

  Future<void> _post(String path, Map<String, dynamic> body, {String? ok}) async {
    try {
      final r = fmt.m(await AppScope.of(context).api.postJson(path, body));
      if (r['success'] == false) throw Exception(fmt.s(r['error']).isEmpty ? 'refused' : fmt.s(r['error']));
      if (mounted && ok != null) toast(context, ok);
      setState(() => _needsFocus = false);
      await _load();
    } catch (e) {
      if (mounted) toast(context, '$e'.replaceFirst('Exception: ', ''), error: true);
    }
  }

  Future<void> _logEvidence(Map<String, dynamic> g) async {
    final dims = fmt.lm(g['dimensions']).map((d) => fmt.s(d['id'])).where((s) => s.isNotEmpty).toList();
    var dim = fmt.s(g['weakest']).isNotEmpty ? fmt.s(g['weakest']) : (dims.isEmpty ? '' : dims.first);
    final note = TextEditingController();
    final link = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('Log evidence', style: T.title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (dims.isNotEmpty)
                DropdownButton<String>(
                  key: const Key('gauge-dim'),
                  isExpanded: true,
                  value: dims.contains(dim) ? dim : dims.first,
                  items: [for (final d in dims) DropdownMenuItem(value: d, child: Text(d))],
                  onChanged: (v) => setD(() => dim = v ?? dim),
                ),
              TextField(key: const Key('gauge-note'), controller: note, maxLength: 280, decoration: const InputDecoration(hintText: 'What happened, in one sentence')),
              TextField(key: const Key('gauge-link'), controller: link, decoration: const InputDecoration(hintText: 'Link (optional)')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: T.body2.copyWith(color: C.text3))),
            FilledButton(key: const Key('gauge-save'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (go != true || !mounted) return;
    final n = note.text.trim();
    if (n.isEmpty) {
      toast(context, 'Write one sentence about what happened.', error: true);
      return;
    }
    await _post('/api/compass/evidence', {'cycleKey': _key, 'dimension': dim, 'note': n, if (link.text.trim().isNotEmpty) 'link': link.text.trim()}, ok: 'Evidence logged');
  }

  Future<void> _changeFocus() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Change this cycle's focus?", style: T.title),
        content: Text("Evidence you logged stays, but it belongs to the old model's dimensions.", style: T.body2),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: T.body2.copyWith(color: C.text3))),
          FilledButton(key: const Key('gauge-change-confirm'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Change focus')),
        ],
      ),
    );
    if (ok == true && mounted) setState(() => _needsFocus = true);
  }

  Widget _actions(Map<String, dynamic> g) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Wrap(spacing: 8, children: [
          OutlinedButton(key: const Key('gauge-log'), onPressed: () => _logEvidence(g), child: const Text('Log evidence')),
          OutlinedButton(key: const Key('gauge-change'), onPressed: _changeFocus, child: const Text('Change focus')),
        ]),
      );

  Widget _picker() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Pick the focus this cycle is measured against. You log evidence as you go and the gauge shows where you stand.'),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final m in gaugeModels)
              OutlinedButton(
                key: Key('gauge-model-${m[0]}'),
                onPressed: () => _post('/api/compass/focus', {'cycleKey': _key, 'model': m[0]}),
                child: Text(m[1]),
              ),
          ]),
        ],
      );

  @override
  Widget build(BuildContext context) {
    if (_key == null) return const SizedBox.shrink();
    final g = _g;
    Widget body;
    if (g == null) {
      body = const Text('Reading the gauge…');
    } else if (_needsFocus || g['needsFocus'] == true) {
      body = _picker();
    } else if (g['available'] != true) {
      body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(fmt.s(g['reason']).isEmpty ? 'The gauge is not available.' : fmt.s(g['reason'])),
        if (g['empty'] == true) const Padding(padding: EdgeInsets.only(top: 6), child: Text('No evidence logged yet. The first entry starts the picture.')),
        _actions(g),
      ]);
    } else {
      final status = gaugeStatus(g['trajectory']);
      final tr = fmt.m(g['trajectory']);
      final delta = tr['deltaPoints'];
      final trend = fmt.m(fmt.m(g['trend'])['vsPriorPeriod']);
      final dims = fmt.lm(g['dimensions']);
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(fmt.s(g['position']), key: const Key('gauge-position'), style: T.title.copyWith(fontSize: 34)),
            const SizedBox(width: 6),
            Text('of 100', style: T.small.copyWith(color: C.text3)),
            const Spacer(),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('confidence ${pct(g['confidence'])}', style: T.small.copyWith(color: C.text3)),
              if (status != null)
                Text(
                  '${status.label}${delta is num ? ' · ${delta > 0 ? '+' : ''}$delta against the plan' : ''}',
                  key: const Key('gauge-status'),
                  style: T.small.copyWith(color: status.tone, fontWeight: FontWeight.w600),
                ),
              if (trend['positionDelta'] is num)
                Text('${(trend['positionDelta'] as num) >= 0 ? '+' : ''}${trend['positionDelta']} since the last reading', style: T.small.copyWith(color: C.text3)),
            ]),
          ]),
          if (g['capped'] == true) const Padding(padding: EdgeInsets.only(top: 6), child: Text('A near-zero dimension is holding the position down.')),
          if (g['empty'] == true) const Padding(padding: EdgeInsets.only(top: 6), child: Text('No evidence logged yet, so the confidence is low. Log the first entry.')),
          const SizedBox(height: 8),
          for (final d in dims) _dim(d, fmt.s(d['id']) == fmt.s(g['weakest'])),
          _actions(g),
        ],
      );
    }
    final title = fmt.s(fmt.m(g?['focus'])['title']);
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.isEmpty ? 'Cycle gauge' : 'Cycle gauge · $title', style: T.body.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          body,
        ],
      ),
    );
  }

  Widget _dim(Map<String, dynamic> d, bool weakest) {
    final score = d['score'] is num ? (d['score'] as num).toDouble() : 0.0;
    final gaps = (d['gaps'] is List ? d['gaps'] as List : const []).map((e) => fmt.s(e)).where((s) => s.isNotEmpty);
    final ev = d['evidence'] is List ? (d['evidence'] as List).length : 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${fmt.s(d['label']).isEmpty ? fmt.s(d['id']) : fmt.s(d['label'])}${weakest ? ' · weakest' : ''}', style: T.small.copyWith(fontWeight: FontWeight.w600))),
          Text('${score.round()} · confidence ${pct(d['confidence'])}', style: T.small.copyWith(color: C.text3)),
        ]),
        const SizedBox(height: 3),
        LinearProgressIndicator(value: (score / 100).clamp(0.0, 1.0), minHeight: 6, color: weakest ? C.amber : C.green, backgroundColor: C.surface),
        for (final x in gaps) Padding(padding: const EdgeInsets.only(top: 2), child: Text(x, style: T.small.copyWith(color: C.text3))),
        if (ev > 0) Text('$ev piece${ev == 1 ? '' : 's'} of evidence', style: T.small.copyWith(color: C.text3)),
      ]),
    );
  }
}
