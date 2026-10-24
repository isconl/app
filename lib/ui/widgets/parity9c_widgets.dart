import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_scope.dart';
import '../../services/parity9c.dart';
import '../../theme.dart';
import 'common.dart';

/// BI26101515: the screens for the routes in [Parity9cApi]. Every delete asks first, naming what goes; Google send shows
/// the recipient and subject before an explicit tap; nothing prints a code or PIN anywhere but the field it was typed in.

Parity9cApi parity9cFor(BuildContext context) => HttpParity9cApi(AppScope.of(context).api);

/// Chat: write the open thread out as markdown (copied; there is no share sheet in the app).
Future<void> exportChatThread(BuildContext context, Parity9cApi api) async {
  final sure = await confirmDialog(context, 'Export this conversation?', 'The whole thread is written out as markdown, including anything that has scrolled out of view. It is copied so you can paste it.', action: 'Export');
  if (!sure || !context.mounted) return;
  try {
    final e = await api.exportThread();
    await Clipboard.setData(ClipboardData(text: e.content));
    if (context.mounted) toast(context, 'Copied ${e.filename}');
  } on Parity9cException catch (e) {
    if (context.mounted) toast(context, e.message, error: true);
  }
}

/// Chat: delete one thread. Returns true when it went.
Future<bool> deleteChatThread(BuildContext context, Parity9cApi api, String id, String title) async {
  final sure = await confirmDialog(context, 'Delete this conversation?', '"$title" goes out of the vault entirely, including from OneDrive on the next sync.', action: 'Delete', destructive: true);
  if (!sure || !context.mounted) return false;
  try {
    await api.deleteThread(id);
    if (context.mounted) toast(context, 'Deleted');
    return true;
  } on Parity9cException catch (e) {
    if (context.mounted) toast(context, e.message, error: true);
    return false;
  }
}

/// Inbox: delete messages after a confirm that names how many. Returns how many went.
Future<int> deleteInboxMessages(BuildContext context, Parity9cApi api, List<String> ids) async {
  if (ids.isEmpty) return 0;
  final sure = await confirmDialog(context, 'Delete ${ids.length} message${ids.length > 1 ? 's' : ''} from the inbox?', 'The captured messages are removed. Anything already distilled from them stays.', action: 'Delete', destructive: true);
  if (!sure) return 0;
  var ok = 0;
  for (final id in ids) {
    try {
      if (await api.inboxDelete(id)) ok++;
    } on Parity9cException {
      // counted as not deleted below
    }
  }
  if (context.mounted) toast(context, 'Deleted $ok of ${ids.length}', error: ok != ids.length);
  return ok;
}

Future<void> runInboxBackfill(BuildContext context, Parity9cApi api) async {
  try {
    await api.inboxBackfill();
    if (context.mounted) toast(context, 'History backfill finished');
  } on Parity9cException catch (e) {
    if (context.mounted) toast(context, e.message, error: true);
  }
}

/// Google send: shows the recipient and subject first and sends only on the explicit tap.
Future<bool> confirmAndSendGoogle(BuildContext context, Parity9cApi api, GoogleDraft draft) async {
  final go = await confirmDialog(context, 'Send this reply?', googleSendPreview(draft), action: 'Send');
  if (!go || !context.mounted) return false;
  try {
    await api.googleSend(draft);
    if (context.mounted) toast(context, 'Reply sent');
    return true;
  } on Parity9cException catch (e) {
    if (context.mounted) toast(context, 'Failed: ${e.message}', error: true);
    return false;
  }
}

/// Projects: link an instance URL.
Future<void> projectUrlDialog(BuildContext context, Parity9cApi api, String id, {String current = ''}) async {
  final c = TextEditingController(text: current);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Link an instance'),
      content: TextField(key: const Key('project-url-field'), controller: c, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'URL')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(key: const Key('project-url-save'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    await api.setProjectUrl(id, c.text.trim());
    if (context.mounted) toast(context, 'Instance linked');
  } on Parity9cException catch (e) {
    if (context.mounted) toast(context, e.message, error: true);
  }
}

/// Spaces: check the registry against OneDrive. Read-only (`apply: false`), and says what drifted.
Future<void> spacesSyncCheck(BuildContext context, Parity9cApi api) async {
  try {
    final d = await api.spacesCheck();
    if (!context.mounted) return;
    if (d.inSync) {
      toast(context, d.line);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Registry drift'),
        content: SingleChildScrollView(
          child: Text([d.line, if (d.missingLocally.isNotEmpty) '\nNot in the registry:\n${d.missingLocally.join('\n')}', if (d.goneRemotely.isNotEmpty) '\nNo folder:\n${d.goneRemotely.join('\n')}'].join('\n'), key: const Key('drift-text')),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  } on Parity9cException catch (e) {
    if (context.mounted) toast(context, e.message, error: true);
  }
}

// ── Settings: Google connect ────────────────────────────────────────────────

class GoogleConnectCard extends StatefulWidget {
  const GoogleConnectCard({super.key, this.api, this.account = 'default'});
  final Parity9cApi? api;
  final String account;
  @override
  State<GoogleConnectCard> createState() => _GoogleConnectCardState();
}

class _GoogleConnectCardState extends State<GoogleConnectCard> {
  Parity9cApi? _api;
  GoogleDeviceCode? _code;
  String _status = '';
  bool _connected = false;
  Timer? _timer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _api ??= widget.api ?? parity9cFor(context);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => _status = 'Requesting a code from Google…');
    try {
      final c = await _api!.googleStart(widget.account);
      if (!mounted) return;
      setState(() {
        _code = c;
        _status = 'Open the link, enter the code and sign in.';
      });
      _timer?.cancel();
      _timer = Timer.periodic(Duration(seconds: c.pollIntervalSec), (_) => _poll(c));
    } on Parity9cException catch (e) {
      if (mounted) setState(() => _status = 'Failed: ${e.message}');
    }
  }

  Future<void> _poll(GoogleDeviceCode c) async {
    try {
      final p = await _api!.googlePoll(widget.account, c.deviceCode);
      if (!mounted) return;
      if (p.state == GooglePollState.waiting) return;
      _timer?.cancel();
      setState(() {
        _connected = p.state == GooglePollState.connected;
        _status = _connected ? 'Google account connected.' : 'Status: ${p.error}';
        if (_connected) _code = null;
      });
    } on Parity9cException {
      // keep polling; a dropped request is not a failed sign-in
    }
  }

  @override
  Widget build(BuildContext context) => Panel(
        key: const Key('google-connect'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Google', style: T.title),
          const SizedBox(height: 6),
          if (_code != null) ...[
            SelectableText(_code!.userCode, key: const Key('google-code'), style: T.mono.copyWith(fontSize: 22, fontWeight: FontWeight.w700)),
            SelectableText(_code!.verificationUri, key: const Key('google-link'), style: T.small),
          ],
          if (_status.isNotEmpty) Text(_status, key: const Key('google-status'), style: T.small.copyWith(color: _connected ? C.green : C.text2)),
          const SizedBox(height: 6),
          OutlinedButton(key: const Key('google-start'), onPressed: _start, child: Text(_connected ? 'Connect again' : 'Connect a Google account')),
        ]),
      );
}

// ── Settings: PIN ───────────────────────────────────────────────────────────

class PinCard extends StatefulWidget {
  const PinCard({super.key, this.api});
  final Parity9cApi? api;
  @override
  State<PinCard> createState() => _PinCardState();
}

class _PinCardState extends State<PinCard> {
  Parity9cApi? _api;
  final _new = TextEditingController(), _confirm = TextEditingController(), _check = TextEditingController();
  bool? _set;
  String _msg = '';
  bool _ok = false, _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_api != null) return;
    _api = widget.api ?? parity9cFor(context);
    _api!.pinIsSet().then((v) {
      if (mounted) setState(() => _set = v);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _new.dispose();
    _confirm.dispose();
    _check.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final problem = pinProblem(_new.text.trim(), _confirm.text.trim());
    if (problem != null) return setState(() { _msg = problem; _ok = false; });
    setState(() => _busy = true);
    try {
      await _api!.setPin(_new.text.trim());
      _new.clear();
      _confirm.clear();
      if (mounted) setState(() { _msg = 'PIN updated.'; _ok = true; _set = true; });
    } on Parity9cException catch (e) {
      if (mounted) setState(() { _msg = e.message; _ok = false; });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final pin = _check.text.trim();
    if (!RegExp(r'^\d{4,12}$').hasMatch(pin)) return setState(() { _msg = 'Enter your PIN.'; _ok = false; });
    final go = await confirmDialog(context, 'Check your PIN?', 'A wrong guess uses one of a small number of tries before the PIN locks.', action: 'Check');
    if (!go) return;
    setState(() => _busy = true);
    final r = await _api!.verifyPin(pin);
    _check.clear();
    if (mounted) setState(() { _msg = r.message; _ok = r.ok; _busy = false; });
  }

  @override
  Widget build(BuildContext context) => Panel(
        key: const Key('pin-card'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('PIN', style: T.title),
            const Spacer(),
            Text(_set == null ? '' : (_set! ? 'PIN set' : 'No PIN'), key: const Key('pin-badge'), style: T.small.copyWith(color: C.text3)),
          ]),
          TextField(key: const Key('pin-new'), controller: _new, obscureText: true, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'New PIN (4-12 digits)')),
          TextField(key: const Key('pin-confirm'), controller: _confirm, obscureText: true, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Confirm PIN')),
          Align(alignment: Alignment.centerLeft, child: TextButton(key: const Key('pin-save'), onPressed: _busy ? null : _save, child: const Text('Set / reset PIN'))),
          TextField(key: const Key('pin-check'), controller: _check, obscureText: true, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Check a PIN')),
          Align(alignment: Alignment.centerLeft, child: TextButton(key: const Key('pin-verify'), onPressed: _busy ? null : _verify, child: const Text('Check'))),
          if (_msg.isNotEmpty) Text(_msg, key: const Key('pin-message'), style: T.small.copyWith(color: _ok ? C.green : C.amber)),
        ]),
      );
}

// ── Identity: persona split and voice card ──────────────────────────────────

class PersonaVoiceSection extends StatefulWidget {
  const PersonaVoiceSection({super.key, this.api});
  final Parity9cApi? api;
  @override
  State<PersonaVoiceSection> createState() => _PersonaVoiceSectionState();
}

class _PersonaVoiceSectionState extends State<PersonaVoiceSection> {
  Parity9cApi? _api;
  PersonaSplit? _split;
  VoiceCard? _voice;
  String _day = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_api != null) return;
    _api = widget.api ?? parity9cFor(context);
    _loadSplit();
    _api!.voiceCard().then((v) {
      if (mounted) setState(() => _voice = v);
    }).catchError((_) {
      if (mounted) setState(() => _voice = const VoiceCard(error: 'Could not load.'));
    });
  }

  Future<void> _loadSplit() async {
    try {
      final s = await _api!.personaSplit(day: _day);
      if (mounted) setState(() => _split = s);
    } catch (e) {
      if (mounted) setState(() => _split = PersonaSplit(day: _day, error: e is Parity9cException ? e.message : 'Could not load.'));
    }
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Panel(
          key: const Key('persona-split'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('Persona split', style: T.title),
              const Spacer(),
              DropdownButton<String>(
                key: const Key('persona-day'),
                value: _day,
                items: [const DropdownMenuItem(value: '', child: Text('Today')), for (final d in const ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']) DropdownMenuItem(value: d, child: Text(d))],
                onChanged: (v) {
                  _day = v ?? '';
                  _loadSplit();
                },
              ),
            ]),
            if (_split == null) const MiniSpinner(size: 16),
            if (_split != null && _split!.error.isNotEmpty) Text(_split!.error, style: T.small.copyWith(color: C.amber)),
            if (_split != null) for (final l in _split!.lines) Text(l, style: T.small),
          ]),
        ),
        Panel(
          key: const Key('voice-card'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Voice card', style: T.title),
            if (_voice == null) const MiniSpinner(size: 16),
            if (_voice != null && _voice!.error.isNotEmpty) Text(_voice!.error, style: T.small.copyWith(color: C.amber)),
            if (_voice != null) for (final l in _voice!.lines) Text(l, style: T.small),
          ]),
        ),
      ]);
}
