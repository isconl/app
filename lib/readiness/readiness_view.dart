import 'package:flutter/material.dart';

import '../theme.dart';
import 'readiness_controller.dart';
import 'readiness_model.dart';

/// Picks a date and time. Injected so tests do not drive the system pickers.
typedef DateTimePicker = Future<DateTime?> Function(BuildContext context, DateTime initial);

Future<DateTime?> systemPicker(BuildContext context, DateTime initial) async {
  final d = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(2024),
    lastDate: DateTime(2100),
  );
  if (d == null || !context.mounted) return null;
  final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
  if (t == null) return null;
  return DateTime(d.year, d.month, d.day, t.hour, t.minute);
}

Future<DateTime?> systemDatePicker(BuildContext context, DateTime initial) =>
    showDatePicker(context: context, initialDate: initial, firstDate: DateTime(2024), lastDate: DateTime(2100));

/// Survival and Readiness: kits and trips. Large targets and strong contrast,
/// because it is used in sunlight and with gloves on.
class ReadinessView extends StatefulWidget {
  const ReadinessView({
    super.key,
    required this.controller,
    required this.launch,
    this.pickDateTime = systemPicker,
    this.pickDate = systemDatePicker,
    this.now = DateTime.now,
    this.initialTripId,
  });

  final ReadinessController controller;

  /// Opens a link (WhatsApp). Returns whether it opened.
  final Future<bool> Function(Uri uri) launch;
  final DateTimePicker pickDateTime;
  final Future<DateTime?> Function(BuildContext, DateTime) pickDate;
  final DateTime Function() now;

  /// Opens straight to this trip (from a missed check-in nudge).
  final String? initialTripId;

  @override
  State<ReadinessView> createState() => _ReadinessViewState();
}

class _ReadinessViewState extends State<ReadinessView> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this, initialIndex: widget.initialTripId == null ? 0 : 1);

  @override
  void initState() {
    super.initState();
    if (!widget.controller.loaded) widget.controller.load();
    if (widget.initialTripId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final exists = widget.controller.trips.any((t) => t.id == widget.initialTripId);
        if (exists) _openTrip(widget.initialTripId!);
      });
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _openTrip(String id) => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => TripScreen(
            controller: widget.controller, tripId: id, launch: widget.launch, now: widget.now),
      ));

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) => Column(children: [
          TabBar(controller: _tabs, tabs: const [Tab(text: 'Kits'), Tab(text: 'Trips')]),
          Expanded(
            child: TabBarView(controller: _tabs, children: [
              _KitsTab(controller: widget.controller, pickDate: widget.pickDate, now: widget.now),
              _TripsTab(
                controller: widget.controller,
                pickDateTime: widget.pickDateTime,
                launch: widget.launch,
                now: widget.now,
                onOpen: _openTrip,
              ),
            ]),
          ),
        ]),
      );
}

// ---------------------------------------------------------------- kits

class _KitsTab extends StatelessWidget {
  const _KitsTab({required this.controller, required this.pickDate, required this.now});
  final ReadinessController controller;
  final Future<DateTime?> Function(BuildContext, DateTime) pickDate;
  final DateTime Function() now;

  Future<void> _add(BuildContext context, Kit kit) async {
    final r = await showDialog<({String name, DateTime? expiry})>(
      context: context,
      builder: (_) => _AddItemDialog(kitName: kit.name, pickDate: pickDate, now: now),
    );
    if (r != null) await controller.addItem(kit.id, r.name, expiry: r.expiry);
  }
  @override
  Widget build(BuildContext context) {
    final attention = controller.attention;
    final today = now();
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (attention.isNotEmpty)
        Container(
          key: const Key('kit-attention'),
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(border: Border.all(color: C.amber, width: 2), borderRadius: BorderRadius.circular(Sz.rMd)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Check these now', style: T.title),
            const SizedBox(height: 6),
            for (final a in attention)
              Text(a.days < 0 ? '${a.item.name} (${a.kit.name}) expired ${-a.days} days ago' : '${a.item.name} (${a.kit.name}) expires in ${a.days} days',
                  style: T.body),
          ]),
        ),
      for (final kit in controller.kits)
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(border: Border.all(color: C.border), borderRadius: BorderRadius.circular(Sz.rMd)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
              child: Row(children: [
                Expanded(child: Text(kit.name, style: T.title)),
                Text('${kit.packedCount} of ${kit.items.length} packed', key: Key('packed-${kit.id}'), style: T.small),
              ]),
            ),
            if (kit.items.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                child: Text('Nothing here yet. Add what the course says to pack.', style: T.small),
              ),
            for (final item in kit.items)
              CheckboxListTile(
                key: Key('item-${item.id}'),
                // 56 dp rows: easy to hit with gloves.
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                value: item.packed,
                onChanged: (v) => controller.setPacked(kit.id, item.id, v ?? false),
                title: Text(item.name, style: T.body),
                subtitle: item.expiry == null
                    ? null
                    : Text(
                        item.needsAttention(today) ? 'Expires ${formatDate(item.expiry!)} - check it' : 'Expires ${formatDate(item.expiry!)}',
                        style: T.small.copyWith(color: item.needsAttention(today) ? C.amber : C.text3)),
                secondary: IconButton(
                  key: Key('remove-${item.id}'),
                  tooltip: 'Remove',
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () => controller.removeItem(kit.id, item.id),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: TextButton.icon(
                key: Key('add-${kit.id}'),
                style: TextButton.styleFrom(minimumSize: const Size(0, 52)),
                onPressed: () => _add(context, kit),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add item'),
              ),
            ),
          ]),
        ),
    ]);
  }
}

// ---------------------------------------------------------------- trips

class _TripsTab extends StatelessWidget {
  const _TripsTab({
    required this.controller,
    required this.pickDateTime,
    required this.launch,
    required this.now,
    required this.onOpen,
  });
  final ReadinessController controller;
  final DateTimePicker pickDateTime;
  final Future<bool> Function(Uri) launch;
  final DateTime Function() now;
  final void Function(String id) onOpen;

  @override
  Widget build(BuildContext context) {
    final today = now();
    return ListView(padding: const EdgeInsets.all(16), children: [
      FilledButton.icon(
        key: const Key('new-trip'),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => NewTripScreen(controller: controller, pickDateTime: pickDateTime, now: now),
        )),
        icon: const Icon(Icons.add_location_alt_rounded),
        label: const Text('New trip card'),
      ),
      const SizedBox(height: 14),
      if (controller.trips.isEmpty)
        Text('No trips yet. Make the card before you leave; it works with no signal.', style: T.small),
      for (final t in controller.trips)
        InkWell(
          key: Key('trip-${t.id}'),
          onTap: () => onOpen(t.id),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border.all(color: t.isOverdue(today) ? C.red : C.border, width: t.isOverdue(today) ? 2 : 1),
              borderRadius: BorderRadius.circular(Sz.rMd),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.where, style: T.title),
              const SizedBox(height: 4),
              Text('${formatDateTime(t.start)} to ${formatDateTime(t.returnBy)}', style: T.small),
              const SizedBox(height: 4),
              Text(
                t.isBack ? 'Back safe' : t.isOverdue(today) ? 'Overdue: not checked in' : 'Alarm ${formatDateTime(t.alarmAt)}',
                style: T.small.copyWith(color: t.isBack ? C.greenBright : t.isOverdue(today) ? C.red : C.text3),
              ),
            ]),
          ),
        ),
    ]);
  }
}

class NewTripScreen extends StatefulWidget {
  const NewTripScreen({super.key, required this.controller, required this.pickDateTime, required this.now});
  final ReadinessController controller;
  final DateTimePicker pickDateTime;
  final DateTime Function() now;

  @override
  State<NewTripScreen> createState() => _NewTripScreenState();
}

class _NewTripScreenState extends State<NewTripScreen> {
  final _where = TextEditingController();
  final _who = TextEditingController();
  final _call = TextEditingController();
  final _notes = TextEditingController();
  final _phone = TextEditingController();
  late DateTime _start = widget.now().add(const Duration(hours: 2));
  late DateTime _return = widget.now().add(const Duration(hours: 10));
  DateTime? _alarm;
  String? _error;
  String? _hint;

  @override
  void dispose() {
    for (final c in [_where, _who, _call, _notes, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  DateTime get _alarmAt => _alarm ?? _return.add(const Duration(hours: 1));

  Future<void> _pick(DateTime current, void Function(DateTime) set) async {
    final d = await widget.pickDateTime(context, current);
    if (d != null) setState(() => set(d));
  }

  Future<void> _save() async {
    if (_where.text.trim().isEmpty) {
      setState(() => _error = 'Say where you are going.');
      return;
    }
    if (!_return.isAfter(_start)) {
      setState(() => _error = 'The return time must be after the start.');
      return;
    }
    final trip = await widget.controller.createTrip(
      where: _where.text,
      who: _who.text,
      start: _start,
      returnBy: _return,
      alarmAt: _alarmAt,
      callWho: _call.text,
      notes: _notes.text,
      sharePhone: _phone.text,
    );
    if (mounted) Navigator.of(context).pop(trip.id);
  }

  Widget _timeButton(String label, DateTime value, Key key, void Function(DateTime) set) => OutlinedButton(
        key: key,
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), alignment: Alignment.centerLeft),
        onPressed: () => _pick(value, set),
        child: Text('$label: ${formatDateTime(value)}'),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('New trip card')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Wrap(spacing: 8, children: [
            for (final t in tripTemplates)
              ActionChip(
                key: Key('template-${t.name}'),
                label: Text(t.name),
                onPressed: () => setState(() {
                  _where.text = t.where;
                  _hint = t.hint;
                }),
              ),
          ]),
          if (_hint != null)
            Padding(padding: const EdgeInsets.only(top: 6), child: Text(_hint!, key: const Key('template-hint'), style: T.small)),
          const SizedBox(height: 12),
          TextField(key: const Key('trip-where'), controller: _where, decoration: const InputDecoration(labelText: 'Where (route or place)')),
          TextField(key: const Key('trip-who'), controller: _who, decoration: const InputDecoration(labelText: 'Who is going')),
          const SizedBox(height: 12),
          _timeButton('Start', _start, const Key('trip-start'), (d) => _start = d),
          const SizedBox(height: 8),
          _timeButton('Return', _return, const Key('trip-return'), (d) => _return = d),
          const SizedBox(height: 8),
          _timeButton('Raise the alarm at', _alarmAt, const Key('trip-alarm'), (d) => _alarm = d),
          const SizedBox(height: 12),
          TextField(
            key: const Key('trip-call'),
            controller: _call,
            decoration: const InputDecoration(labelText: 'Who to call (name and number)', helperText: 'Type the number yourself. Check it before you go.'),
          ),
          TextField(
            key: const Key('trip-phone'),
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'WhatsApp number to share with', hintText: '+254...'),
          ),
          TextField(key: const Key('trip-notes'), controller: _notes, minLines: 2, maxLines: 5, decoration: const InputDecoration(labelText: 'Notes')),
          if (_error != null)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, key: const Key('trip-error'), style: T.body.copyWith(color: C.red))),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('trip-save'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            onPressed: _save,
            child: const Text('Save trip card'),
          ),
        ]),
      );
}

class TripScreen extends StatefulWidget {
  const TripScreen({super.key, required this.controller, required this.tripId, required this.launch, required this.now});
  final ReadinessController controller;
  final String tripId;
  final Future<bool> Function(Uri) launch;
  final DateTime Function() now;

  @override
  State<TripScreen> createState() => _TripScreenState();
}

class _TripScreenState extends State<TripScreen> {
  String? _message;

  Future<void> _share({bool overdue = false}) async {
    final link = await widget.controller.share(widget.tripId, overdue: overdue);
    if (link == null) {
      setState(() => _message = 'Add a WhatsApp number to this trip first.');
      return;
    }
    final ok = await widget.launch(link);
    setState(() => _message = ok ? null : 'WhatsApp did not open. Copy the message below and send it yourself.');
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final exists = widget.controller.trips.any((t) => t.id == widget.tripId);
          if (!exists) return const Scaffold(body: Center(child: Text('This trip was deleted.')));
          final t = widget.controller.trip(widget.tripId);
          final now = widget.now();
          final overdue = t.isOverdue(now);
          return Scaffold(
            appBar: AppBar(title: Text(t.where)),
            body: ListView(padding: const EdgeInsets.all(16), children: [
              if (overdue)
                Container(
                  key: const Key('overdue-banner'),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(border: Border.all(color: C.red, width: 2), borderRadius: BorderRadius.circular(Sz.rMd)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('You have not checked in', style: T.title.copyWith(color: C.red)),
                    const SizedBox(height: 6),
                    Text('The alarm time was ${formatDateTime(t.alarmAt)}. Press "I\'m back" if you are safe, or send your contact this message.', style: T.body),
                    const SizedBox(height: 8),
                    SelectableText(t.overdueMessage(now), key: const Key('overdue-message'), style: T.small),
                    const SizedBox(height: 10),
                    FilledButton(
                      key: const Key('resend-overdue'),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                      onPressed: () => _share(overdue: true),
                      child: const Text('Send the overdue message'),
                    ),
                  ]),
                ),
              if (t.isBack)
                Text('Back safe at ${formatDateTime(t.backAt!)}', key: const Key('back-safe'), style: T.title.copyWith(color: C.greenBright)),
              const SizedBox(height: 12),
              SelectableText(t.message(), key: const Key('trip-message'), style: T.body),
              const SizedBox(height: 16),
              if (_message != null)
                Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(_message!, key: const Key('trip-note'), style: T.body.copyWith(color: C.amber))),
              FilledButton.icon(
                key: const Key('share-trip'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                onPressed: () => _share(),
                icon: const Icon(Icons.send_rounded),
                label: Text(t.sharedAt == null ? 'Share on WhatsApp' : 'Share again'),
              ),
              if (t.sharedAt != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Shared ${formatDateTime(t.sharedAt!)}', style: T.small)),
              const SizedBox(height: 12),
              if (!t.isBack)
                OutlinedButton.icon(
                  key: const Key('im-back'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(60)),
                  onPressed: () => widget.controller.markBack(t.id),
                  icon: const Icon(Icons.check_circle_outline_rounded),
                  label: const Text("I'm back"),
                ),
              const SizedBox(height: 12),
              TextButton(
                key: const Key('delete-trip'),
                onPressed: () async {
                  await widget.controller.deleteTrip(t.id);
                  if (context.mounted) Navigator.of(context).maybePop();
                },
                child: const Text('Delete this trip card'),
              ),
            ]),
          );
        },
      );
}

class _AddItemDialog extends StatefulWidget {
  const _AddItemDialog({required this.kitName, required this.pickDate, required this.now});
  final String kitName;
  final Future<DateTime?> Function(BuildContext, DateTime) pickDate;
  final DateTime Function() now;

  @override
  State<_AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends State<_AddItemDialog> {
  final _name = TextEditingController();
  DateTime? _expiry;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Add to ${widget.kitName}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(key: const Key('item-name'), controller: _name, autofocus: true, decoration: const InputDecoration(labelText: 'Item')),
          const SizedBox(height: 12),
          OutlinedButton(
            key: const Key('item-expiry'),
            onPressed: () async {
              final d = await widget.pickDate(context, widget.now().add(const Duration(days: 180)));
              if (d != null) setState(() => _expiry = d);
            },
            child: Text(_expiry == null ? 'Expiry date (perishables)' : 'Expires ${formatDate(_expiry!)}'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            key: const Key('item-save'),
            onPressed: () {
              final n = _name.text.trim();
              if (n.isEmpty) return;
              Navigator.pop(context, (name: n, expiry: _expiry));
            },
            child: const Text('Add'),
          ),
        ],
      );
}