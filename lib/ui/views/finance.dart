import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../widgets/common.dart';

/// Finance: KES, necessity/satisfaction scoring, recursive 50-30-20.
/// All numbers come from the vault - this view only formats them.
class FinanceView extends StatelessWidget {
  const FinanceView({super.key});

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return Stack(
      children: [
        SnapshotView(
          snapshot: services.store.finance,
          builder: (context, data) {
            final fin = fmt.m(data);
            final currency =
                fmt.s(fin['currency']).isEmpty ? 'KES' : fmt.s(fin['currency']);
            final net = fmt.m(fin['netWorth']);
            final month = fmt.m(fin['month']);
            final incomes = fmt.m(fin['incomes']);
            final streams = fmt.lm(incomes['streams']);
            final accounts = fmt.lm(fin['accounts']);
            final goals = fmt.lm(fin['goals']);
            final recent = fmt.lm(fin['recent']);
            final syncInfo = fmt.m(fin['sync']);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                              ? '—'
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
                                          fmt.s(accounts[idx]['INSTITUTION'])
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
                // ---- recent transactions ----
                if (recent.isNotEmpty) ...[
                  const SectionLabel('Recent'),
                  Panel(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var idx = 0; idx < recent.length; idx++) ...[
                          if (idx > 0) const Divider(),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: Sz.pad, vertical: 9),
                            child: Row(
                              children: [
                                Icon(
                                  fmt.s(recent[idx]['TYPE']) == 'income'
                                      ? Icons.south_west_rounded
                                      : fmt.s(recent[idx]['TYPE']) ==
                                              'transfer'
                                          ? Icons.swap_horiz_rounded
                                          : Icons.north_east_rounded,
                                  size: 14,
                                  color:
                                      fmt.s(recent[idx]['TYPE']) == 'income'
                                          ? C.green
                                          : C.text3,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        fmt
                                                .s(recent[idx]['DESCRIPTION'])
                                                .isEmpty
                                            ? fmt.s(recent[idx]['CATEGORY'])
                                            : fmt.s(
                                                recent[idx]['DESCRIPTION']),
                                        style: T.small,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        [
                                          fmt.s(recent[idx]['DATE']),
                                          fmt.s(recent[idx]['CATEGORY']),
                                        ]
                                            .where((x) => x.isNotEmpty)
                                            .join(' · '),
                                        style: T.monoSmall,
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  fmt.money(recent[idx]['AMOUNT'],
                                      currency: currency),
                                  style: T.mono.copyWith(
                                    color: fmt.s(recent[idx]['TYPE']) ==
                                            'income'
                                        ? C.green
                                        : C.text2,
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
          },
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton.small(
                heroTag: 'paste',
                backgroundColor: C.surface,
                foregroundColor: C.text2,
                onPressed: () => _pasteMessage(context),
                child: const Icon(Icons.content_paste_rounded, size: 18),
              ),
              const SizedBox(height: 10),
              FloatingActionButton.small(
                heroTag: 'receipt',
                backgroundColor: C.surface,
                foregroundColor: C.text2,
                onPressed: () => _captureReceipt(context),
                child: const Icon(Icons.receipt_long_rounded, size: 18),
              ),
              const SizedBox(height: 10),
              FloatingActionButton(
                heroTag: 'tx',
                backgroundColor: C.greenDim,
                foregroundColor: Colors.white,
                onPressed: () => _addTxSheet(context),
                child: const Icon(Icons.add_rounded),
              ),
            ],
          ),
        ),
      ],
    );
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
