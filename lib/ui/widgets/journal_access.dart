import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../services/cx_grants.dart';
import '../../theme_tokens.dart';

String _left(Duration d) {
  if (d.inMinutes < 1) return 'under a minute left';
  if (d.inMinutes < 60) return '${d.inMinutes} min left';
  return '${d.inHours} h ${d.inMinutes % 60} min left';
}

/// The sheet a push notice opens: who wants to read the journal, from where,
/// why, and for how long. No journal text appears here.
class GrantRequestSheet extends StatefulWidget {
  const GrantRequestSheet({super.key, required this.client, required this.request});
  final CxGrantsClient client;
  final GrantRequest request;

  @override
  State<GrantRequestSheet> createState() => _GrantRequestSheetState();
}

class _GrantRequestSheetState extends State<GrantRequestSheet> {
  bool _busy = false;
  String? _message;
  bool _done = false;

  Future<void> _run(Future<String> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final msg = await action();
      setState(() {
        _message = msg;
        _done = true;
      });
    } catch (_) {
      setState(() => _message = 'That did not go through. Nothing was changed.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String> _approve() async {
    final ok = await widget.client.approve(widget.request.id);
    if (!ok) throw StateError('not approved');
    return 'Approved. ${widget.request.session} can read for up to ${widget.request.limit.inHours} hours.';
  }

  Future<String> _refuse() async {
    await widget.client.refuse(widget.request.id);
    return 'Refused. ${widget.request.session} cannot read the journal.';
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${r.session} wants to read your journal', key: const Key('grant-title'), style: TokenType.title),
          const SizedBox(height: 12),
          _row('Session', r.session),
          _row('Machine', r.machine),
          _row('Reason', r.reason),
          _row('Limit', '${r.limit.inHours} hours, read only, you can revoke it'),
          const SizedBox(height: 16),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_message!, key: const Key('grant-message'), style: TokenType.body2),
            ),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                key: const Key('grant-refuse'),
                onPressed: _busy || _done ? null : () => _run(_refuse),
                child: const Text('Refuse'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                key: const Key('grant-approve'),
                onPressed: _busy || _done ? null : () => _run(_approve),
                child: const Text('Approve with passkey'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 74, child: Text(k, style: TokenType.small)),
          Expanded(child: Text(v, style: TokenType.body)),
        ]),
      );
}

/// Opens the grant sheet for [id]; says so plainly if the request has gone.
Future<void> showGrantRequest(BuildContext context, String id) async {
  final services = AppScope.of(context);
  final client = HubCxGrantsClient(services.api, services.session.passkeys);
  GrantRequest? req;
  try {
    req = await client.request(id);
  } catch (_) {}
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => req == null
        ? const SafeArea(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text('That request is no longer open.', key: Key('grant-gone')),
            ),
          )
        : GrantRequestSheet(client: client, request: req),
  );
}

/// Settings, Journal access: live grants with time left and reads so far.
class JournalAccessCard extends StatefulWidget {
  const JournalAccessCard({super.key, required this.client, this.now = DateTime.now});
  final CxGrantsClient client;
  final DateTime Function() now;

  @override
  State<JournalAccessCard> createState() => _JournalAccessCardState();
}

class _JournalAccessCardState extends State<JournalAccessCard> {
  late Future<List<LiveGrant>> _grants = widget.client.live();

  Future<void> _revoke(LiveGrant g) async {
    await widget.client.revoke(g.id);
    setState(() {
      _grants = widget.client.live();
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<LiveGrant>>(
        future: _grants,
        builder: (context, snap) {
          if (snap.hasError) return const Text('Could not load journal access.');
          final list = snap.data;
          if (list == null) return const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator());
          if (list.isEmpty) {
            return const Text('No session can read your journal right now.', key: Key('no-grants'), style: TokenType.body2);
          }
          return Column(children: [
            for (final g in list)
              ListTile(
                key: Key('grant-${g.id}'),
                contentPadding: EdgeInsets.zero,
                title: Text(g.session, style: TokenType.body),
                subtitle: Text('${g.machine} · ${_left(g.timeLeft(widget.now()))} · ${g.reads} reads', style: TokenType.small),
                trailing: TextButton(
                  key: Key('revoke-${g.id}'),
                  onPressed: () => _revoke(g),
                  child: const Text('Revoke'),
                ),
              ),
          ]);
        },
      );
}
