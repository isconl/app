import 'package:flutter/material.dart';

import '../../api/client.dart';
import '../../app_scope.dart';
import '../../services/teams_api.dart' show updateSurfaced;
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../widgets/common.dart';
import '../shell.dart' show SecondaryScreen, viewForNavRoute;
import 'task_detail.dart';

/// BI26101211: items other parts of the system have surfaced for attention, as the
/// console's Inbox > Surfaced list shows them (`/api/state` `surfacedTasks`: ID,
/// TITLE, BODY, ORIGIN, STATUS new/seen/dismissed, CREATED_AT, VIEW, REF).
///
/// Opening one marks it seen and goes to the thing it points at (a task opens its
/// detail, any other VIEW opens that view). Mark seen and Dismiss are separate
/// buttons, and Dismiss asks first. The console has only seen and dismissed, so the
/// phone has the same two.
class SurfacedView extends StatelessWidget {
  const SurfacedView({super.key, this.items, this.update, this.onOpen});

  /// Tests pass the list directly; the app reads the state snapshot.
  final List<Map<String, dynamic>>? items;

  /// Tests pass a fake; the app posts to hub.
  final Future<void> Function(String id, String status)? update;

  /// Tests record where it went; the app pushes the screen.
  final void Function(BuildContext context, String view, String ref)? onOpen;

  @override
  Widget build(BuildContext context) {
    if (items != null) return _SurfacedList(items: items!, update: update, onOpen: onOpen, reload: null);
    final services = AppScope.of(context);
    return SnapshotView(
      snapshot: services.store.state,
      builder: (context, data) {
        final list = fmt.lm(fmt.m(data)['surfacedTasks']).map(fmt.m).where((i) => fmt.s(i['STATUS']) != 'dismissed').toList();
        return _SurfacedList(items: list, update: update, onOpen: onOpen, reload: () => services.store.state.refresh());
      },
    );
  }
}

class _SurfacedList extends StatefulWidget {
  const _SurfacedList({required this.items, required this.update, required this.onOpen, required this.reload});
  final List<Map<String, dynamic>> items;
  final Future<void> Function(String id, String status)? update;
  final void Function(BuildContext context, String view, String ref)? onOpen;
  final Future<bool> Function()? reload;

  @override
  State<_SurfacedList> createState() => _SurfacedListState();
}

class _SurfacedListState extends State<_SurfacedList> {
  /// Optimistic statuses, so the row changes at once while the agent is told.
  final Map<String, String> _local = {};
  String? _message;

  String _status(Map<String, dynamic> i) => _local[fmt.s(i['ID'])] ?? fmt.s(i['STATUS']);

  Future<void> _set(String id, String status) async {
    setState(() {
      _local[id] = status;
      _message = null;
    });
    try {
      final u = widget.update ?? (a, b) => updateSurfaced(AppScope.of(context).api, a, b);
      await u(id, status);
      await widget.reload?.call();
    } catch (e) {
      if (mounted) {
        setState(() {
          _local.remove(id);
          _message = e is ApiException ? e.message : '$e';
        });
      }
    }
  }

  Future<void> _dismiss(Map<String, dynamic> item) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Dismiss this?'),
        content: Text(fmt.s(item['TITLE'])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep it')),
          FilledButton(key: const Key('dismiss-confirm'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Dismiss')),
        ],
      ),
    );
    if (sure == true) await _set(fmt.s(item['ID']), 'dismissed');
  }

  Future<void> _open(Map<String, dynamic> item) async {
    final id = fmt.s(item['ID']);
    if (_status(item) == 'new') await _set(id, 'seen');
    final view = fmt.s(item['VIEW']);
    final ref = fmt.s(item['REF']);
    if (view.isEmpty || view == '-' || ref.isEmpty || ref == '-' || !mounted) return;
    final open = widget.onOpen ?? _defaultOpen;
    open(context, view, ref);
  }

  static void _defaultOpen(BuildContext context, String view, String ref) {
    if (view == 'task') {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TaskDetailScreen(taskId: ref)));
      return;
    }
    final target = viewForNavRoute(view);
    if (target == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SecondaryScreen(title: target.$2, child: target.$1)));
  }

  @override
  Widget build(BuildContext context) {
    final shown = [for (final i in widget.items) if (_status(i) != 'dismissed') i];
    return ListView(padding: const EdgeInsets.all(Sz.pad), children: [
      Text('${shown.length} item${shown.length == 1 ? '' : 's'}', key: const Key('surfaced-count'), style: T.small),
      const SizedBox(height: 8),
      if (_message != null)
        Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_message!, key: const Key('surfaced-error'), style: T.small.copyWith(color: C.red))),
      if (shown.isEmpty) const EmptyState('Nothing surfaced right now', 'When something needs your attention it appears here.', icon: Icons.flag_rounded),
      for (final i in shown) _row(i),
    ]);
  }

  Widget _row(Map<String, dynamic> i) {
    final id = fmt.s(i['ID']);
    final st = _status(i);
    final body = fmt.s(i['BODY']);
    return InkWell(
      key: Key('surfaced-$id'),
      onTap: () => _open(i),
      child: Panel(
        margin: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (st == 'new') const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.circle, size: 8, color: C.greenBright, key: Key('unread-dot'))),
            Expanded(child: Text(fmt.s(i['TITLE']), style: T.body.copyWith(fontWeight: st == 'new' ? FontWeight.w600 : FontWeight.w400))),
          ]),
          if (body.isNotEmpty && body != '-') Padding(padding: const EdgeInsets.only(top: 4), child: Text(body.length > 140 ? '${body.substring(0, 140)}...' : body, style: T.small)),
          const SizedBox(height: 4),
          Text('${fmt.s(i['ORIGIN'])} · ${fmt.s(i['CREATED_AT'])}', style: T.tiny),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            if (st != 'seen') TextButton(key: Key('seen-$id'), onPressed: () => _set(id, 'seen'), child: const Text('Mark seen')),
            TextButton(key: Key('dismiss-$id'), onPressed: () => _dismiss(i), child: Text('Dismiss', style: TextStyle(color: C.red))),
          ]),
        ]),
      ),
    );
  }
}
