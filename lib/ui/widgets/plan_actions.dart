import 'package:flutter/material.dart';

import '../../api/client.dart' show ApiException, OfflineException;
import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import 'common.dart';

/// BI26100506 (plans): what the console does with a goal, on the phone. Distill walks a goal down to first tasks and
/// calendar entries; Ladder does the same for a decade-scale goal and shows its rungs. Neither adopts anything: the
/// proposals come back as a list to veto, and only the ticked ones are added when Accept is tapped
/// (`POST /api/plans/accept`), so nothing is created silently. A goal can be marked done or archived
/// (`/api/plans/update`). "Read the terrain" (`/api/plans/strategy`) shows where the goals sit against what is real.
/// Everything is a hub route, writes need the live server, and a refusal shows the server's reason.

/// A proposal's title, however hub spelled the key.
String proposalTitle(Map<String, dynamic> p) => fmt.s(p['title'] ?? p['TITLE']).trim();

/// The ticked proposals that still have a title, without the client-only `keep` flag, ready to send back.
List<Map<String, dynamic>> chosenProposals(List<Map<String, dynamic>> all, Set<int> kept) => [
      for (var i = 0; i < all.length; i++)
        if (kept.contains(i) && proposalTitle(all[i]).isNotEmpty) {...all[i]}..remove('keep'),
    ];

/// "2 tasks and 1 calendar entry", for the line above the proposals.
String proposalSummary(int tasks, int events) {
  final t = '$tasks task${tasks == 1 ? '' : 's'}';
  return events == 0 ? t : '$t and $events calendar entr${events == 1 ? 'y' : 'ies'}';
}

class PlanActions extends StatefulWidget {
  const PlanActions({super.key, required this.plan});
  final Map<String, dynamic> plan;

  @override
  State<PlanActions> createState() => _PlanActionsState();
}

class _PlanActionsState extends State<PlanActions> {
  String? _busy;
  List<Map<String, dynamic>> _tasks = const [];
  List<Map<String, dynamic>> _events = const [];
  Map<String, dynamic> _rungs = const {};
  final Set<int> _keepTasks = {};
  final Set<int> _keepEvents = {};

  String get _id => fmt.s(widget.plan['ID']);

  Future<Map<String, dynamic>?> _call(String path, Map<String, dynamic> body, String busy) async {
    setState(() => _busy = busy);
    String? err;
    Map<String, dynamic>? out;
    try {
      final r = fmt.m(await AppScope.of(context).mutations.post(path, body));
      if (r['success'] == false) {
        err = fmt.s(r['error']).isEmpty ? 'Refused.' : fmt.s(r['error']);
      } else {
        out = r;
      }
    } on ApiException catch (e) {
      err = e.message;
    } on OfflineException {
      err = 'This needs the live server - you are offline.';
    }
    if (!mounted) return null;
    setState(() => _busy = null);
    if (err != null) toast(context, err, error: true);
    return out;
  }

  void _take(Map<String, dynamic> r) {
    setState(() {
      _tasks = fmt.lm(r['proposals']);
      _events = fmt.lm(r['events']);
      _rungs = fmt.m(r['rungs']);
      _keepTasks
        ..clear()
        ..addAll(List.generate(_tasks.length, (i) => i));
      _keepEvents
        ..clear()
        ..addAll(List.generate(_events.length, (i) => i));
    });
  }

  Future<void> _distill() async {
    final r = await _call('/api/plans/distill', {'id': _id}, 'distill');
    if (r == null) return;
    _take(r);
    if (mounted) toast(context, '${proposalSummary(_tasks.length, _events.length)} to veto or accept');
  }

  Future<void> _ladder() async {
    final r = await _call('/api/plans/ladder', {'id': _id}, 'ladder');
    if (r == null) return;
    _take(r);
    if (mounted) toast(context, 'Laddered: ${_tasks.length} first task${_tasks.length == 1 ? '' : 's'} to veto or accept');
  }

  Future<void> _accept() async {
    final tasks = chosenProposals(_tasks, _keepTasks);
    final events = chosenProposals(_events, _keepEvents);
    if (tasks.isEmpty && events.isEmpty) {
      toast(context, 'Nothing is ticked, so nothing happens.');
      return;
    }
    final r = await _call('/api/plans/accept', {'id': _id, 'tasks': tasks, 'events': events}, 'accept');
    if (r == null) return;
    if (!mounted) return;
    setState(() {
      _tasks = const [];
      _events = const [];
      _rungs = const {};
    });
    toast(context, 'Added: ${proposalSummary(fmt.lm(r['added']).length, fmt.lm(r['events']).length)}');
    final services = AppScope.of(context);
    services.store.plans.refresh();
    services.store.state.refresh();
  }

  Future<void> _setStatus(String status) async {
    final sure = await confirmDialog(context, status == 'done' ? 'Mark this goal done?' : 'Archive this goal?', fmt.s(widget.plan['TITLE']), action: status == 'done' ? 'Mark done' : 'Archive');
    if (!sure || !mounted) return;
    final r = await _call('/api/plans/update', {'id': _id, 'status': status}, status);
    if (r != null && mounted) AppScope.of(context).store.plans.refresh();
  }

  Widget _proposalRows(String label, List<Map<String, dynamic>> items, Set<int> kept, String keyPrefix) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.only(top: 8), child: Text(label.toUpperCase(), style: T.label)),
      for (var i = 0; i < items.length; i++)
        Row(children: [
          Checkbox(
            key: Key('$keyPrefix-$i'),
            value: kept.contains(i),
            onChanged: (v) => setState(() => v == true ? kept.add(i) : kept.remove(i)),
          ),
          Expanded(child: Text(proposalTitle(items[i]), style: T.small.copyWith(color: kept.contains(i) ? C.text : C.text3))),
        ]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final status = fmt.s(widget.plan['STATUS']).toLowerCase();
    final closed = status == 'done' || status == 'archived';
    final hasProposals = _tasks.isNotEmpty || _events.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!closed)
          Wrap(spacing: 8, children: [
            OutlinedButton(key: Key('plan-distill-$_id'), onPressed: _busy != null ? null : _distill, child: Text(_busy == 'distill' ? 'Thinking...' : 'Distill')),
            OutlinedButton(key: Key('plan-ladder-$_id'), onPressed: _busy != null ? null : _ladder, child: Text(_busy == 'ladder' ? 'Walking it down...' : 'Ladder')),
            TextButton(key: Key('plan-done-$_id'), onPressed: _busy != null ? null : () => _setStatus('done'), child: const Text('Done')),
            TextButton(key: Key('plan-archive-$_id'), onPressed: _busy != null ? null : () => _setStatus('archived'), child: const Text('Archive')),
          ]),
        if (_rungs.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('RUNGS', style: T.label),
          for (final e in _rungs.entries) Text('${e.key}: ${fmt.s(e.value)}', style: T.small.copyWith(color: C.text2)),
        ],
        if (hasProposals) ...[
          _proposalRows('Tasks', _tasks, _keepTasks, 'keep-task'),
          _proposalRows('Calendar entries', _events, _keepEvents, 'keep-event'),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            FilledButton(key: const Key('plan-accept'), onPressed: _busy != null ? null : _accept, child: Text(_busy == 'accept' ? 'Adding...' : 'Accept ticked')),
            TextButton(
              key: const Key('plan-discard'),
              onPressed: () => setState(() {
                _tasks = const [];
                _events = const [];
                _rungs = const {};
              }),
              child: const Text('Discard'),
            ),
          ]),
        ],
      ],
    );
  }
}

/// "Read the terrain": where the goals sit against what is real this cycle. A card with a button; the answer is hub's.
class StrategyRead extends StatefulWidget {
  const StrategyRead({super.key});

  @override
  State<StrategyRead> createState() => _StrategyReadState();
}

class _StrategyReadState extends State<StrategyRead> {
  Map<String, dynamic>? _s;
  bool _busy = false;
  String? _error;

  Future<void> _read() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    String? err;
    Map<String, dynamic>? s;
    try {
      final r = fmt.m(await AppScope.of(context).mutations.post('/api/plans/strategy', {}));
      if (r['success'] == false) {
        err = fmt.s(r['error']).isEmpty ? 'Could not read it.' : fmt.s(r['error']);
      } else {
        s = fmt.m(r['strategy']);
      }
    } on ApiException catch (e) {
      err = e.message;
    } on OfflineException {
      err = 'This needs the live server - you are offline.';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
      if (s != null) _s = s;
    });
  }

  Widget _lines(String label, dynamic items, Color tone) {
    final list = items is List ? items.map((e) => fmt.s(e)).where((s) => s.isNotEmpty).toList() : <String>[];
    if (list.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label.toUpperCase(), style: T.label.copyWith(color: tone)),
        for (final l in list) Text(l, style: T.small.copyWith(color: C.text2)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text('The read', style: T.w500(T.body2))),
            OutlinedButton(key: const Key('strategy-read'), onPressed: _busy ? null : _read, child: Text(_busy ? 'Reading the terrain...' : 'Read the terrain')),
          ]),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_error!, key: const Key('strategy-error'), style: T.small.copyWith(color: C.red))),
          if (s != null) ...[
            const SizedBox(height: 6),
            Text('${fmt.s(s['theme'])} · ${fmt.s(s['daysLeft'])} days left', style: T.monoSmall),
            if (fmt.s(s['position']).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(fmt.s(s['position']), style: T.small.copyWith(color: C.text2))),
            _lines('Where the leverage is', s['leverage'], C.green),
            _lines('Where you are thin', s['exposed'], C.amber),
            if (fmt.s(s['window']).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('If only one thing: ${fmt.s(s['window'])}', style: T.small.copyWith(color: C.text))),
          ],
        ],
      ),
    );
  }
}
