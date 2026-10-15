import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../services/ledger_tools.dart';
import '../../theme.dart';
import '../views/learning_export_stub.dart' if (dart.library.io) '../views/learning_export_native.dart' as export_impl;
import 'common.dart';

LedgerApi _defaultApi(BuildContext context) => HubLedgerApi(AppScope.of(context).api);

String _err(Object e) => '$e'.replaceFirst('ApiException(0): ', '').replaceFirst('Exception: ', '');

/// One field of a small form.
class FieldSpec {
  const FieldSpec(this.id, this.label, {this.type = 'text', this.value = '', this.options = const [], this.hint = ''});
  final String id;
  final String label;

  /// text, number, date or select.
  final String type;
  final String value;
  final List<String> options;
  final String hint;
}

/// Asks for [fields] and returns what was typed, or null if cancelled. Nothing leaves the device here.
Future<Map<String, String>?> showFieldsDialog(BuildContext context, String title, List<FieldSpec> fields, {String confirm = 'Save'}) {
  final ctl = {for (final f in fields) f.id: TextEditingController(text: f.value)};
  final sel = {for (final f in fields) if (f.type == 'select') f.id: f.options.contains(f.value) ? f.value : (f.options.isEmpty ? '' : f.options.first)};
  return showDialog<Map<String, String>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final f in fields) ...[
              const SizedBox(height: 8),
              Text(f.label, style: T.small),
              if (f.type == 'select')
                DropdownButton<String>(
                  key: Key('field-${f.id}'),
                  isExpanded: true,
                  value: sel[f.id],
                  items: [for (final o in f.options) DropdownMenuItem(value: o, child: Text(o))],
                  onChanged: (v) => setState(() => sel[f.id] = v ?? ''),
                )
              else
                TextField(
                  key: Key('field-${f.id}'),
                  controller: ctl[f.id],
                  keyboardType: f.type == 'number' ? const TextInputType.numberWithOptions(decimal: true) : (f.type == 'date' ? TextInputType.datetime : TextInputType.text),
                  decoration: InputDecoration(isDense: true, border: const OutlineInputBorder(), hintText: f.type == 'date' ? 'YYYY-MM-DD' : null, helperText: f.hint.isEmpty ? null : f.hint),
                ),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            key: const Key('dialog-save'),
            onPressed: () => Navigator.pop(ctx, {for (final f in fields) f.id: (f.type == 'select' ? sel[f.id] ?? '' : ctl[f.id]!.text.trim())}),
            child: Text(confirm),
          ),
        ],
      ),
    ),
  );
}

Future<bool> _confirm(BuildContext context, String title, String body, String yes) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: C.red), onPressed: () => Navigator.pop(ctx, true), child: Text(yes)),
        ],
      ),
    ) ==
    true;

String money(double v, String cur) => '$cur ${v.round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',')}';

/// Shared state for a tab that loads, shows a message and reloads after a write.
mixin _Loads<W extends StatefulWidget> on State<W> {
  String? message;
  bool busy = false;

  Future<void> run(Future<String?> Function() job) async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final m = await job();
      if (mounted && m != null) setState(() => message = m);
    } catch (e) {
      if (mounted) setState(() => message = _err(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget msg() => message == null ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(message!, key: const Key('ledger-message'), style: T.small));
}

// ----------------------------------------------------------- accounts and goals

class AccountsTab extends StatefulWidget {
  const AccountsTab({super.key, this.api});
  final LedgerApi? api;

  @override
  State<AccountsTab> createState() => _AccountsTabState();
}

class _AccountsTabState extends State<AccountsTab> with _Loads<AccountsTab> {
  LedgerApi get _api => widget.api ?? _defaultApi(context);
  LedgerSummary? _s;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final s = await _api.summary();
      if (mounted) setState(() => _s = s);
    } catch (e) {
      if (mounted) setState(() => message = _err(e));
    }
  }

  Future<void> _add() async {
    final v = await showFieldsDialog(context, 'Add account', const [
      FieldSpec('name', 'Account name'),
      FieldSpec('type', 'Type', type: 'select', value: 'cash', options: accountTypes, hint: 'Debts subtract from net worth on their own: enter the balance as a positive number.'),
      FieldSpec('balance', 'Current balance', type: 'number', value: '0'),
    ]);
    if (v == null) return;
    if (v['name']!.isEmpty) {
      setState(() => message = 'A name would help.');
      return;
    }
    await run(() async {
      await _api.addAccount(name: v['name']!, type: v['type']!, balance: v['balance']!);
      await _load();
      return 'Account added.';
    });
  }

  Future<void> _balance(LedgerAccount a) async {
    final v = await showFieldsDialog(context, a.name, [FieldSpec('balance', 'New balance', type: 'number', value: a.balance)], confirm: 'Update');
    if (v == null || v['balance']!.isEmpty) return;
    await run(() async {
      await _api.setBalance(a.id, v['balance']!);
      await _load();
      return 'Balance noted. Net worth recalculated.';
    });
  }

  Future<void> _rename(LedgerAccount a) async {
    final v = await showFieldsDialog(context, 'Rename', [FieldSpec('name', 'Name', value: a.name)]);
    if (v == null || v['name']!.isEmpty || v['name'] == a.name) return;
    await run(() async {
      await _api.renameAccount(a.id, v['name']!);
      await _load();
      return 'Renamed.';
    });
  }

  Future<void> _goal() async {
    final v = await showFieldsDialog(context, 'Add goal', const [
      FieldSpec('title', 'Goal'),
      FieldSpec('target', 'Target amount', type: 'number', value: '0'),
      FieldSpec('due', 'Target date (optional)', type: 'date'),
    ]);
    if (v == null) return;
    if (v['title']!.isEmpty) {
      setState(() => message = 'Name the goal first.');
      return;
    }
    await run(() async {
      await _api.addGoal(title: v['title']!, target: v['target']!, due: v['due']!);
      await _load();
      return 'Goal added.';
    });
  }

  Future<void> _snapshot() => run(() async {
        final net = await _api.snapshot();
        return 'Position frozen${net.isEmpty ? '' : ': $net'}.';
      });

  @override
  Widget build(BuildContext context) {
    final s = _s;
    if (s == null) return message == null ? const Center(child: CircularProgressIndicator()) : ErrorRetry(message!, onRetry: _load);
    return ListView(padding: const EdgeInsets.fromLTRB(14, 8, 14, 96), children: [
      Wrap(spacing: 8, children: [
        OutlinedButton(key: const Key('add-account'), onPressed: busy ? null : _add, child: const Text('Add account')),
        OutlinedButton(key: const Key('add-goal'), onPressed: busy ? null : _goal, child: const Text('Add goal')),
        OutlinedButton(key: const Key('snapshot'), onPressed: busy ? null : _snapshot, child: const Text('Snapshot')),
      ]),
      msg(),
      const SectionLabel('Accounts'),
      if (s.accounts.isEmpty) Text('No accounts yet. Add cash, M-Pesa, bank, sacco, investments, and the debts too.', style: T.small),
      for (final a in s.accounts)
        Panel(
          key: Key('acct-${a.id}'),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a.name, style: T.body2),
                Text('${a.type}${a.institution.isEmpty ? '' : ', ${a.institution}'}${a.asOf.isEmpty ? '' : ', as of ${a.asOf}'}', style: T.tiny),
              ]),
            ),
            Text('${a.isDebt ? '-' : ''}${money(a.amount.abs(), s.currency)}', style: T.body2.copyWith(color: a.isDebt ? C.red : C.text)),
            IconButton(key: Key('bal-${a.id}'), tooltip: 'Update the balance', icon: const Icon(Icons.edit_outlined, size: 18), onPressed: busy ? null : () => _balance(a)),
            IconButton(key: Key('ren-${a.id}'), tooltip: 'Rename', icon: const Icon(Icons.drive_file_rename_outline, size: 18), onPressed: busy ? null : () => _rename(a)),
          ]),
        ),
      const SectionLabel('Goals'),
      if (s.goals.isEmpty) Text('No goals yet.', style: T.small),
      for (final g in s.goals)
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(g.title, style: T.body2),
            const SizedBox(height: 6),
            LinearProgressIndicator(value: g.share),
            Text('${money(g.current, s.currency)} of ${money(g.target, s.currency)}${g.due.isEmpty ? '' : ', by ${g.due}'}', style: T.tiny),
          ]),
        ),
    ]);
  }
}

// ----------------------------------------------------------- income

class IncomeTab extends StatefulWidget {
  const IncomeTab({super.key, this.api});
  final LedgerApi? api;

  @override
  State<IncomeTab> createState() => _IncomeTabState();
}

class _IncomeTabState extends State<IncomeTab> with _Loads<IncomeTab> {
  LedgerApi get _api => widget.api ?? _defaultApi(context);
  LedgerSummary? _s;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final s = await _api.summary();
      if (mounted) setState(() => _s = s);
    } catch (e) {
      if (mounted) setState(() => message = _err(e));
    }
  }

  Future<void> _add() async {
    final v = await showFieldsDialog(context, 'Add income stream', const [
      FieldSpec('name', 'Stream name'),
      FieldSpec('amount', 'Expected amount per cycle', type: 'number', value: '0'),
      FieldSpec('recurs', 'Recurs', type: 'select', value: 'monthly', options: ['monthly', 'weekly', 'once']),
      FieldSpec('day', 'Day it usually lands', type: 'number', hint: 'Monthly streams only. Late streams get flagged.'),
      FieldSpec('source', 'Source'),
      FieldSpec('match', 'Match word', hint: 'How ledger entries are recognised as this stream.'),
    ]);
    if (v == null) return;
    if (v['name']!.isEmpty) {
      setState(() => message = 'Name the stream first.');
      return;
    }
    await run(() async {
      await _api.addIncome(name: v['name']!, amount: v['amount']!, recurs: v['recurs']!, day: v['day']!, source: v['source']!, match: v['match']!);
      await _load();
      return 'Stream configured.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    if (s == null) return message == null ? const Center(child: CircularProgressIndicator()) : ErrorRetry(message!, onRetry: _load);
    return ListView(padding: const EdgeInsets.fromLTRB(14, 8, 14, 96), children: [
      Row(children: [
        OutlinedButton(key: const Key('add-income'), onPressed: busy ? null : _add, child: const Text('Add stream')),
        const SizedBox(width: 10),
        if (s.expectedMonthly > 0) Text('${money(s.expectedMonthly, s.currency)} expected monthly', style: T.tiny),
      ]),
      msg(),
      if (s.streams.isEmpty) Text('No streams configured. Start with the salary: the amount, the day it lands, and a match word.', style: T.small),
      for (final x in s.streams)
        Panel(
          key: Key('stream-${x.id}'),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(x.name, style: T.body2),
                Text('${x.source.isEmpty ? '' : '${x.source}, '}${x.dueDay > 0 ? 'by day ${x.dueDay}, ' : ''}${x.recurs}', style: T.tiny),
                Text(
                  x.paused
                      ? 'paused'
                      : x.overdue
                          ? 'not yet in: chase it'
                          : (x.received >= x.expected && x.expected > 0)
                              ? 'received'
                              : x.received > 0
                                  ? 'partial, ${money(x.received, s.currency)}'
                                  : 'expected',
                  style: T.tiny.copyWith(color: x.overdue ? C.red : C.text3),
                ),
              ]),
            ),
            Text(money(x.expected, s.currency), style: T.body2),
            TextButton(
              key: Key('toggle-${x.id}'),
              onPressed: busy
                  ? null
                  : () => run(() async {
                        await _api.setIncomeStatus(x.id, x.paused ? 'active' : 'paused');
                        await _load();
                        return null;
                      }),
              child: Text(x.paused ? 'Resume' : 'Pause'),
            ),
          ]),
        ),
    ]);
  }
}

// ----------------------------------------------------------- review

class ReviewTab extends StatefulWidget {
  const ReviewTab({super.key, this.api});
  final LedgerApi? api;

  @override
  State<ReviewTab> createState() => _ReviewTabState();
}

class _ReviewTabState extends State<ReviewTab> with _Loads<ReviewTab> {
  LedgerApi get _api => widget.api ?? _defaultApi(context);
  List<ReviewGroup>? _groups;
  final _picked = <String, String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final g = await _api.review();
      if (mounted) setState(() => _groups = g);
    } catch (e) {
      if (mounted) setState(() => message = _err(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups;
    if (groups == null) return message == null ? const Center(child: CircularProgressIndicator()) : ErrorRetry(message!, onRetry: _load);
    return ListView(padding: const EdgeInsets.fromLTRB(14, 8, 14, 96), children: [
      Text('Grouped by counterparty, biggest first. Pick the right category and save.', style: T.tiny),
      msg(),
      if (groups.isEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Nothing to clarify.', key: const Key('review-empty'), style: T.small)),
      for (final g in groups)
        Panel(
          key: Key('review-${g.vendor}'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(g.vendor, style: T.body2)),
              Text('${g.count}x', style: T.tiny),
              const SizedBox(width: 8),
              Text(money(g.total, 'KES'), style: T.body2),
            ]),
            if (g.sample.isNotEmpty) Text(g.sample, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.tiny),
            Row(children: [
              Expanded(
                child: DropdownButton<String>(
                  key: Key('review-cat-${g.vendor}'),
                  isExpanded: true,
                  value: _picked[g.vendor] ?? (reviewCategories.contains(g.category) ? g.category : reviewCategories.first),
                  items: [for (final c in reviewCategories) DropdownMenuItem(value: c, child: Text(c))],
                  onChanged: (v) => setState(() => _picked[g.vendor] = v ?? ''),
                ),
              ),
              FilledButton(
                key: Key('review-save-${g.vendor}'),
                onPressed: busy
                    ? null
                    : () => run(() async {
                          final to = _picked[g.vendor] ?? (reviewCategories.contains(g.category) ? g.category : reviewCategories.first);
                          final n = await _api.resolve(vendor: g.vendor, category: g.category, newCategory: to);
                          await _load();
                          return '$n transaction${n == 1 ? '' : 's'} moved to $to.';
                        }),
                child: const Text('Save'),
              ),
            ]),
          ]),
        ),
    ]);
  }
}

// ----------------------------------------------------------- report

/// The report on this device, and the hub's own save to OneDrive. Nothing here sends a figure to anyone.
class ReportTab extends StatefulWidget {
  const ReportTab({super.key, this.api, this.now});
  final LedgerApi? api;
  final DateTime Function()? now;

  @override
  State<ReportTab> createState() => _ReportTabState();
}

class _ReportTabState extends State<ReportTab> with _Loads<ReportTab> {
  LedgerApi get _api => widget.api ?? _defaultApi(context);
  late final Map<String, ReportPeriod> _presets = ReportPeriod.presets((widget.now ?? DateTime.now)());
  late String _period = _presets.keys.first;
  final _formats = <String, bool>{'pdf': true, 'csv': true, 'html': false};

  Future<void> _open(bool pdf) => run(() async {
        final f = await _api.report(_presets[_period]!, pdf: pdf);
        final name = f.filename.isEmpty ? (pdf ? 'report.pdf' : 'report.html') : f.filename;
        final ok = await export_impl.saveAndOpenExport(name, f.bytes, mime: pdf ? 'application/pdf' : 'text/html');
        return ok ? null : 'Saved, but nothing on this device opens that file.';
      });

  Future<void> _export() async {
    final chosen = [for (final e in _formats.entries) if (e.value) e.key];
    if (chosen.isEmpty) {
      setState(() => message = 'Pick a format.');
      return;
    }
    final ok = await _confirm(context, 'Save to your OneDrive?', 'The hub writes ${chosen.join(', ')} for "$_period" into your OneDrive vault. Nothing is sent to anyone else.', 'Save it');
    if (!ok) return;
    await run(() async {
      final files = await _api.exportToOneDrive(_presets[_period]!, chosen);
      return 'Saved to OneDrive: ${files.join(', ')}.';
    });
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.fromLTRB(14, 8, 14, 96), children: [
        Text('Period', style: T.small),
        DropdownButton<String>(
          key: const Key('report-period'),
          isExpanded: true,
          value: _period,
          items: [for (final k in _presets.keys) DropdownMenuItem(value: k, child: Text(k))],
          onChanged: (v) => setState(() => _period = v ?? _period),
        ),
        Wrap(spacing: 8, children: [
          OutlinedButton(key: const Key('report-pdf'), onPressed: busy ? null : () => _open(true), child: const Text('Open PDF')),
          OutlinedButton(key: const Key('report-html'), onPressed: busy ? null : () => _open(false), child: const Text('Open HTML')),
        ]),
        const SectionLabel('Export to OneDrive'),
        Wrap(spacing: 10, children: [
          for (final e in _formats.entries) FilterChip(label: Text(e.key), selected: e.value, onSelected: (v) => setState(() => _formats[e.key] = v)),
        ]),
        const SizedBox(height: 8),
        FilledButton(key: const Key('report-export'), onPressed: busy ? null : _export, child: const Text('Export to OneDrive')),
        msg(),
      ]);
}

// ----------------------------------------------------------- possessions and ventures

class AssetsTab extends StatefulWidget {
  const AssetsTab({super.key, this.api});
  final LedgerApi? api;

  @override
  State<AssetsTab> createState() => _AssetsTabState();
}

class _AssetsTabState extends State<AssetsTab> with _Loads<AssetsTab> {
  LedgerApi get _api => widget.api ?? _defaultApi(context);
  List<Possession>? _p;
  List<Venture>? _v;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load({bool refresh = false}) async {
    try {
      final p = await _api.possessions();
      final v = await _api.ventures(refresh: refresh);
      if (mounted) {
        setState(() {
          _p = p;
          _v = v;
        });
      }
    } catch (e) {
      if (mounted) setState(() => message = _err(e));
    }
  }

  List<FieldSpec> _pFields(Possession? p) => [
        FieldSpec('item', 'Item', value: p?.item ?? ''),
        FieldSpec('category', 'Category', value: p?.category ?? ''),
        FieldSpec('value', 'Value', type: 'number', value: p?.value ?? ''),
        FieldSpec('acquiredDate', 'Acquired', type: 'date', value: p?.acquired ?? ''),
        FieldSpec('location', 'Location', value: p?.location ?? ''),
        FieldSpec('condition', 'Condition', value: p?.condition ?? ''),
        FieldSpec('notes', 'Notes', value: p?.notes ?? ''),
      ];

  Future<void> _editPossession(Possession? p) async {
    final v = await showFieldsDialog(context, p == null ? 'Add possession' : 'Edit ${p.item}', _pFields(p));
    if (v == null) return;
    if (v['item']!.isEmpty) {
      setState(() => message = 'Name the item first.');
      return;
    }
    await run(() async {
      await _api.upsertPossession(v, id: p?.id ?? '');
      await _load();
      return p == null ? 'Possession registered.' : 'Possession updated.';
    });
  }

  Future<void> _deletePossession(Possession p) async {
    if (!await _confirm(context, 'Discard "${p.item}"?', 'This removes the possession row entirely.', 'Discard')) return;
    await run(() async {
      await _api.deletePossession(p.id);
      await _load();
      return 'Possession discarded.';
    });
  }

  List<FieldSpec> _vFields(Venture? v) => [
        FieldSpec('name', 'Venture name', value: v?.name ?? ''),
        FieldSpec('kind', 'Kind', type: 'select', value: v?.kind ?? 'saas', options: ventureKinds),
        FieldSpec('category', 'Category', type: 'select', value: v?.category.isEmpty ?? true ? '-' : v!.category, options: ventureCategories, hint: 'Leave as "-" if unsure. It is never guessed for you.'),
        FieldSpec('url', 'Metrics endpoint URL', value: v?.url ?? ''),
        FieldSpec('authSecret', 'Name of the secret for its auth token', value: v?.authSecret ?? '', hint: 'The name only, never the token itself.'),
        FieldSpec('renderUrl', 'Deployed URL', value: v?.renderUrl ?? ''),
        FieldSpec('github', 'GitHub repo', value: v?.github ?? ''),
        FieldSpec('folder', 'OneDrive folder', value: v?.folder ?? ''),
        FieldSpec('note', 'Note', value: v?.note ?? ''),
      ];

  Future<void> _editVenture(Venture? v) async {
    final f = await showFieldsDialog(context, v == null ? 'Register venture' : 'Edit ${v.name}', _vFields(v));
    if (f == null) return;
    if (f['name']!.isEmpty) {
      setState(() => message = 'Name the venture first.');
      return;
    }
    await run(() async {
      await _api.upsertVenture(f, id: v?.id ?? '');
      await _load(refresh: true);
      return v == null ? 'Venture registered.' : 'Venture updated.';
    });
  }

  Future<void> _deleteVenture(Venture v) async {
    if (!await _confirm(context, 'Discard "${v.name}"?', 'This removes the venture row entirely, not just a status flip.', 'Discard')) return;
    await run(() async {
      await _api.deleteVenture(v.id);
      await _load(refresh: true);
      return 'Venture discarded.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final ps = _p, vs = _v;
    if (ps == null || vs == null) return message == null ? const Center(child: CircularProgressIndicator()) : ErrorRetry(message!, onRetry: _load);
    return ListView(padding: const EdgeInsets.fromLTRB(14, 8, 14, 96), children: [
      msg(),
      Row(children: [
        const Expanded(child: SectionLabel('Possessions')),
        TextButton(key: const Key('add-possession'), onPressed: busy ? null : () => _editPossession(null), child: const Text('Add')),
      ]),
      if (ps.isEmpty) Text('Nothing registered yet. Track anything of value here: a laptop, a vehicle, equipment.', style: T.small),
      for (final p in ps)
        Panel(
          key: Key('poss-${p.id}'),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${p.item}${p.category.isEmpty ? '' : ', ${p.category}'}', style: T.body2),
                Text([p.value.isEmpty ? '' : 'KES ${p.value}', p.location, p.condition, p.acquired].where((x) => x.isNotEmpty).join(' Â· '), style: T.tiny),
              ]),
            ),
            TextButton(onPressed: busy ? null : () => _editPossession(p), child: const Text('Edit')),
            TextButton(key: Key('poss-del-${p.id}'), onPressed: busy ? null : () => _deletePossession(p), child: Text('Discard', style: TextStyle(color: C.red))),
          ]),
        ),
      Row(children: [
        const Expanded(child: SectionLabel('Ventures')),
        TextButton(
          key: const Key('discover'),
          onPressed: busy
              ? null
              : () => run(() async {
                    final n = await _api.discoverVentures();
                    await _load(refresh: true);
                    return n > 0 ? '$n new venture candidate${n == 1 ? '' : 's'} added. Assign categories.' : 'No new venture folders found.';
                  }),
          child: const Text('Sync from OneDrive'),
        ),
        TextButton(key: const Key('add-venture'), onPressed: busy ? null : () => _editVenture(null), child: const Text('Add')),
      ]),
      if (vs.isEmpty) Text('Nothing plugged in yet. Give a product a metrics endpoint returning flat JSON and add it here.', style: T.small),
      for (final v in vs)
        Panel(
          key: Key('vent-${v.id}'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('${v.name}, ${v.kind}${v.category.isEmpty ? ', category unset' : ', ${v.category}'}', style: T.body2)),
              TextButton(onPressed: busy ? null : () => _editVenture(v), child: const Text('Edit')),
              TextButton(key: Key('vent-del-${v.id}'), onPressed: busy ? null : () => _deleteVenture(v), child: Text('Discard', style: TextStyle(color: C.red))),
            ]),
            if (v.metrics.isNotEmpty) Wrap(spacing: 12, children: [for (final e in v.metrics.entries.take(8)) Text('${e.key}: ${e.value}', style: T.tiny)])
            else if (v.error.isNotEmpty) Text('unreachable: ${v.error}', style: T.tiny.copyWith(color: C.amber))
            else Text(v.url.isEmpty ? 'no endpoint configured yet' : 'no data yet', style: T.tiny),
          ]),
        ),
    ]);
  }
}
