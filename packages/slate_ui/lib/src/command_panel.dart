import 'dart:async';

import 'package:flutter/material.dart';

import 'client.dart';
import 'models.dart';
import 'tokens.dart';

enum _Stage { compose, confirm }

/// Compose a directive, read it back, pass step-up, send, then watch its
/// delivery state.
class CommandPanel extends StatefulWidget {
  const CommandPanel({
    super.key,
    required this.client,
    required this.stepUp,
    this.pollEvery = const Duration(seconds: 3),
  });

  final SlateClient client;
  final StepUp stepUp;
  final Duration pollEvery;

  @override
  State<CommandPanel> createState() => _CommandPanelState();
}

class _CommandPanelState extends State<CommandPanel> {
  static const _expiries = <String, Duration?>{
    'No expiry': null,
    '1 hour': Duration(hours: 1),
    '4 hours': Duration(hours: 4),
    'Until tomorrow': Duration(hours: 18),
  };

  List<SessionInfo> _sessions = const [];
  CommandTarget _target = const CommandTarget.everyone();
  final _message = TextEditingController();
  bool _persistent = true;
  String _expiryKey = 'Until tomorrow';
  _Stage _stage = _Stage.compose;
  CommandDraft? _draft;
  bool _sending = false;
  String? _error;
  final List<CommandStatus> _sent = [];
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    widget.client.sessions().then((s) {
      if (mounted) setState(() => _sessions = s);
    }).catchError((_) {});
    _poll = Timer.periodic(widget.pollEvery, (_) => _refreshDelivery());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _message.dispose();
    super.dispose();
  }

  Future<void> _refreshDelivery() async {
    for (var i = 0; i < _sent.length; i++) {
      if (_sent[i].state == DeliveryState.acknowledged) continue;
      try {
        final st = await widget.client.deliveryState(_sent[i].id);
        if (!mounted) return;
        setState(() => _sent[i] = _sent[i].copyWith(st));
      } catch (_) {}
    }
  }

  List<CommandTarget> get _targets {
    final kinds = <String>{};
    for (final s in _sessions) {
      kinds.add('${s.kind}|${s.machine}');
    }
    return [
      const CommandTarget.everyone(),
      for (final k in (kinds.toList()..sort()))
        CommandTarget.kindOnMachine(kind: k.split('|')[0], machine: k.split('|')[1]),
      for (final s in _sessions) CommandTarget.session(s.id),
    ];
  }

  void _review(CommandDraft draft) {
    setState(() {
      _draft = draft;
      _stage = _Stage.confirm;
      _error = null;
    });
  }

  void _quick(QuickAction a) => _review(CommandDraft(
        target: _target,
        message: a.message,
        persistent: true,
        expiresIn: const Duration(hours: 18),
        action: a,
      ));

  Future<void> _send() async {
    final draft = _draft!;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final ok = await widget.stepUp(draft);
      if (!ok) {
        setState(() => _error = 'Step-up was not completed. Nothing was sent.');
        return;
      }
      final id = await widget.client.sendCommand(draft);
      setState(() {
        _sent.insert(0, CommandStatus(id: id, draft: draft, state: DeliveryState.sent));
        _stage = _Stage.compose;
        _draft = null;
        _message.clear();
      });
    } catch (e) {
      setState(() => _error = 'Could not send: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = SlateTokens.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_stage == _Stage.compose) ..._compose(t) else ..._confirm(t),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, style: TextStyle(color: t.danger, fontSize: 13)),
          ),
        if (_sent.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('SENT',
              style: TextStyle(
                  color: t.text3,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2)),
          const SizedBox(height: 8),
          for (final c in _sent) _DeliveryRow(status: c),
        ],
      ],
    );
  }

  List<Widget> _compose(SlateTokens t) {
    final targets = _targets;
    final current = targets.contains(_target) ? _target : targets.first;
    return [
      Text('To', style: TextStyle(color: t.text2, fontSize: 12)),
      const SizedBox(height: 6),
      DropdownButton<CommandTarget>(
        key: const Key('target-picker'),
        isExpanded: true,
        value: current,
        items: [
          for (final x in targets)
            DropdownMenuItem(value: x, child: Text(x.label, overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (v) => setState(() => _target = v ?? _target),
      ),
      const SizedBox(height: 14),
      TextField(
        key: const Key('message-field'),
        controller: _message,
        minLines: 3,
        maxLines: 6,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(labelText: 'Message', border: OutlineInputBorder()),
      ),
      const SizedBox(height: 10),
      SwitchListTile(
        key: const Key('persist-switch'),
        contentPadding: EdgeInsets.zero,
        title: const Text('Keep delivering until acknowledged'),
        value: _persistent,
        onChanged: (v) => setState(() => _persistent = v),
      ),
      DropdownButton<String>(
        key: const Key('expiry-picker'),
        isExpanded: true,
        value: _expiryKey,
        items: [for (final k in _expiries.keys) DropdownMenuItem(value: k, child: Text(k))],
        onChanged: (v) => setState(() => _expiryKey = v ?? _expiryKey),
      ),
      const SizedBox(height: 12),
      FilledButton(
        key: const Key('review-button'),
        onPressed: _message.text.trim().isEmpty
            ? null
            : () => _review(CommandDraft(
                  target: current,
                  message: _message.text.trim(),
                  persistent: _persistent,
                  expiresIn: _expiries[_expiryKey],
                )),
        child: const Text('Review'),
      ),
      const SizedBox(height: 22),
      Text('QUICK ACTIONS',
          style: TextStyle(
              color: t.text3,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final a in QuickAction.values)
          OutlinedButton(
            key: Key('quick-${a.name}'),
            onPressed: () {
              _target = current;
              _quick(a);
            },
            child: Text(a.label),
          ),
      ]),
    ];
  }

  List<Widget> _confirm(SlateTokens t) {
    final d = _draft!;
    final expiry = d.expiresIn == null ? 'no expiry' : 'expires in ${d.expiresIn!.inHours} h';
    return [
      Text('Read this back before it goes',
          style: TextStyle(color: t.text, fontSize: 16, fontWeight: FontWeight.w600)),
      const SizedBox(height: 12),
      _kv(t, 'To', d.target.label),
      _kv(t, 'Delivery', '${d.persistent ? 'persistent, until acknowledged' : 'once'}, $expiry'),
      if (d.action != null) _kv(t, 'Action', d.action!.label),
      const SizedBox(height: 8),
      Container(
        key: const Key('confirm-message'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: t.surface2,
          border: Border.all(color: t.hairline),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(d.message, style: TextStyle(color: t.text, fontSize: 13)),
      ),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(
          child: OutlinedButton(
            key: const Key('back-button'),
            onPressed: _sending ? null : () => setState(() => _stage = _Stage.compose),
            child: const Text('Back'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton(
            key: const Key('send-button'),
            onPressed: _sending ? null : _send,
            child: Text(_sending ? 'Sending' : 'Confirm and send'),
          ),
        ),
      ]),
    ];
  }

  Widget _kv(SlateTokens t, String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 74, child: Text(k, style: TextStyle(color: t.text3, fontSize: 12))),
          Expanded(child: Text(v, style: TextStyle(color: t.text, fontSize: 13))),
        ]),
      );
}

class _DeliveryRow extends StatelessWidget {
  const _DeliveryRow({required this.status});
  final CommandStatus status;

  static String text(DeliveryState s) {
    switch (s) {
      case DeliveryState.sent:
        return 'sent';
      case DeliveryState.delivered:
        return 'delivered';
      case DeliveryState.acknowledged:
        return 'acknowledged';
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = SlateTokens.of(context);
    final done = status.state == DeliveryState.acknowledged;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Expanded(
          child: Text(
            status.draft.action?.label ?? status.draft.message,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: t.text, fontSize: 13),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(status.draft.target.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: t.text3, fontSize: 11)),
        ),
        const SizedBox(width: 10),
        Text(text(status.state),
            key: Key('state-${status.id}'),
            style: TextStyle(color: done ? t.ok : t.warn, fontSize: 12)),
      ]),
    );
  }
}
