import 'package:flutter/material.dart';
import 'package:slate_ui/slate_ui.dart';

import '../../app_scope.dart';
import '../../data/accounts_data.dart';
import '../../services/circle_depth.dart';
import '../../services/revenue_actions.dart';
import '../../services/slate_hub_client.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../shell.dart' show SecondaryScreen;
import '../views/accounts_space.dart';
import 'common.dart';

/// BI26102202: the top of the home. Only the open growth and practice rows, and the days since the last client
/// conversation, so the first shilling stays in view every morning. No new store: slate holds the rows, circle the people.
class RevenueActionsCard extends StatefulWidget {
  const RevenueActionsCard({super.key, this.rows, this.clock, this.onOpen, this.spend, this.onOpenAccounts});

  /// Tests supply the rows; the app reads them through hub's slate view.
  final Future<List<RowSummary>> Function()? rows;
  final DateTime Function()? clock;
  final void Function(BuildContext, RowSummary)? onOpen;

  /// BI26102403: money out beside money in. Tests supply it; the app reads it from hub. A failed read hides the line.
  final Future<SpendSummary> Function()? spend;
  final void Function(BuildContext)? onOpenAccounts;

  @override
  State<RevenueActionsCard> createState() => _RevenueActionsCardState();
}

class _RevenueActionsCardState extends State<RevenueActionsCard> {
  Future<List<RowSummary>>? _rows;
  Future<SpendSummary?>? _spend;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rows ??= (widget.rows ?? () => HubSlateClient(AppScope.of(context).api).rows())()
        .then((all) => pickRevenueRows(all))
        .catchError((_) => <RowSummary>[]);
    _spend ??= (widget.spend ?? () => HttpAccountsApi(AppScope.of(context).api).spend())().then<SpendSummary?>((s) => s).catchError((_) => null);
  }

  void _openAccounts(BuildContext context) {
    if (widget.onOpenAccounts != null) return widget.onOpenAccounts!(context);
    Navigator.push(context, MaterialPageRoute(builder: (_) => const SecondaryScreen(title: 'Accounts', child: AccountsSpace(initialTab: 1))));
  }

  DateTime _now() => (widget.clock ?? DateTime.now)();

  void _open(BuildContext context, RowSummary r) {
    if (widget.onOpen != null) return widget.onOpen!(context, r);
    final app = AppScope.of(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RowDetailScreen(
          client: HubSlateClient(app.api),
          stepUp: passkeyWriteStepUp(app.api, app.session.passkeys),
          id: r.id,
          project: r.project,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return ListenableBuilder(
      listenable: services.store.circle,
      builder: (context, _) {
        final people = fmt.lm(fmt.m(services.store.circle.value)['people']);
        final days = daysSinceClientConversation(people, _now());
        final gap = clientGap(days);
        final color = switch (gap) { ClientGap.red => C.red, ClientGap.amber => C.amber, _ => C.text2 };
        return Panel(
          key: const Key('revenue-actions'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Today's revenue actions", style: T.title),
              const SizedBox(height: 6),
              FutureBuilder<List<RowSummary>>(
                future: _rows,
                builder: (ctx, snap) {
                  final rows = snap.data ?? const <RowSummary>[];
                  if (snap.connectionState != ConnectionState.done) return const SizedBox(height: 20);
                  if (rows.isEmpty) {
                    return Text('No revenue actions open', key: const Key('revenue-empty'), style: T.body2.copyWith(color: C.text3));
                  }
                  return Column(children: [
                    for (final r in rows)
                      InkWell(
                        key: Key('revenue-row-${r.id}'),
                        onTap: () => _open(ctx, r),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(children: [
                            Expanded(child: Text(r.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: T.body2)),
                            const SizedBox(width: 8),
                            Text(r.project, style: T.tiny.copyWith(color: C.text3)),
                          ]),
                        ),
                      ),
                  ]);
                },
              ),
              FutureBuilder<SpendSummary?>(
                future: _spend,
                builder: (ctx, snap) {
                  final s = snap.data;
                  if (s == null) return const SizedBox.shrink();
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const SizedBox(height: 6),
                    InkWell(
                      key: const Key('spend-line'),
                      onTap: () => _openAccounts(ctx),
                      child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(s.line, style: T.body2.copyWith(color: s.empty ? C.text3 : C.text))),
                    ),
                    if (s.renewals.isNotEmpty)
                      Wrap(spacing: 8, runSpacing: 4, children: [
                        for (final r in s.renewals)
                          ActionChip(
                            key: Key('spend-chip-${r.id}'),
                            label: Text(r.label, style: T.small.copyWith(color: r.soon(_now()) ? C.amber : C.text2)),
                            onPressed: () => _openAccounts(ctx),
                          ),
                      ]),
                  ]);
                },
              ),
              const SizedBox(height: 6),
              Text(gapLine(days), key: const Key('revenue-gap'), style: T.small.copyWith(color: color, fontWeight: gap == ClientGap.red || gap == ClientGap.amber ? FontWeight.w700 : FontWeight.w400)),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(key: const Key('revenue-log'), onPressed: () => _logDialog(context, people), child: const Text('Log a conversation')),
              ),
            ],
          ),
        );
      },
    );
  }

  /// One note: who, when, one line. Saved to circle as a touch and the person is tagged client. No phone or email is shown.
  Future<void> _logDialog(BuildContext context, List<Map<String, dynamic>> people) async {
    final names = [for (final p in people) if (fmt.s(p['NAME']).isNotEmpty) p];
    if (names.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add the person to your circle first.')));
      return;
    }
    Map<String, dynamic> who = names.first;
    DateTime when = _now();
    final line = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Log a conversation'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButton<Map<String, dynamic>>(
                key: const Key('revenue-person'),
                isExpanded: true,
                value: who,
                items: [for (final p in names) DropdownMenuItem(value: p, child: Text(fmt.s(p['NAME']), overflow: TextOverflow.ellipsis))],
                onChanged: (v) => set(() => who = v ?? who),
              ),
              TextButton(
                onPressed: () async {
                  final d = await showDatePicker(context: ctx, initialDate: when, firstDate: DateTime(2020), lastDate: _now());
                  if (d != null) set(() => when = d);
                },
                child: Text('Date: ${when.toIso8601String().substring(0, 10)}'),
              ),
              TextField(key: const Key('revenue-line'), controller: line, maxLength: 140, decoration: const InputDecoration(labelText: 'One line')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(key: const Key('revenue-save'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    final app = AppScope.of(context);
    final api = HubCircleDepthApi(app.api);
    final id = fmt.s(who['ID']);
    try {
      await api.logSent(id, channel: 'conversation', summary: '${when.toIso8601String().substring(0, 10)} ${line.text.trim()}');
      if (!isClientPerson(who)) await api.addTag(id, 'client');
      await app.store.circle.refresh();
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }
}
