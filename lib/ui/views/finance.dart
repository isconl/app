import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../app_scope.dart';
import '../../data/ledger_data.dart';
import '../../theme.dart';
import '../../util/current_block.dart' show nairobiClock;
import '../../util/fmt.dart' as fmt;
import '../widgets/common.dart';
import 'ledger_tools.dart';
import '../widgets/space_header.dart';

/// Finance: KES, necessity/satisfaction scoring, recursive 50-30-20.
/// All numbers come from the vault - this view only formats them.
class FinanceView extends StatefulWidget {
  const FinanceView({super.key});

  @override
  State<FinanceView> createState() => _FinanceViewState();
}

class _FinanceViewState extends State<FinanceView> {
  /// BI26101808: the Ledger space is three tabs (Overview, Transactions, Plan) under a search over transactions,
  /// accounts and envelopes. Every section the old single scroll showed is in one of them.
  final _tabs = SpaceTabController();
  LedgerFilter _filter = const LedgerFilter();

  // The current month's rows (and next month's, when the week crosses a month): envelopes and bills are computed from them.
  TxPage? _month;
  bool _monthFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMonth());
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadMonth() async {
    final api = AppScope.of(context).api;
    final now = DateTime.now();
    final month = nairobiMonth(now);
    try {
      final data = LedgerData(api);
      final page = await data.transactions(LedgerFilter(month: month), limit: 500);
      final endMonth = weekEnd(now).substring(0, 7);
      final extra = endMonth == month ? null : await data.transactions(LedgerFilter(month: endMonth), limit: 200);
      if (!mounted) return;
      setState(() {
        _month = extra == null ? page : TxPage(items: [...page.items, ...extra.items], total: page.total, all: page.all, newest: page.newest, oldest: page.oldest, months: page.months, categories: page.categories);
        _monthFailed = false;
      });
    } catch (_) {
      if (mounted) setState(() => _monthFailed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return Stack(
      children: [
        SpaceView(
          space: 'ledger',
          searchHint: 'Search transactions, accounts and envelopes',
          controller: _tabs,
          onSearch: (ctx) => _openSearch(ctx),
          tabs: [
            SpaceTab('Overview', _financeTab(services, _overviewBody)),
            SpaceTab('Transactions', _transactionsTab(services)),
            SpaceTab('Plan', _financeTab(services, _planBody)),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FabStack(
            primary: FabAction(
              heroTag: 'tx',
              tooltip: 'Add a transaction',
              icon: Icons.add_rounded,
              onPressed: () => _addTxSheet(context),
            ),
            secondary: [
              FabAction(
                heroTag: 'paste',
                tooltip: 'Paste a message',
                icon: Icons.content_paste_rounded,
                onPressed: () => _pasteMessage(context),
              ),
              FabAction(
                heroTag: 'receipt',
                tooltip: 'Capture a receipt',
                icon: Icons.receipt_long_rounded,
                onPressed: () => _captureReceipt(context),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// A tab whose body comes from the finance summary snapshot.
  Widget _financeTab(AppServices services, Widget Function(BuildContext, Map<String, dynamic>) body) {
    return SnapshotView(
      snapshot: services.store.finance,
      builder: (context, data) => body(context, fmt.m(data)),
    );
  }

  /// Overview: net position and runway, safe to spend this week, the month, how fresh the book is, the envelopes, accounts.
  Widget _overviewBody(BuildContext context, Map<String, dynamic> fin) {
    final currency = fmt.s(fin['currency']).isEmpty ? 'KES' : fmt.s(fin['currency']);
    final net = fmt.m(fin['netWorth']);
    final month = fmt.m(fin['month']);
    final accounts = fmt.lm(fin['accounts']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _safeToSpendCard(fin, currency),
                // ---- headline numbers ----
                Row(
                  children: [
                    Expanded(
                      child: _stat('NET WORTH',
                          fmt.money(net['net'], currency: currency, compact: true),
                          C.greenBright),
                    ),
                    const SizedBox(width: Sz.gap),
                    Expanded(
                      child: _stat(
                          'RUNWAY',
                          fin['runwayMonths'] == null
                              ? '-'
                              : '${fmt.d(fin['runwayMonths']).toStringAsFixed(1)} mo',
                          C.cyan),
                    ),
                  ],
                ),
                const SizedBox(height: Sz.gap),
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('THIS MONTH · ${fmt.s(month['month'])}',
                          style: T.label),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _flow('In', month['income'], C.green, currency),
                          _flow('Out', month['expense'], C.red, currency),
                          _flow('Net', month['netFlow'],
                              fmt.d(month['netFlow']) >= 0 ? C.green : C.red,
                              currency),
                        ],
                      ),
                      if (month['savingsRate'] != null) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Text('Savings rate ',
                                style: T.small.copyWith(color: C.text3)),
                            Text(
                                '${(fmt.d(month['savingsRate']) * 100).toStringAsFixed(0)}%',
                                style: T.w600(
                                    T.small.copyWith(color: C.greenBright))),
                            const Spacer(),
                            if (fmt.i(month['lowNecessity']) > 0)
                              Badge2(
                                  '${fmt.i(month['lowNecessity'])} low-necessity',
                                  color: C.amberBg,
                                  textColor: C.amber),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
        _freshnessNote(),
        _envelopesCard(fin, currency),
                // ---- accounts ----
                if (accounts.isNotEmpty) ...[
                  const SectionLabel('Accounts'),
                  Panel(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var idx = 0; idx < accounts.length; idx++) ...[
                          if (idx > 0) const Divider(),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: Sz.pad, vertical: 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(fmt.s(accounts[idx]['NAME']),
                                          style: T.body2),
                                      Text(
                                        [
                                          fmt.s(accounts[idx]['TYPE']),
                                          fmt.s(accounts[idx]['INSTITUTION']),
                                          fmt.s(accounts[idx]['ASOF']).isEmpty ? 'no as-of date' : 'as of ${shortDateWords(fmt.s(accounts[idx]['ASOF']))}',
                                        ]
                                            .where((x) => x.isNotEmpty)
                                            .join(' · '),
                                        style: T.monoSmall,
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  fmt.money(accounts[idx]['BALANCE'],
                                      currency: currency),
                                  style: T.mono.copyWith(
                                      color:
                                          fmt.d(accounts[idx]['BALANCE']) < 0
                                              ? C.red
                                              : C.text),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
        _toolsLink(),
      ],
    );
  }

  /// Review, report and assets stay reachable from Overview (BI26101808: nothing is lost by folding the old tools in).
  Widget _toolsLink() => Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const Key('ledger-tools-link'),
          onPressed: () => Navigator.push<void>(context, MaterialPageRoute(builder: (_) => const LedgerToolsScreen())),
          icon: const Icon(Icons.build_circle_outlined, size: 16),
          label: const Text('Review, report and assets'),
        ),
      );

  /// Plan: the allocation, income streams, goals and the wishlist, and the sync line.
  Widget _planBody(BuildContext context, Map<String, dynamic> fin) {
    final currency = fmt.s(fin['currency']).isEmpty ? 'KES' : fmt.s(fin['currency']);
    final incomes = fmt.m(fin['incomes']);
    final streams = fmt.lm(incomes['streams']);
    final goals = fmt.lm(fin['goals']);
    final syncInfo = fmt.m(fin['sync']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _allocationPlan(fin, currency),
                // ---- income streams ----
                if (streams.isNotEmpty) ...[
                  const SectionLabel('Income streams'),
                  Panel(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var idx = 0; idx < streams.length; idx++) ...[
                          if (idx > 0) const Divider(),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: Sz.pad, vertical: 10),
                            child: Row(
                              children: [
                                StatusDot(
                                  fmt.b(streams[idx]['overdue'])
                                      ? C.red
                                      : fmt.d(streams[idx]['received']) > 0
                                          ? C.green
                                          : C.text3,
                                  size: 6,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(fmt.s(streams[idx]['NAME']),
                                          style: T.body2),
                                      if (fmt.b(streams[idx]['overdue']))
                                        Text('overdue',
                                            style: T.monoSmall
                                                .copyWith(color: C.red)),
                                    ],
                                  ),
                                ),
                                Text(
                                  fmt.money(
                                      fmt.d(streams[idx]['received']) > 0
                                          ? streams[idx]['received']
                                          : streams[idx]['expected'],
                                      currency: currency),
                                  style: T.mono.copyWith(
                                    color: fmt.d(streams[idx]['received']) > 0
                                        ? C.green
                                        : C.text3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                // ---- goals ----
                if (goals.isNotEmpty) ...[
                  const SectionLabel('Goals'),
                  ...goals.map((g) {
                    final target = fmt.d(g['TARGET']);
                    final current = fmt.d(g['CURRENT']);
                    final pct = target > 0
                        ? (current / target).clamp(0.0, 1.0)
                        : 0.0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Panel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                    child: Text(fmt.s(g['TITLE']),
                                        style: T.body2)),
                                Text(
                                    '${(pct * 100).toStringAsFixed(0)}%',
                                    style: T.mono
                                        .copyWith(color: C.greenBright)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                  value: pct, minHeight: 5),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${fmt.money(current, currency: currency)} of ${fmt.money(target, currency: currency)}'
                              '${fmt.s(g['DUE']).isNotEmpty ? ' · by ${fmt.shortDate(g['DUE'])}' : ''}',
                              style: T.monoSmall,
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
                // ---- wishlist ----
                _Wishlist(currency: currency),
                // ---- OneDrive sync status ----
                if (syncInfo.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      StatusDot(
                          fmt.s(syncInfo['status']) == 'synced'
                              ? C.green
                              : C.amber,
                          size: 5),
                      const SizedBox(width: 6),
                      Text(
                        'OneDrive ${fmt.s(syncInfo['status'])}'
                        '${fmt.s(syncInfo['at']).isNotEmpty ? ' · ${fmt.ago(syncInfo['at'])}' : ''}',
                        style: T.monoSmall,
                      ),
                    ],
                  ),
                ],
      ],
    );
  }



  // ---- BI26101808: the Ledger's own pieces -----------------------------------------------------------------------

  Envelopes? _envelopes(Map<String, dynamic> fin) =>
      envelopesFrom(fin['allocation'], _month?.items ?? const [], nairobiMonth(DateTime.now()));

  String _money(num v, String currency) => fmt.money(v, currency: currency, compact: false);

  /// Safe to spend this week: the envelopes left minus unassigned spend minus bills due by Sunday. Tap for the arithmetic.
  Widget _safeToSpendCard(Map<String, dynamic> fin, String currency) {
    final now = DateTime.now();
    Widget shell(Widget body, {VoidCallback? onTap}) => Padding(
          padding: const EdgeInsets.only(bottom: Sz.gap),
          child: Panel(key: const Key('safe-to-spend'), onTap: onTap, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('SAFE TO SPEND THIS WEEK', style: T.label), const SizedBox(height: 6), body])),
        );
    if (_month == null) {
      return shell(Text(_monthFailed ? 'Could not read this month\'s transactions. Pull down to retry.' : 'Reading this month...', style: T.small.copyWith(color: C.text3)));
    }
    final env = _envelopes(fin);
    final r = safeToSpend(envelopes: env, bills: billsFrom(_month!.items, now), now: now);
    if (r == null) {
      return shell(Text('Needs an allocation. No 50-30-20 model is set up yet (a reference income and the shares), so there is no figure to show.',
          style: T.small.copyWith(color: C.text3)));
    }
    return shell(
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(r.short ? '-${_money(-r.value, currency)}' : _money(r.value, currency),
            key: const Key('safe-to-spend-value'), style: T.headline.copyWith(fontSize: 24, color: r.short ? C.red : C.greenBright)),
        const SizedBox(height: 2),
        Text(r.short ? 'Short by ${_money(-r.value, currency)} until ${shortDateWords(r.goodUntil)}' : 'Good until Sunday ${shortDateWords(r.goodUntil)}', style: T.monoSmall.copyWith(color: r.short ? C.red : C.text3)),
      ]),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        backgroundColor: C.panel,
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('How this is worked out', style: T.title),
              const SizedBox(height: 10),
              _sum('Needs and wants left', _money(r.spendableLeft, currency)),
              _sum('Spend no envelope claimed', '-${_money(r.unassigned, currency)}'),
              for (final b in r.bills) _sum('${b.name} (${shortDateWords(b.date)})', '-${_money(b.amount, currency)}'),
              if (r.bills.isEmpty) _sum('Bills due by Sunday', 'none'),
              const Divider(),
              _sum('Safe to spend', _money(r.value, currency), bold: true),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _sum(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(label, style: bold ? T.w600(T.body2) : T.body2)),
          Text(value, style: bold ? T.w600(T.mono) : T.mono),
        ]),
      );

  /// Amber when the book has gone quiet: the newest transaction is more than a week old.
  Widget _freshnessNote() {
    final newest = _month?.newest;
    final days = daysSince(newest, nairobiClock(DateTime.now()));
    if (days == null || days <= 7) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: Sz.gap),
      child: Container(
        key: const Key('ledger-stale'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: C.amberBg, border: Border.all(color: C.amber.withValues(alpha: 0.4)), borderRadius: BorderRadius.circular(Sz.rMd)),
        child: Text('Last transaction ${shortDateWords(newest!)}, $days days ago. Nothing has been recorded since: import a statement or let the SMS ingest run.',
            style: T.small.copyWith(color: C.amber)),
      ),
    );
  }

  /// This month's envelopes as bars (spent against the allocation); tapping a line opens its transactions.
  Widget _envelopesCard(Map<String, dynamic> fin, String currency) {
    final env = _envelopes(fin);
    Widget shell(List<Widget> children) => Padding(
          padding: const EdgeInsets.only(bottom: Sz.gap),
          child: Panel(key: const Key('envelopes'), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children)),
        );
    if (env == null) {
      return shell([
        Text('ENVELOPES', style: T.label),
        const SizedBox(height: 6),
        Text('No allocation model is set up, so there are no envelopes to show. They are the 50-30-20 split of income (needs, wants, security) into housing, food, utilities and the rest.',
            style: T.small.copyWith(color: C.text3)),
      ]);
    }
    Widget bar(String label, double spent, double allocated, {String? category, bool top = false}) {
      final over = allocated > 0 && spent > allocated;
      final pct = allocated > 0 ? (spent / allocated).clamp(0.0, 1.0) : 0.0;
      return InkWell(
        key: Key('envelope-${category ?? label}'),
        onTap: category == null ? null : () {
          setState(() => _filter = LedgerFilter(category: category, month: env.month));
          _tabs.select(1);
        },
        child: Padding(
          padding: EdgeInsets.only(top: top ? 10 : 4, bottom: 4, left: top ? 0 : 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(label, style: top ? T.w600(T.small) : T.small)),
              Text('${_money(spent, currency)} of ${_money(allocated, currency)}', style: T.monoSmall.copyWith(color: over ? C.red : C.text3)),
            ]),
            const SizedBox(height: 3),
            ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(value: pct, minHeight: 5, backgroundColor: C.border, valueColor: AlwaysStoppedAnimation(over ? C.red : C.green))),
          ]),
        ),
      );
    }
    String pretty(String n) => n.isEmpty ? n : '${n[0].toUpperCase()}${n.substring(1).replaceAll('-', ' ')}';
    return shell([
      Row(children: [
        Expanded(child: Text('ENVELOPES · ${env.month}', style: T.label)),
        Text(env.planned ? 'on expected income' : 'on income received', style: T.tiny.copyWith(color: C.text3)),
      ]),
      for (final e in env.envelopes) ...[
        bar(pretty(e.name), e.spent, e.allocated, top: true),
        for (final l in e.lines) bar(pretty(l.name), l.spent, l.allocated, category: l.name),
      ],
      if (env.unassigned > 0) ...[
        const SizedBox(height: 8),
        Text('${_money(env.unassigned, currency)} spent this month in no envelope (blank or unknown category).', key: const Key('envelope-unassigned'), style: T.tiny.copyWith(color: C.amber)),
      ],
    ]);
  }

  /// Plan: the allocation as amounts (the model the envelopes are drawn from).
  Widget _allocationPlan(Map<String, dynamic> fin, String currency) {
    final a = fmt.m(fin['allocation']);
    final buckets = fmt.lm(a['buckets']);
    return Padding(
      padding: const EdgeInsets.only(bottom: Sz.gap),
      child: Panel(
        key: const Key('allocation-plan'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('ALLOCATION · RECURSIVE 50-30-20', style: T.label),
          const SizedBox(height: 6),
          if (buckets.isEmpty)
            Text('No allocation model is set up. Give it a reference income (and the shares, if they are not 50, 30 and 20) and the envelopes appear here and on Overview.',
                style: T.small.copyWith(color: C.text3))
          else ...[
            Text(a['planned'] == true ? 'Planned on the expected ${_money(fmt.d(a['base']), currency)}' : 'On ${_money(fmt.d(a['base']), currency)} income this month', style: T.monoSmall.copyWith(color: C.text3)),
            for (final b in buckets) ...[
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: Text(fmt.s(b['name']).toUpperCase(), style: T.w600(T.small))),
                Text('${(fmt.d(b['share']) * 100).round()}% · ${_money(fmt.d(b['amount']), currency)}', style: T.mono),
              ]),
              for (final c in fmt.lm(b['children']))
                Padding(
                  padding: const EdgeInsets.only(left: 10, top: 2),
                  child: Row(children: [
                    Expanded(child: Text(fmt.s(c['name']).replaceAll('-', ' '), style: T.small.copyWith(color: C.text2))),
                    Text(_money(fmt.d(c['amount']), currency), style: T.monoSmall),
                  ]),
                ),
            ],
          ],
        ]),
      ),
    );
  }

  /// Transactions: the whole book, newest first, filtered by account, envelope (category), month and type.
  Widget _transactionsTab(AppServices services) => _TransactionsTab(
        key: ValueKey('tx-${_filter.hashCode}'),
        data: LedgerData(services.api),
        filter: _filter,
        accounts: fmt.lm(fmt.m(services.store.finance.value)['accounts']),
        onFilter: (f) => setState(() => _filter = f),
      );

  Future<void> _openSearch(BuildContext ctx) async {
    final fin = fmt.m(AppScope.of(ctx).store.finance.value);
    final pick = await Navigator.push<LedgerFilter>(
      ctx,
      MaterialPageRoute(
        builder: (_) => _LedgerSearchScreen(
          data: LedgerData(AppScope.of(ctx).api),
          accounts: fmt.lm(fin['accounts']),
          envelopeNames: [
            for (final b in fmt.lm(fmt.m(fin['allocation'])['buckets'])) for (final c in fmt.lm(b['children'])) fmt.s(c['name']),
          ],
        ),
      ),
    );
    if (pick != null && mounted) {
      setState(() => _filter = pick);
      _tabs.select(1);
    }
  }

  Widget _stat(String label, String value, Color color) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: T.label),
          const SizedBox(height: 6),
          Text(value,
              style: T.headline.copyWith(color: color, fontSize: 17)),
        ],
      ),
    );
  }

  Widget _flow(String label, dynamic value, Color color, String currency) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: T.monoSmall),
          const SizedBox(height: 2),
          Text(fmt.money(value, currency: currency, compact: true),
              style: T.mono.copyWith(color: color, fontSize: 12.5)),
        ],
      ),
    );
  }

  /// Paste any money message - an M-Pesa text, a bank alert, a paybill
  /// confirmation - and let the agent distil it into a transaction. The parse
  /// is the server's (one parser of record, idempotent on the code), so this
  /// only carries the text there and reports what actually landed.
  Future<void> _pasteMessage(BuildContext context) async {
    final controller = TextEditingController();
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    final pre = clip?.text?.trim() ?? '';
    if (pre.isNotEmpty) controller.text = pre;
    if (!context.mounted) return;
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Sz.rXl)),
        side: BorderSide(color: C.border),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Distil a message', style: T.headline.copyWith(fontSize: 16)),
            const SizedBox(height: 4),
            Text(
              'Paste an M-Pesa text or bank alert. The agent reads the amount, '
              'the counterparty and the code, and files it once - online.',
              style: T.monoSmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: pre.isEmpty,
              minLines: 3,
              maxLines: 6,
              style: T.body2,
              decoration: const InputDecoration(
                hintText:
                    'e.g. TAB1A2B3C4 Confirmed. Ksh1,500.00 sent to JOHN DOE …',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Distil into a record'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (text == null || text.isEmpty || !context.mounted) return;
    final services = AppScope.of(context);
    toast(context, 'Reading the message…');
    final res = await services.mutations.distillMessage(text);
    if (!context.mounted) return;
    if (res.queued) {
      toast(context, 'Message queued - it will file on reconnect');
      return;
    }
    if (!res.ok) {
      toast(context, res.error!, error: true);
      return;
    }
    final map = fmt.m(res.payload);
    final written = fmt.d(map['written']).toInt();
    if (written > 0) {
      toast(context, written == 1 ? 'Filed 1 record' : 'Filed $written records');
    } else {
      toast(context, 'No transaction found in that message', error: true);
    }
  }

  /// Camera/gallery receipt -> /api/finance/receipt (native capability).
  Future<void> _captureReceipt(BuildContext context) async {
    final services = AppScope.of(context);
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: C.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Sz.rXl)),
        side: BorderSide(color: C.border),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              dense: true,
              leading: const Icon(Icons.photo_camera_rounded, size: 18),
              title: Text('Photograph receipt', style: T.body2),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.photo_library_rounded, size: 18),
              title: Text('Pick from gallery', style: T.body2),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null || !context.mounted) return;
    final picker = ImagePicker();
    final file = await picker.pickImage(
        source: source, maxWidth: 2000, imageQuality: 82);
    if (file == null || !context.mounted) return;
    final bytes = await file.readAsBytes();
    if (bytes.length > 5 * 1024 * 1024) {
      if (context.mounted) {
        toast(context, 'Image too large (max ~5 MB).', error: true);
      }
      return;
    }
    if (!context.mounted) return;
    toast(context, 'Filing receipt…');
    final res = await services.mutations.fileReceipt(
      base64Content: base64Encode(bytes),
      name: 'receipt-${DateTime.now().millisecondsSinceEpoch}.jpg',
      contentType: 'image/jpeg',
    );
    if (!context.mounted) return;
    if (!res.ok) {
      toast(context, res.error!, error: true);
    } else {
      toast(
          context,
          res.queued
              ? 'Receipt queued - will file on reconnect'
              : 'Receipt filed');
    }
  }

  Future<void> _addTxSheet(BuildContext context) {
    final amount = TextEditingController();
    final desc = TextEditingController();
    final category = TextEditingController();
    final account = TextEditingController();
    var type = 'expense';
    var necessity = 5.0;
    var satisfaction = 5.0;
    final services = AppScope.of(context);

    return showFormSheet(
      context,
      title: 'New transaction',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Segmented(
              options: const ['expense', 'income', 'transfer'],
              value: type,
              onChanged: (v) => setSheet(() => type = v),
            ),
            Field(
                label: 'Amount (KES)',
                controller: amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                autofocus: true),
            Field(label: 'Description', controller: desc),
            Field(label: 'Category', controller: category, hint: 'e.g. food'),
            Field(label: 'Account (optional)', controller: account),
            if (type == 'expense') ...[
              _slider(ctx, 'Necessity', necessity,
                  (v) => setSheet(() => necessity = v)),
              _slider(ctx, 'Satisfaction', satisfaction,
                  (v) => setSheet(() => satisfaction = v)),
            ],
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () async {
                final amt = fmt.dOrNull(amount.text);
                if (amt == null || amt <= 0) return;
                Navigator.pop(ctx);
                final res = await services.mutations.addTransaction({
                  'type': type,
                  'amount': amt,
                  if (desc.text.trim().isNotEmpty)
                    'description': desc.text.trim(),
                  if (category.text.trim().isNotEmpty)
                    'category': category.text.trim(),
                  if (account.text.trim().isNotEmpty)
                    'account': account.text.trim(),
                  if (type == 'expense') 'necessity': necessity.round(),
                  if (type == 'expense')
                    'satisfaction': satisfaction.round(),
                });
                if (!context.mounted) return;
                if (!res.ok) {
                  toast(context, res.error!, error: true);
                } else {
                  toast(
                      context,
                      res.queued
                          ? 'Transaction queued - will sync'
                          : 'Recorded');
                }
              },
              child: const Text('Record'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _slider(BuildContext context, String label, double value,
      void Function(double) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label.toUpperCase(),
                style: T.label.copyWith(letterSpacing: 0.6)),
            const Spacer(),
            Text('${value.round()}/10',
                style: T.mono.copyWith(color: C.greenBright)),
          ],
        ),
        Slider(
          value: value,
          min: 1,
          max: 10,
          divisions: 9,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// The wishlist: wants, scored before they are bought.
///
/// His finance system scores every want on necessity and satisfaction, 1 to 10,
/// precisely so the decision is made in a calm moment rather than at the till.
/// Capturing that here, on the device he actually has in a shop, is the point.
///
/// The numbers are his, not the model's: nothing on this screen is inferred,
/// and the totals are plain arithmetic over what he entered.
class _Wishlist extends StatefulWidget {
  const _Wishlist({required this.currency});
  final String currency;

  @override
  State<_Wishlist> createState() => _WishlistState();
}

class _WishlistState extends State<_Wishlist> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final snap = AppScope.of(context).store.wishlist;
      snap.hydrate().then((_) {
        if (mounted && snap.value == null) snap.refresh();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return ListenableBuilder(
      listenable: services.store.wishlist,
      builder: (context, _) {
        final items = fmt.lm(fmt.m(services.store.wishlist.value)['items'])
            .where((i) => fmt.s(i['status']) != 'bought')
            .toList();
        final total = items.fold<double>(0, (sum, i) => sum + fmt.d(i['cost']));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionLabel(
              'Wishlist${items.isEmpty ? '' : ' · ${fmt.money(total, currency: widget.currency, compact: true)}'}',
              trailing: InkWell(
                onTap: () => _addSheet(context),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Icon(Icons.add_rounded, size: 17, color: C.text2),
                ),
              ),
            ),
            if (items.isEmpty)
              Panel(
                child: Text(
                  'Nothing on the list. Score a want here before you buy it, '
                  'not after.',
                  style: T.small.copyWith(color: C.text3),
                ),
              )
            else
              ...items.map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _WishTile(item: item, currency: widget.currency),
                  )),
          ],
        );
      },
    );
  }

  Future<void> _addSheet(BuildContext context) {
    final name = TextEditingController();
    final cost = TextEditingController();
    final note = TextEditingController();
    var necessity = 5.0;
    var satisfaction = 5.0;
    final services = AppScope.of(context);

    return showFormSheet(
      context,
      title: 'Add to wishlist',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Field(label: 'What', controller: name, autofocus: true),
            Field(
                label: 'Cost (${widget.currency})',
                controller: cost,
                keyboardType: TextInputType.number),
            _score('Necessity', necessity,
                (v) => setSheet(() => necessity = v)),
            _score('Satisfaction', satisfaction,
                (v) => setSheet(() => satisfaction = v)),
            Field(label: 'Note', controller: note, hint: 'optional'),
            const SizedBox(height: 4),
            FilledButton(
              onPressed: () async {
                if (name.text.trim().isEmpty) return;
                Navigator.pop(ctx);
                final res = await services.mutations.saveWishlistItem({
                  'name': name.text.trim(),
                  'cost': double.tryParse(cost.text.trim()) ?? 0,
                  'necessity': necessity.round(),
                  'satisfaction': satisfaction.round(),
                  if (note.text.trim().isNotEmpty) 'note': note.text.trim(),
                  'status': 'open',
                });
                if (!context.mounted) return;
                if (!res.ok) {
                  toast(context, res.error!, error: true);
                } else if (res.queued) {
                  toast(context, 'Queued - will sync');
                } else {
                  toast(context, 'Added to the wishlist');
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _score(String label, double value, void Function(double) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label.toUpperCase(),
                style: T.label.copyWith(letterSpacing: 0.6)),
            const Spacer(),
            Text('${value.round()}/10',
                style: T.mono.copyWith(color: C.greenBright)),
          ],
        ),
        Slider(
            value: value, min: 1, max: 10, divisions: 9, onChanged: onChanged),
      ],
    );
  }
}

class _WishTile extends StatelessWidget {
  const _WishTile({required this.item, required this.currency});
  final Map<String, dynamic> item;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final necessity = fmt.i(item['necessity']);
    final satisfaction = fmt.i(item['satisfaction']);
    // Both scores high is a buy; both low is a no. The colour says which
    // without him having to do the comparison again.
    final score = necessity + satisfaction;
    final tone = score >= 15
        ? C.greenBright
        : score >= 10
            ? C.amber
            : C.text3;

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text(fmt.s(item['name']),
                      style: T.w500(T.body2.copyWith(color: C.text)))),
              Text(fmt.money(item['cost'], currency: currency),
                  style: T.mono.copyWith(color: tone)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Badge2('necessity $necessity'),
              const SizedBox(width: 6),
              Badge2('satisfaction $satisfaction'),
            ],
          ),
          if (fmt.s(item['note']).isNotEmpty) ...[
            const SizedBox(height: 7),
            Text(fmt.s(item['note']), style: T.small.copyWith(color: C.text3)),
          ],
        ],
      ),
    );
  }
}

// ---- BI26101808: the Transactions tab and the Ledger search -------------------------------------------------------

/// The full book, newest first, with filters. Filter changes go up to the space, which remounts this tab on the new filter.
class _TransactionsTab extends StatefulWidget {
  const _TransactionsTab({super.key, required this.data, required this.filter, required this.accounts, required this.onFilter});
  final LedgerData data;
  final LedgerFilter filter;
  final List<Map<String, dynamic>> accounts;
  final ValueChanged<LedgerFilter> onFilter;

  @override
  State<_TransactionsTab> createState() => _TransactionsTabState();
}

class _TransactionsTabState extends State<_TransactionsTab> {
  static const _pageSize = 60;
  final List<Tx> _items = [];
  TxPage? _page;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.data.transactions(widget.filter, limit: _pageSize, offset: reset ? 0 : _items.length);
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(page.items);
        _page = page;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e'.replaceAll(RegExp(r'\s+'), ' ');
      });
    }
  }

  String _accountName(String id) {
    for (final a in widget.accounts) {
      if (fmt.s(a['ID']) == id) return fmt.s(a['NAME']);
    }
    return id;
  }

  Widget _filters() {
    final f = widget.filter;
    final page = _page;
    Widget drop(String label, String value, List<(String, String)> options, ValueChanged<String> onPick, Key key) => DropdownButton<String>(
          key: key,
          value: options.any((o) => o.$1 == value) ? value : '',
          isDense: true,
          underline: const SizedBox.shrink(),
          style: T.small.copyWith(color: C.text2),
          dropdownColor: C.panel,
          items: [
            DropdownMenuItem(value: '', child: Text(label, style: T.small.copyWith(color: C.text3))),
            for (final o in options.where((o) => o.$1.isNotEmpty)) DropdownMenuItem(value: o.$1, child: Text(o.$2)),
          ],
          onChanged: (v) => onPick(v ?? ''),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      child: Wrap(spacing: 14, runSpacing: 0, crossAxisAlignment: WrapCrossAlignment.center, children: [
        drop('Any month', f.month, [for (final m in page?.months ?? const <String>[]) (m, m)], (v) => widget.onFilter(f.copyWith(month: v)), const Key('tx-filter-month')),
        drop('Any account', f.account, [for (final a in widget.accounts) (fmt.s(a['ID']), fmt.s(a['NAME']))], (v) => widget.onFilter(f.copyWith(account: v)), const Key('tx-filter-account')),
        drop('Any envelope', f.category, [for (final c in page?.categories ?? const <String>[]) (c, c)], (v) => widget.onFilter(f.copyWith(category: v)), const Key('tx-filter-category')),
        drop('In and out', f.type, const [('expense', 'Out'), ('income', 'In'), ('transfer', 'Transfers')], (v) => widget.onFilter(f.copyWith(type: v)), const Key('tx-filter-type')),
        if (!f.isEmpty) TextButton(key: const Key('tx-filter-clear'), onPressed: () => widget.onFilter(const LedgerFilter()), child: const Text('Clear')),
      ]),
    );
  }

  Widget _row(Tx t) {
    final income = t.isIncome;
    return InkWell(
      key: Key('tx-${t.id}'),
      onTap: () => showTransactionSheet(context, t, _accountName(t.accountId)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Sz.pad, vertical: 9),
        child: Row(children: [
          Icon(income ? Icons.south_west_rounded : (t.type == 'transfer' ? Icons.swap_horiz_rounded : Icons.north_east_rounded), size: 14, color: income ? C.green : C.text3),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.description.isEmpty ? (t.category.isEmpty ? '(no description)' : t.category) : t.description, style: T.small, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text([t.date, t.category].where((x) => x.isNotEmpty).join(' · '), style: T.monoSmall),
            ]),
          ),
          Text(fmt.money(t.amount, currency: t.currency.isEmpty ? 'KES' : t.currency), style: T.mono.copyWith(color: income ? C.green : C.text2)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    final shown = _items.length;
    final total = page?.total ?? 0;
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      color: C.green,
      backgroundColor: C.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 96),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _filters(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
            child: Text(
              _error != null ? 'Could not load transactions: $_error' : (page == null ? 'Loading...' : '$shown of $total${widget.filter.isEmpty ? '' : ' matching'}${page.newest == null ? '' : ' · newest ${shortDateWords(page.newest!)}'}'),
              key: const Key('tx-count'),
              style: T.monoSmall.copyWith(color: _error != null ? C.red : C.text3),
            ),
          ),
          if (_items.isEmpty && !_loading && _error == null)
            const Padding(padding: EdgeInsets.all(Sz.pad), child: EmptyState('No transactions', 'Nothing matches these filters.', icon: Icons.receipt_long_rounded))
          else
            Panel(
              padding: EdgeInsets.zero,
              margin: const EdgeInsets.symmetric(horizontal: 14),
              child: Column(children: [
                for (var i = 0; i < _items.length; i++) ...[if (i > 0) const Divider(height: 1), _row(_items[i])],
              ]),
            ),
          if (_loading) const Padding(padding: EdgeInsets.all(18), child: Center(child: MiniSpinner())),
          if (!_loading && shown < total)
            Center(child: TextButton(key: const Key('tx-more'), onPressed: () => _load(), child: Text('Show more (${total - shown} left)'))),
        ],
      ),
    );
  }
}

/// One transaction in full.
Future<void> showTransactionSheet(BuildContext context, Tx t, String account) {
  Widget line(String k, String v) => v.isEmpty || v == '-'
      ? const SizedBox.shrink()
      : Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 92, child: Text(k, style: T.small.copyWith(color: C.text3))), Expanded(child: Text(v, style: T.small))]));
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: C.panel,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t.description.isEmpty ? 'Transaction' : t.description, style: T.title, key: const Key('tx-sheet-title')),
          const SizedBox(height: 8),
          line('Amount', fmt.money(t.amount, currency: t.currency.isEmpty ? 'KES' : t.currency)),
          line('Date', t.date),
          line('Type', t.type),
          line('Envelope', t.category),
          line('Account', account),
          line('Vendor', t.vendor),
          line('Note', t.note),
        ]),
      ),
    ),
  );
}

/// The Ledger search: transactions (asked of the server as you type), accounts and envelopes. Accounts and envelopes send
/// the space to Transactions on that filter.
class _LedgerSearchScreen extends StatefulWidget {
  const _LedgerSearchScreen({required this.data, required this.accounts, required this.envelopeNames});
  final LedgerData data;
  final List<Map<String, dynamic>> accounts;
  final List<String> envelopeNames;

  @override
  State<_LedgerSearchScreen> createState() => _LedgerSearchScreenState();
}

class _LedgerSearchScreenState extends State<_LedgerSearchScreen> {
  final _field = TextEditingController();
  Timer? _debounce;
  String _q = '';
  List<Tx> _txs = const [];
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _field.dispose();
    super.dispose();
  }

  void _changed(String v) {
    _debounce?.cancel();
    final q = v.trim();
    setState(() => _q = q);
    if (q.isEmpty) {
      setState(() => _txs = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 280), () async {
      setState(() {
        _busy = true;
        _error = null;
      });
      try {
        final page = await widget.data.transactions(LedgerFilter(q: q), limit: 40);
        if (!mounted || _q != q) return;
        setState(() {
          _txs = page.items;
          _busy = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = '$e'.replaceAll(RegExp(r'\s+'), ' ');
        });
      }
    });
  }

  bool _hit(String hay) => _q.toLowerCase().split(RegExp(r'\s+')).every((w) => w.isEmpty || hay.toLowerCase().contains(w));

  @override
  Widget build(BuildContext context) {
    final accs = _q.isEmpty ? const <Map<String, dynamic>>[] : widget.accounts.where((a) => _hit('${fmt.s(a['NAME'])} ${fmt.s(a['INSTITUTION'])}')).toList();
    final envs = _q.isEmpty ? const <String>[] : widget.envelopeNames.where((n) => _hit(n.replaceAll('-', ' '))).toList();
    Widget head(String t) => Padding(padding: const EdgeInsets.fromLTRB(0, 14, 0, 4), child: Text(t, style: T.label));
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          key: const Key('ledger-search-field'),
          controller: _field,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Search transactions, accounts and envelopes', border: InputBorder.none),
          style: T.body,
          onChanged: _changed,
        ),
      ),
      body: _q.isEmpty
          ? const EmptyState('Search', 'Type to search this space.', icon: Icons.search_rounded)
          : ListView(padding: const EdgeInsets.fromLTRB(14, 0, 14, 24), children: [
              if (accs.isNotEmpty) ...[
                head('ACCOUNTS'),
                for (final a in accs)
                  ListTile(
                    key: Key('hit-account-${fmt.s(a['ID'])}'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(fmt.s(a['NAME']), style: T.w600(T.body2)),
                    subtitle: Text(fmt.s(a['INSTITUTION']), style: T.small.copyWith(color: C.text3)),
                    onTap: () => Navigator.pop(context, LedgerFilter(account: fmt.s(a['ID']))),
                  ),
              ],
              if (envs.isNotEmpty) ...[
                head('ENVELOPES'),
                for (final n in envs)
                  ListTile(
                    key: Key('hit-envelope-$n'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(n.replaceAll('-', ' '), style: T.w600(T.body2)),
                    onTap: () => Navigator.pop(context, LedgerFilter(category: n)),
                  ),
              ],
              head('TRANSACTIONS'),
              if (_error != null) Text('Could not search: $_error', style: T.small.copyWith(color: C.red)),
              if (_busy) const Padding(padding: EdgeInsets.all(12), child: Center(child: MiniSpinner())),
              if (!_busy && _error == null && _txs.isEmpty) Text('No transactions match.', style: T.small.copyWith(color: C.text3)),
              for (final t in _txs)
                ListTile(
                  key: Key('hit-tx-${t.id}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(t.description.isEmpty ? t.category : t.description, style: T.w600(T.body2), maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text([t.date, t.category].where((x) => x.isNotEmpty).join(' · '), style: T.small.copyWith(color: C.text3)),
                  trailing: Text(fmt.money(t.amount, currency: t.currency.isEmpty ? 'KES' : t.currency), style: T.mono),
                  onTap: () => showTransactionSheet(context, t, ''),
                ),
            ]),
    );
  }
}
