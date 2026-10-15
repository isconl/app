import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_scope.dart';
import '../../services/parity3b.dart';
import '../../theme.dart';

Parity3bApi _defaultApi(BuildContext context) => HubParity3bApi(AppScope.of(context).api);

/// The pre-written chase for a decision that has been pending too long: who it goes
/// to, how, and the exact text, editable. The app never sends it. The reader copies
/// it and sends it themselves, as on the console, so nothing leaves without their hand.
Future<void> showChaseSheet(BuildContext context, String decisionId, {Parity3bApi? api}) {
  final a = api ?? _defaultApi(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => ChaseSheet(api: a, decisionId: decisionId),
  );
}

class ChaseSheet extends StatefulWidget {
  const ChaseSheet({super.key, required this.api, required this.decisionId});
  final Parity3bApi api;
  final String decisionId;

  @override
  State<ChaseSheet> createState() => _ChaseSheetState();
}

class _ChaseSheetState extends State<ChaseSheet> {
  late Future<ChaseDraft> _draft = widget.api.chase(widget.decisionId);
  final _text = TextEditingController();
  String? _loadedFor;
  String? _message;
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _another() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.api.rechase(widget.decisionId);
      if (mounted) {
        setState(() {
          _loadedFor = null;
          _draft = widget.api.chase(widget.decisionId);
        });
      }
    } catch (e) {
      if (mounted) setState(() => _message = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(18, 16, 18, 16 + MediaQuery.of(context).viewInsets.bottom),
          child: FutureBuilder<ChaseDraft>(
            future: _draft,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
              }
              if (snap.hasError) {
                return Text('${snap.error}'.replaceFirst('ApiException(0): ', ''), key: const Key('chase-error'), style: T.body);
              }
              final d = snap.data!;
              final key = '${d.id}|${d.body}';
              if (_loadedFor != key) {
                _loadedFor = key;
                _text.text = d.body;
              }
              return SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${d.id} · pending on ${d.by} since ${d.date}', style: T.small),
                  const SizedBox(height: 8),
                  Text('To ${d.to} via ${d.channel}', key: const Key('chase-to'), style: T.title),
                  const SizedBox(height: 10),
                  TextField(
                    key: const Key('chase-text'),
                    controller: _text,
                    minLines: 4,
                    maxLines: 12,
                    decoration: const InputDecoration(border: OutlineInputBorder(), helperText: 'Edit it freely. What you leave here is what gets copied.'),
                  ),
                  if (d.checks.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text('Check before sending', style: T.label),
                    for (final c in d.checks)
                      Padding(padding: const EdgeInsets.only(top: 4), child: Text('${c.found}: ${c.say}', style: T.small)),
                  ],
                  if (_message != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_message!, key: const Key('chase-note'), style: T.small)),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: FilledButton(
                        key: const Key('chase-copy'),
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: _text.text));
                          if (mounted) setState(() => _message = 'Copied. Go and send it.');
                        },
                        child: const Text('Copy message'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        key: const Key('chase-again'),
                        onPressed: _busy ? null : _another,
                        child: Text(_busy ? 'Rewriting...' : 'Different angle'),
                      ),
                    ),
                  ]),
                ]),
              );
            },
          ),
        ),
      );
}

/// Asks first, then stops counting a key date. Returns whether it was deleted.
Future<bool> confirmDeleteDate(BuildContext context, String id, String title, {Parity3bApi? api}) async {
  final a = api ?? _defaultApi(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final sure = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Stop counting this date?'),
      content: Text('$title\n\nThe counter disappears from the calendar. Nothing else is touched.', key: const Key('date-warning')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep it')),
        FilledButton(key: const Key('date-delete-confirm'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Stop counting')),
      ],
    ),
  );
  if (sure != true) return false;
  try {
    await a.deleteDate(id);
    return true;
  } catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text('$e')));
    return false;
  }
}

/// Time and Blocks: real logged time against the day's blocks, last 7 days.
class AdherenceCard extends StatefulWidget {
  const AdherenceCard({super.key, this.api});
  final Parity3bApi? api;

  @override
  State<AdherenceCard> createState() => _AdherenceCardState();
}

class _AdherenceCardState extends State<AdherenceCard> {
  Future<Adherence>? _f;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _f ??= (widget.api ?? _defaultApi(context)).adherence();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Adherence>(
        future: _f,
        builder: (context, snap) {
          final head = Row(children: [
            Expanded(child: Text('Time and blocks', style: T.title)),
            if (snap.hasData) Text('last ${snap.data!.days} days', style: T.tiny),
          ]);
          Widget body;
          if (snap.connectionState != ConnectionState.done) {
            body = Text('Loading...', style: T.small);
          } else if (snap.hasError) {
            body = Text('${snap.error}'.replaceFirst('ApiException(0): ', ''), key: const Key('adherence-error'), style: T.small.copyWith(color: C.red));
          } else {
            final a = snap.data!;
            final touched = a.touched;
            body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (touched.isEmpty)
                Text('No logged work sessions in this window yet. Start and stop a task to see adherence here.', key: const Key('adherence-empty'), style: T.small),
              for (final b in touched)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Expanded(child: Text('${b.day} ${b.name}', style: T.body2)),
                    Text('${b.loggedMinutes.round()}m logged', style: T.tiny),
                    if (b.adherencePct != null) ...[
                      const SizedBox(width: 8),
                      Text('${b.adherencePct}% on purpose',
                          key: Key('pct-${b.day}-${b.name}'),
                          style: T.tiny.copyWith(color: b.adherencePct! >= 70 ? C.greenBright : C.amber)),
                    ],
                  ]),
                ),
              if (a.recommendations.isNotEmpty) ...[
                const Divider(),
                for (final r in a.recommendations) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('· $r', style: T.small)),
              ],
            ]);
          }
          return Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(border: Border.all(color: C.border), borderRadius: BorderRadius.circular(Sz.rMd)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [head, const SizedBox(height: 8), body]),
          );
        },
      );
}

/// The day's theme phrase, under the date. Nothing shows when there is none or the
/// agent cannot be reached: it is a line of colour, not something to wait for.
class ThemeOfDayLine extends StatefulWidget {
  const ThemeOfDayLine({super.key, this.api});
  final Parity3bApi? api;

  @override
  State<ThemeOfDayLine> createState() => _ThemeOfDayLineState();
}

class _ThemeOfDayLineState extends State<ThemeOfDayLine> {
  Future<String?>? _f;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _f ??= (widget.api ?? _defaultApi(context)).themeDay().catchError((_) => null);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
        future: _f,
        builder: (context, snap) {
          final p = snap.data;
          if (p == null || p.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 2),
            child: Text(p, key: const Key('theme-of-day'), style: T.small.copyWith(fontStyle: FontStyle.italic, color: C.text2)),
          );
        },
      );
}

/// Sweep: runs the agent's notification check and says what it found.
class SweepButton extends StatefulWidget {
  const SweepButton({super.key, this.api, this.onDone});
  final Parity3bApi? api;
  final Future<void> Function()? onDone;

  @override
  State<SweepButton> createState() => _SweepButtonState();
}

class _SweepButtonState extends State<SweepButton> {
  bool _busy = false;

  Future<void> _run() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final api = widget.api ?? _defaultApi(context);
    setState(() => _busy = true);
    try {
      final raised = await api.sweep();
      await widget.onDone?.call();
      messenger?.showSnackBar(SnackBar(content: Text(sweepMessage(raised))));
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => TextButton(
        key: const Key('sweep-button'),
        onPressed: _busy ? null : _run,
        child: Text(_busy ? 'Checking...' : 'Sweep'),
      );
}
