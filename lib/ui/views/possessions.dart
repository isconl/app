import 'package:flutter/material.dart';

import '../../api/client.dart';
import '../../data/finance_repo.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../widgets/common.dart';
import 'personal_dashboard.dart' show Unlock, deviceUnlock;

/// BI26100509 (finance depth, the possessions slice): Holdings' asset registry, editable from the app.
///
/// Values are T3, so they follow the Holdings tile's rule (BI26100130): masked until the device unlocks,
/// masked again when the app leaves the foreground, and never kept unmasked anywhere but this widget's state.
/// Names and categories show, since the list is no use without them; amounts do not.
class PossessionsSection extends StatefulWidget {
  const PossessionsSection({super.key, required this.repo, this.currency = 'KES', this.unlock = deviceUnlock});
  final FinanceRepository repo;
  final String currency;
  final Unlock unlock;

  @override
  State<PossessionsSection> createState() => _PossessionsSectionState();
}

class _PossessionsSectionState extends State<PossessionsSection> with WidgetsBindingObserver {
  List<Possession>? _items;
  String? _error;
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _shown) setState(() => _shown = false);
  }

  Future<void> _load() async {
    try {
      final items = await widget.repo.possessions();
      if (mounted) setState(() {
        _items = items;
        _error = null;
      });
    } on OfflineException {
      if (mounted) setState(() => _error = 'Offline. Possessions load when you are back online.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Possessions could not be loaded.');
    }
  }

  Future<void> _toggleValues() async {
    if (_shown) {
      setState(() => _shown = false);
      return;
    }
    final ok = await widget.unlock();
    if (mounted && ok) setState(() => _shown = true);
  }

  String _money(double v) => _shown ? fmt.money(v, currency: widget.currency) : '••••';

  Future<void> _edit([Possession? p]) async {
    final saved = await showFormSheet<Possession>(
      context,
      title: p == null ? 'New possession' : 'Edit possession',
      builder: (ctx) => _PossessionForm(initial: p, currency: widget.currency, showValue: p == null || _shown),
    );
    if (saved == null || !mounted) return;
    try {
      await widget.repo.savePossession(saved);
      if (mounted) toast(context, p == null ? 'Possession added' : 'Possession saved');
      await _load();
    } on OfflineException {
      if (mounted) toast(context, 'Offline. Nothing was saved; try again when online.', error: true);
    } catch (e) {
      if (mounted) toast(context, e is StateError ? e.message : 'Not saved.', error: true);
    }
  }

  Future<void> _delete(Possession p) async {
    final sure = await confirmDialog(context, 'Delete ${p.item}?', 'It is removed from the registry for good.',
        action: 'Delete', destructive: true);
    if (!sure || !mounted) return;
    try {
      await widget.repo.deletePossession(p.id);
      if (mounted) toast(context, 'Deleted');
      await _load();
    } on OfflineException {
      if (mounted) toast(context, 'Offline. Nothing was deleted.', error: true);
    } catch (e) {
      if (mounted) toast(context, e is StateError ? e.message : 'Not deleted.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          const Expanded(child: SectionLabel('Possessions')),
          IconButton(
            key: const Key('possessions-reveal'),
            tooltip: _shown ? 'Hide values' : 'Show values',
            onPressed: items == null || items.isEmpty ? null : _toggleValues,
            icon: Icon(_shown ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 18),
          ),
          IconButton(
            key: const Key('possessions-add'),
            tooltip: 'Add a possession',
            onPressed: () => _edit(),
            icon: const Icon(Icons.add_rounded, size: 18),
          ),
        ]),
        Panel(
          padding: EdgeInsets.zero,
          child: _error != null
              ? Padding(padding: const EdgeInsets.all(Sz.pad), child: Text(_error!, style: T.small.copyWith(color: C.text3)))
              : items == null
                  ? const Padding(padding: EdgeInsets.all(Sz.pad), child: Center(child: MiniSpinner(size: 18)))
                  : items.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(Sz.pad),
                          child: Text('Nothing registered yet. Add what you own: a laptop, a car, land.',
                              style: T.small.copyWith(color: C.text3)))
                      : Column(children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(Sz.pad, 10, Sz.pad, 6),
                            child: Row(children: [
                              Text('${items.length} ${items.length == 1 ? 'item' : 'items'}', style: T.small),
                              const Spacer(),
                              Text(_money(FinanceRepository.totalValue(items)),
                                  key: const Key('possessions-total'), style: T.mono),
                            ]),
                          ),
                          for (final p in items) ...[
                            const Divider(),
                            ListTile(
                              key: ValueKey('possession-${p.id}'),
                              dense: true,
                              title: Text(p.item, style: T.small, maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text([p.category, p.location, p.condition].where((x) => x.isNotEmpty).join(' · '),
                                  style: T.monoSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                Text(_money(p.value), style: T.mono),
                                IconButton(
                                  key: ValueKey('possession-delete-${p.id}'),
                                  tooltip: 'Delete',
                                  onPressed: () => _delete(p),
                                  icon: const Icon(Icons.delete_outline_rounded, size: 18, color: C.text3),
                                ),
                              ]),
                              onTap: () => _edit(p),
                            ),
                          ],
                        ]),
        ),
      ],
    );
  }
}

/// Add or edit. When values are masked, editing an existing item leaves its value untouched rather than
/// showing it, so the form never reveals a figure the list is hiding.
class _PossessionForm extends StatefulWidget {
  const _PossessionForm({required this.initial, required this.currency, required this.showValue});
  final Possession? initial;
  final String currency;
  final bool showValue;

  @override
  State<_PossessionForm> createState() => _PossessionFormState();
}

class _PossessionFormState extends State<_PossessionForm> {
  late final _item = TextEditingController(text: widget.initial?.item ?? '');
  late final _category = TextEditingController(text: widget.initial?.category ?? '');
  late final _value = TextEditingController(
      text: widget.initial == null ? '' : (widget.showValue ? _plain(widget.initial!.value) : ''));
  late final _acquired = TextEditingController(text: widget.initial?.acquiredDate ?? '');
  late final _location = TextEditingController(text: widget.initial?.location ?? '');
  late final _condition = TextEditingController(text: widget.initial?.condition ?? '');
  late final _notes = TextEditingController(text: widget.initial?.notes ?? '');
  String? _problem;

  static String _plain(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  void _submit() {
    final item = _item.text.trim();
    if (item.isEmpty) {
      setState(() => _problem = 'Give it a name.');
      return;
    }
    final raw = _value.text.trim().replaceAll(',', '');
    final keepValue = widget.initial != null && !widget.showValue && raw.isEmpty;
    final value = keepValue ? widget.initial!.value : (raw.isEmpty ? 0.0 : double.tryParse(raw));
    if (value == null || value < 0) {
      setState(() => _problem = 'The value is a number, like 45000.');
      return;
    }
    Navigator.pop(
      context,
      Possession(
        id: widget.initial?.id ?? '',
        item: item,
        category: _category.text.trim(),
        value: value,
        acquiredDate: _acquired.text.trim(),
        location: _location.text.trim(),
        condition: _condition.text.trim(),
        notes: _notes.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Field(label: 'What it is', controller: _item, autofocus: widget.initial == null),
        Field(label: 'Category', controller: _category, hint: 'e.g. electronics, vehicle, land'),
        Field(
          label: 'Value (${widget.currency})',
          controller: _value,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          hint: widget.initial != null && !widget.showValue ? 'Hidden. Leave empty to keep it.' : null,
        ),
        Field(label: 'Acquired', controller: _acquired, hint: 'YYYY-MM-DD'),
        Field(label: 'Where it is', controller: _location),
        Field(label: 'Condition', controller: _condition, hint: 'e.g. good, needs repair'),
        Field(label: 'Notes', controller: _notes, maxLines: 3),
        if (_problem != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_problem!, key: const Key('possession-problem'), style: T.small.copyWith(color: C.red)),
          ),
        FilledButton(key: const Key('possession-save'), onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
