import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../data/accounts_data.dart';
import '../../theme.dart';
import '../widgets/common.dart';
import '../widgets/space_header.dart';

/// BI26102401: the Accounts space in Systems. The shared search entry above exactly three tabs: Addresses (every email
/// address ever used, old and throwaway included), Sign-ups (what each address is signed up to) and AI seats (Claude and
/// agy accounts with live usage from slate). Passwords, codes and keys are never stored; only the Bitwarden item name is.
class AccountsSpace extends StatefulWidget {
  const AccountsSpace({super.key, this.api, this.clock});

  /// Overrides for tests; the app passes none and gets the live client.
  final AccountsApi? api;
  final DateTime Function()? clock;

  @override
  State<AccountsSpace> createState() => _AccountsSpaceState();
}

class _AccountsSpaceState extends State<AccountsSpace> {
  AccountsApi? _api;
  int _refresh = 0;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _api ??= widget.api ?? HttpAccountsApi(AppScope.of(context).api);
  }

  void _reload() => setState(() => _refresh++);

  @override
  Widget build(BuildContext context) {
    final api = _api!;
    return SpaceView(
      space: 'accounts',
      searchHint: 'Search addresses and sign-ups',
      onSearch: (ctx) => ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Use the filters on each tab.'))),
      tabs: [
        SpaceTab('Addresses', _AddressesTab(key: ValueKey('a$_refresh'), api: api, now: _now, onChanged: _reload)),
        SpaceTab('Sign-ups', _SignUpsTab(key: ValueKey('s$_refresh'), api: api, now: _now, onChanged: _reload)),
        SpaceTab('AI seats', _SeatsTab(key: ValueKey('t$_refresh'), api: api, now: _now)),
      ],
    );
  }
}

class _Loader<T> extends StatefulWidget {
  const _Loader({required this.load, required this.builder});
  final Future<T> Function() load;
  final Widget Function(BuildContext, T) builder;
  @override
  State<_Loader<T>> createState() => _LoaderState<T>();
}

class _LoaderState<T> extends State<_Loader<T>> {
  late final Future<T> _f = widget.load();
  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
        future: _f,
        builder: (ctx, snap) {
          if (snap.hasError) return EmptyState('Could not load', '${snap.error}', icon: Icons.cloud_off_rounded);
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          return widget.builder(ctx, snap.data as T);
        },
      );
}

Widget _card(List<Widget> children, {Key? key, bool dim = false}) => Opacity(
      opacity: dim ? 0.55 : 1,
      child: Container(
        key: key,
        margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: C.surface, border: Border.all(color: C.border), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      ),
    );

// ── Addresses ───────────────────────────────────────────────────────────────

class _AddressesTab extends StatelessWidget {
  const _AddressesTab({super.key, required this.api, required this.now, required this.onChanged});
  final AccountsApi api;
  final DateTime Function() now;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => _Loader<(List<AccountAddress>, BreachStatus)>(
        load: () async {
          final addrs = await api.addresses();
          BreachStatus b;
          try {
            b = await api.breaches();
          } on AccountsException {
            b = const BreachStatus();
          }
          return (addrs, b);
        },
        builder: (ctx, data) {
          final all = data.$1, breach = data.$2;
          final single = recoverySinglePoints(all);
          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(breach.line, key: const Key('breach-line'), style: T.small.copyWith(color: breach.enabled ? C.text2 : C.text3)),
              ),
              if (breach.fresh.isNotEmpty)
                _card(key: const Key('breach-notice'), [
                  for (final b in breach.fresh)
                    Text('New breach: ${b.breach} (${b.date == null ? 'date unknown' : b.date!.toIso8601String().substring(0, 10)}) exposed ${b.address}.', style: T.body2.copyWith(color: C.red)),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      key: const Key('breach-dismiss'),
                      onPressed: () async {
                        await api.markBreachesNotified();
                        onChanged();
                      },
                      child: const Text('Got it'),
                    ),
                  ),
                ]),
              for (final a in single)
                _card(key: Key('recovery-warning-$a'), [
                  Text('$a is the only recovery route for ${recoveryChain(all)[a]!.length} addresses.', style: T.body2.copyWith(color: C.amber)),
                ]),
              for (final a in all) _addressCard(a, breach.forAddress(a.address)),
              Padding(
                padding: const EdgeInsets.all(16),
                child: OutlinedButton.icon(
                  key: const Key('add-address'),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add an address'),
                  onPressed: () => _addDialog(ctx),
                ),
              ),
            ],
          );
        },
      );

  Widget _addressCard(AccountAddress a, List<Breach> breaches) => _card(key: Key('address-${a.address}'), dim: a.closedOut, [
        Text(a.address, style: T.body.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text([a.provider, a.purpose, a.status].where((s) => s.isNotEmpty).join(' · '), style: T.small.copyWith(color: C.text3)),
        if (!a.mine)
          Container(
            key: Key('not-mine-${a.address}'),
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: C.redBg, borderRadius: BorderRadius.circular(8)),
            child: Text('Not mine. Never write through this address.', style: T.small.copyWith(color: C.red, fontWeight: FontWeight.w700)),
          ),
        if (a.recoveryAddress.isNotEmpty || a.recoveryPhoneLast2.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Recovery: ${a.recoveryAddress}${a.recoveryPhoneLast2.isEmpty ? '' : ' · phone …${a.recoveryPhoneLast2}'}', style: T.small),
          ),
        if (a.twoFa.isNotEmpty) Text('2FA: ${a.twoFa}', style: T.small),
        if (breaches.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Breaches: ${breaches.map((b) => '${b.breach}${b.date == null ? '' : ' ${b.date!.toIso8601String().substring(0, 4)}'}').join(', ')}', key: Key('breaches-${a.address}'), style: T.small.copyWith(color: C.red)),
          ),
        if (a.bitwardenItem.isNotEmpty) Text('Bitwarden item: ${a.bitwardenItem}', style: T.small),
        if (a.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(a.note, style: T.small.copyWith(color: C.text2))),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(lastSeenLabel(a.lastSeen, a.lastSeenSource, now()), style: T.tiny.copyWith(color: C.text3)),
        ),
        if (staleForReview(a.lastSeen, now())) Text('Unseen for a year. Close or keep?', style: T.small.copyWith(color: C.amber)),
      ]);

  Future<void> _addDialog(BuildContext context) async {
    final addr = TextEditingController(), note = TextEditingController(), bw = TextEditingController();
    String purpose = 'personal';
    bool mine = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Add an address'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(key: const Key('field-address'), controller: addr, decoration: const InputDecoration(labelText: 'Address')),
              DropdownButton<String>(
                value: purpose,
                items: [for (final p in const ['work', 'personal', 'business', 'throwaway', 'legacy']) DropdownMenuItem(value: p, child: Text(p))],
                onChanged: (v) => set(() => purpose = v ?? purpose),
              ),
              SwitchListTile(title: const Text('Mine'), value: mine, onChanged: (v) => set(() => mine = v)),
              TextField(key: const Key('field-bitwarden'), controller: bw, decoration: const InputDecoration(labelText: 'Bitwarden item name (never the password)')),
              TextField(key: const Key('field-note'), controller: note, decoration: const InputDecoration(labelText: 'Note')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(key: const Key('save-address'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true || addr.text.trim().isEmpty || !context.mounted) return;
    try {
      await api.addAddress(AccountAddress(address: addr.text.trim(), purpose: purpose, mine: mine, bitwardenItem: bw.text.trim(), note: note.text.trim()));
      onChanged();
    } on AccountsException catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

// ── Sign-ups ────────────────────────────────────────────────────────────────

class _SignUpsTab extends StatefulWidget {
  const _SignUpsTab({super.key, required this.api, required this.now, required this.onChanged});
  final AccountsApi api;
  final DateTime Function() now;
  final VoidCallback onChanged;
  @override
  State<_SignUpsTab> createState() => _SignUpsTabState();
}

class _SignUpsTabState extends State<_SignUpsTab> {
  bool _paid = false, _soon = false;
  String _status = '';

  @override
  Widget build(BuildContext context) => _Loader<(List<SignUp>, List<SignUpSuggestion>)>(
        load: () async {
          final ups = await widget.api.signUps();
          List<SignUpSuggestion> sug;
          try {
            sug = await widget.api.suggestions();
          } on AccountsException {
            sug = const [];
          }
          return (ups, sug);
        },
        builder: (ctx, data) {
          final all = data.$1, suggestions = data.$2;
          final now = widget.now();
          final shown = [
            for (final s in all)
              if ((!_paid || s.costsMoney) && (!_soon || s.renewsWithin(30, now)) && (_status.isEmpty || s.status == _status)) s,
          ];
          final totals = monthlyTotals(all);
          final dueSoon = [for (final s in all) if (s.renewsWithin(14, now)) s];
          return ListView(
            children: [
              _suggestionCard(ctx, suggestions),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  totals.isEmpty ? 'No paid sign-ups' : 'Monthly: ${totals.entries.map((e) => '${e.key} ${e.value.toStringAsFixed(2)}').join(' · ')}',
                  key: const Key('monthly-total'),
                  style: T.body.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (dueSoon.isNotEmpty)
                _card(key: const Key('renewal-notice'), [
                  Text('Renews in the next 14 days: ${dueSoon.map((s) => s.service).join(', ')}', style: T.body2.copyWith(color: C.amber)),
                ]),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Wrap(spacing: 8, children: [
                  Pill('Costs money', key: const Key('filter-paid'), selected: _paid, onTap: () => setState(() => _paid = !_paid)),
                  Pill('Renews in 30 days', key: const Key('filter-soon'), selected: _soon, onTap: () => setState(() => _soon = !_soon)),
                  for (final st in const ['active', 'trial', 'cancelled', 'unknown'])
                    Pill(st, key: Key('filter-$st'), selected: _status == st, onTap: () => setState(() => _status = _status == st ? '' : st)),
                ]),
              ),
              if (shown.isEmpty) const EmptyState('No sign-ups', 'Add one, or import a list.', icon: Icons.mark_email_unread_rounded),
              for (final s in shown)
                _card(key: Key('signup-${s.service}-${s.address}'), [
                  Text(s.service, style: T.body.copyWith(fontWeight: FontWeight.w700)),
                  Text('${s.address} · ${s.status}${s.plan.isEmpty ? '' : ' · ${s.plan}'}', style: T.small.copyWith(color: C.text3)),
                  if (s.costsMoney) Text('${s.currency} ${s.monthlyCost.toStringAsFixed(2)} a month${s.renewal == null ? '' : ' · renews ${s.renewal!.toIso8601String().substring(0, 10)}'}', style: T.small),
                  Text('2FA ${s.twoFaOn ? 'on' : 'off'}${s.bitwardenItem.isEmpty ? '' : ' · Bitwarden: ${s.bitwardenItem}'}', style: T.small),
                  Text(lastSeenLabel(s.lastSeen, s.lastSeenSource, now), style: T.tiny.copyWith(color: C.text3)),
                  if (staleForReview(s.lastSeen, now)) Text('Unseen for a year. Close or keep?', style: T.small.copyWith(color: C.amber)),
                ]),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  OutlinedButton.icon(key: const Key('add-signup'), icon: const Icon(Icons.add_rounded), label: const Text('Add'), onPressed: () => _addDialog(ctx)),
                  OutlinedButton.icon(key: const Key('scan-mail'), icon: const Icon(Icons.mark_email_read_rounded), label: const Text('Scan mail'), onPressed: () => _scan(ctx)),
                  OutlinedButton.icon(key: const Key('import-signups'), icon: const Icon(Icons.upload_file_rounded), label: const Text('Import a list'), onPressed: () => _importDialog(ctx)),
                ]),
              ),
            ],
          );
        },
      );

  /// One suggestion at a time: Accept adds the sign-up (last seen = the last mail date, source mail), Not a sign-up
  /// never suggests it again, Later keeps it queued. Only the sender, subject and date were read; no mail text is shown.
  Widget _suggestionCard(BuildContext context, List<SignUpSuggestion> list) {
    if (list.isEmpty) return const SizedBox.shrink();
    final x = list.first;
    String day(DateTime? d) => d == null ? 'unknown' : d.toIso8601String().substring(0, 10);
    Future<void> act(String decision) async {
      try {
        await widget.api.decide(x.id, decision);
        widget.onChanged();
      } on AccountsException catch (e) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }

    return _card(key: Key('suggestion-${x.id}'), [
      Text('Found in your mail (${list.length} to look at)', style: T.small.copyWith(color: C.text3)),
      const SizedBox(height: 4),
      Text('${x.service} (${x.domain})', style: T.body.copyWith(fontWeight: FontWeight.w700)),
      Text('${x.address} · first mail ${day(x.firstMail)} · last mail ${day(x.lastMail)} · ${x.count} mails${x.paid ? ' · looks paid' : ''}', style: T.small),
      Wrap(children: [
        TextButton(key: const Key('suggestion-accept'), onPressed: () => act('accept'), child: const Text('Accept')),
        TextButton(key: const Key('suggestion-never'), onPressed: () => act('never'), child: const Text('Not a sign-up')),
        TextButton(key: const Key('suggestion-later'), onPressed: () => act('later'), child: const Text('Later')),
      ]),
    ]);
  }

  Future<void> _scan(BuildContext context) async {
    try {
      final r = await widget.api.scanMail();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(r.mailboxes == 0 ? 'No mailbox is connected.' : 'Scanned ${r.mailboxes} mailbox(es): ${r.added} new.${r.failed > 0 ? ' ${r.failed} failed.' : ''}'),
      ));
      widget.onChanged();
    } on AccountsException catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _addDialog(BuildContext context) async {
    final service = TextEditingController(), addr = TextEditingController(), cost = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add a sign-up'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(key: const Key('field-service'), controller: service, decoration: const InputDecoration(labelText: 'Service')),
          TextField(key: const Key('field-signup-address'), controller: addr, decoration: const InputDecoration(labelText: 'Address used')),
          TextField(key: const Key('field-cost'), controller: cost, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Monthly cost (USD)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(key: const Key('save-signup'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true || service.text.trim().isEmpty || !context.mounted) return;
    await widget.api.addSignUp(SignUp(service: service.text.trim(), address: addr.text.trim(), monthlyCost: double.tryParse(cost.text) ?? 0));
    widget.onChanged();
  }

  Future<void> _importDialog(BuildContext context) async {
    final text = TextEditingController();
    ImportPreview? preview;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Import a list'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Columns: address, service, plan, cost, renewal, note. Password columns are refused.'),
              TextField(key: const Key('import-text'), controller: text, maxLines: 6),
              if (preview != null)
                Text(preview!.ok ? '${preview!.rows.length} rows ready to add.' : preview!.refusal!, key: const Key('import-result'), style: TextStyle(color: preview!.ok ? C.text2 : C.red)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(key: const Key('import-preview'), onPressed: () => set(() => preview = AccountsImport.parse(text.text)), child: const Text('Preview')),
            TextButton(key: const Key('import-commit'), onPressed: preview?.ok == true ? () => Navigator.pop(ctx, true) : null, child: const Text('Add')),
          ],
        ),
      ),
    );
    if (go != true || preview == null || !preview!.ok) return;
    await widget.api.importSignUps(preview!.rows);
    widget.onChanged();
  }
}

// ── AI seats ────────────────────────────────────────────────────────────────

class _SeatsTab extends StatelessWidget {
  const _SeatsTab({super.key, required this.api, required this.now});
  final AccountsApi api;
  final DateTime Function() now;

  String _pct(double? v) => v == null ? 'no reading' : '${v.round()}%';

  @override
  Widget build(BuildContext context) => _Loader<List<AiSeat>>(
        load: api.seats,
        builder: (ctx, seats) => seats.isEmpty
            ? const EmptyState('No AI seats', 'Seats appear when slate reports an account.', icon: Icons.smart_toy_rounded)
            : ListView(children: [
                for (final s in seats)
                  _card(key: Key('seat-${s.account}'), [
                    Text('${s.account} (${s.provider})', style: T.body.copyWith(fontWeight: FontWeight.w700)),
                    Text([s.address, s.plan].where((x) => x.isNotEmpty).join(' · '), style: T.small.copyWith(color: C.text3)),
                    if (s.paidBy.isNotEmpty) Text('Paid by ${s.paidBy}', style: T.small),
                    Text('5-hour ${_pct(s.fiveHourPct)} · 7-day ${_pct(s.sevenDayPct)}', style: T.body2),
                    if (s.machine.isNotEmpty || s.sessionsToday > 0) Text('${s.machine.isEmpty ? '' : '${s.machine} · '}${s.sessionsToday} sessions today', style: T.small),
                  ]),
              ]),
      );
}
