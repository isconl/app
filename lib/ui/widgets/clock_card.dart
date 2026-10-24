import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../services/clock.dart';
import '../../services/clock_strings.dart';
import '../../theme.dart';
import 'common.dart';

/// BI26101408: the Clock card on Today. One big button whose label follows the state (Clock in, Take a break, Back),
/// a smaller Clock out while a day is open, today's net time ticking, the break count, and a "Fix a time" link.
/// Taps go through [ClockService], so they queue at once with the device time and send when the phone is online.
class ClockCard extends StatefulWidget {
  const ClockCard({super.key, this.service, this.clock, this.language});

  final ClockService? service;
  final DateTime Function()? clock;

  /// Tests pass `sw`; the app follows the device.
  final String? language;

  @override
  State<ClockCard> createState() => _ClockCardState();
}

class _ClockCardState extends State<ClockCard> {
  ClockService? _svc;
  ClockHead? _head;
  Timer? _tick;
  String? _notice;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  ClockStrings get _t => ClockStrings.forLanguage(widget.language ?? Localizations.localeOf(context).languageCode);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_svc != null) return;
    final app = AppScope.of(context);
    _svc = widget.service ?? ClockService(db: app.db, api: () => app.api, outbox: app.outbox);
    _load();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final h = await _svc!.head();
    if (mounted) setState(() => _head = h);
  }

  Future<void> _tap(ClockAction a) async {
    final refusal = await _svc!.tap(a, at: _now());
    await _load();
    if (mounted) setState(() => _notice = refusal);
    unawaited(_svc!.publish(locked: false));
  }

  String _buttonLabel(ClockState s) => switch (s) {
        ClockState.out => _t['in'],
        ClockState.working => _t['break'],
        ClockState.onBreak => _t['back'],
      };

  @override
  Widget build(BuildContext context) {
    final head = _head;
    if (head == null) return const SizedBox.shrink();
    final t = _t;
    return Panel(
      key: const Key('clock-card'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t['title'], style: T.title),
        const SizedBox(height: 8),
        Text('${t['net']}: ${t.duration(head.workedNow(_now()))}', key: const Key('clock-net'), style: T.body.copyWith(fontWeight: FontWeight.w700)),
        Text('${t['breaks']}: ${head.breaks} · ${clockStateWord(head.state)}', key: const Key('clock-breaks'), style: T.small.copyWith(color: C.text3)),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: FilledButton(
            key: const Key('clock-main'),
            onPressed: () => _tap(nextClockAction(head.state)),
            child: Text(_buttonLabel(head.state), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
        ),
        if (head.state != ClockState.out)
          TextButton(key: const Key('clock-out'), onPressed: () => _tap(ClockAction.clockOut), child: Text(t['out'])),
        if (_notice != null) Text(_notice!, key: const Key('clock-notice'), style: T.small.copyWith(color: C.amber)),
        TextButton(key: const Key('clock-fix'), onPressed: () => _fixDialog(context), child: Text(t['fix'])),
      ]),
    );
  }

  Future<void> _fixDialog(BuildContext context) async {
    final t = _t;
    final entries = await _svc!.entries();
    if (!context.mounted) return;
    if (entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t['noEntries'])));
      return;
    }
    ClockEntry pick = entries.last;
    TimeOfDay? newTime;
    final reason = TextEditingController();
    String? error;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(t['fixTitle']),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButton<ClockEntry>(
                key: const Key('fix-entry'),
                isExpanded: true,
                value: pick,
                hint: Text(t['pick']),
                items: [for (final e in entries) DropdownMenuItem(value: e, child: Text('${e.kind} ${e.at == null ? '' : _hm(e.at!)}'))],
                onChanged: (v) => set(() => pick = v ?? pick),
              ),
              TextButton(
                key: const Key('fix-time'),
                onPressed: () async {
                  final v = await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(pick.at ?? _now()));
                  if (v != null) set(() => newTime = v);
                },
                child: Text(newTime == null ? t['newTime'] : newTime!.format(ctx)),
              ),
              TextField(key: const Key('fix-reason'), controller: reason, decoration: InputDecoration(labelText: t['reason'], errorText: error)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t['cancel'])),
            TextButton(
              key: const Key('fix-save'),
              onPressed: () {
                if (reason.text.trim().length < 3) {
                  set(() => error = t['reasonNeeded']);
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: Text(t['save']),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final base = pick.at ?? _now();
    final at = newTime == null ? null : DateTime(base.year, base.month, base.day, newTime!.hour, newTime!.minute);
    await _svc!.correct(seq: pick.seq, reason: reason.text, at: at);
    if (mounted) setState(() => _notice = t['queued']);
  }

  static String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
