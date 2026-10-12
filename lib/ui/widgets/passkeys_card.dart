import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../services/passkey_client.dart' show defaultPasskeyName;
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import 'common.dart';

/// BI26100204: Settings > Account > Passkeys. Add one to this phone, see them all, rename and revoke. Adding needs a
/// signed-in session (the server checks the token), and everything here needs the live server. The PIN is unaffected.

/// "added 12 Oct 2026 · last used never" from the server's ISO timestamps.
String passkeyWhen(dynamic iso) {
  final d = DateTime.tryParse(fmt.s(iso));
  if (d == null) return 'never';
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final l = d.toLocal();
  return '${l.day} ${m[l.month - 1]} ${l.year}';
}

/// Revoked passkeys come back in the list too; they show as revoked and offer nothing.
bool passkeyLive(Map<String, dynamic> p) => fmt.s(p['revokedAt']).isEmpty;

class PasskeysCard extends StatefulWidget {
  const PasskeysCard({super.key});

  @override
  State<PasskeysCard> createState() => _PasskeysCardState();
}

class _PasskeysCardState extends State<PasskeysCard> {
  List<Map<String, dynamic>>? _list;
  bool _supported = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final session = AppScope.of(context).session;
    final supported = await session.passkeys.available();
    List<Map<String, dynamic>>? list;
    try {
      list = await session.passkeyList();
    } catch (_) {
      list = null;
    }
    if (!mounted) return;
    setState(() {
      _supported = supported;
      _list = list;
      _error = list == null ? 'Could not read your passkeys.' : null;
    });
  }

  Future<void> _add() async {
    final name = TextEditingController(text: await defaultPasskeyName());
    if (!mounted) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add a passkey', style: T.title),
        content: TextField(key: const Key('passkey-name'), controller: name, autofocus: true, decoration: const InputDecoration(hintText: 'Name this passkey')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: T.body2.copyWith(color: C.text3))),
          FilledButton(key: const Key('passkey-add-go'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    );
    if (go != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await AppScope.of(context).session.addPasskey(name.text.trim().isEmpty ? 'My phone' : name.text.trim());
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
    if (err == null) {
      toast(context, 'Passkey added');
      await _load();
    }
  }

  Future<void> _rename(Map<String, dynamic> p) async {
    final c = TextEditingController(text: fmt.s(p['name']));
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Rename passkey', style: T.title),
        content: TextField(key: const Key('passkey-rename'), controller: c, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: T.body2.copyWith(color: C.text3))),
          FilledButton(key: const Key('passkey-rename-go'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (go != true || c.text.trim().isEmpty || !mounted) return;
    final err = await AppScope.of(context).session.renamePasskey(fmt.s(p['id']), c.text.trim());
    if (!mounted) return;
    if (err != null) toast(context, err, error: true);
    await _load();
  }

  Future<void> _revoke(Map<String, dynamic> p) async {
    final sure = await confirmDialog(
      context,
      'Revoke this passkey?',
      '"${fmt.s(p['name'])}" stops working at once. Your PIN is unaffected.',
      action: 'Revoke',
      destructive: true,
    );
    if (!sure || !mounted) return;
    final err = await AppScope.of(context).session.revokePasskey(fmt.s(p['id']));
    if (!mounted) return;
    if (err != null) toast(context, err, error: true);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _supported
                ? 'Sign in with this phone\'s screen lock instead of typing anything. The PIN keeps working.'
                : 'Passkeys need an Android phone with a screen lock set up.',
            style: T.small.copyWith(color: C.text2),
          ),
          if (list != null)
            for (final p in list)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  key: Key('passkey-${fmt.s(p['id'])}'),
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(passkeyLive(p) ? fmt.s(p['name']) : '${fmt.s(p['name'])} (revoked)', style: T.body2),
                          Text('added ${passkeyWhen(p['createdAt'])} · last used ${passkeyWhen(p['lastUsedAt'])}', style: T.monoSmall),
                        ],
                      ),
                    ),
                    if (passkeyLive(p)) ...[
                      TextButton(key: Key('passkey-rename-${fmt.s(p['id'])}'), onPressed: () => _rename(p), child: const Text('Rename')),
                      TextButton(key: Key('passkey-revoke-${fmt.s(p['id'])}'), onPressed: () => _revoke(p), child: Text('Revoke', style: T.body2.copyWith(color: C.red))),
                    ],
                  ],
                ),
              ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, key: const Key('passkey-error'), style: T.small.copyWith(color: C.red)),
          ],
          if (_supported) ...[
            const SizedBox(height: 10),
            OutlinedButton(
              key: const Key('passkey-add'),
              onPressed: _busy ? null : _add,
              child: Text(_busy ? 'Waiting for your phone...' : 'Add a passkey'),
            ),
          ],
        ],
      ),
    );
  }
}
