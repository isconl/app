import 'package:flutter/material.dart';

import '../../api/client.dart' show ApiException, OfflineException;
import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import 'common.dart';

/// BI26100510 (groups): create, edit, archive and restore a Study track from the phone, as the console's track modal
/// does (`POST /api/learning/group` and `POST /api/learning/group/archive`). Archiving is reversible: a restore sends
/// the same route with status active, and nothing is deleted. Every write needs the live server and a refusal shows the
/// server's reason.

/// A track id is a short word with no spaces, as the console's form asks for; the server decides the rest.
bool trackIdOk(String id) => RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,39}$').hasMatch(id.trim());

/// The body for saving a track, or the sentence to show when the form is not fit to send.
({Map<String, dynamic>? body, String? problem}) trackBody({required String id, required String label, String description = '', String icon = '', String sortOrder = '', String status = 'active'}) {
  if (!trackIdOk(id)) return (body: null, problem: 'The track id is one short word, letters, digits, hyphen or underscore.');
  if (label.trim().isEmpty) return (body: null, problem: 'A track needs a label.');
  final order = int.tryParse(sortOrder.trim());
  if (sortOrder.trim().isNotEmpty && order == null) return (body: null, problem: 'The order is a whole number.');
  return (
    body: {
      'id': id.trim(),
      'label': label.trim(),
      'description': description.trim(),
      if (icon.trim().isNotEmpty) 'icon': icon.trim(),
      'sortOrder': order ?? 1,
      'status': status == 'archived' ? 'archived' : 'active',
    },
    problem: null,
  );
}

bool trackArchived(Map<String, dynamic> g) => fmt.s(g['status'] ?? g['STATUS']).toLowerCase() == 'archived';

Future<void> showTrackAdmin(BuildContext context, List<Map<String, dynamic>> groups) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.panel,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Sz.rXl)), side: BorderSide(color: C.border)),
    builder: (ctx) => TrackAdminSheet(groups: groups),
  );
}

class TrackAdminSheet extends StatefulWidget {
  const TrackAdminSheet({super.key, required this.groups});
  final List<Map<String, dynamic>> groups;

  @override
  State<TrackAdminSheet> createState() => _TrackAdminSheetState();
}

class _TrackAdminSheetState extends State<TrackAdminSheet> {
  late final List<Map<String, dynamic>> _groups = [for (final g in widget.groups) {...g}];
  bool _busy = false;

  Future<String?> _post(String path, Map<String, dynamic> body) async {
    try {
      final r = fmt.m(await AppScope.of(context).mutations.post(path, body));
      if (r['success'] == false) return fmt.s(r['error']).isEmpty ? 'That did not work.' : fmt.s(r['error']);
      return null;
    } on ApiException catch (e) {
      return e.message;
    } on OfflineException {
      return 'This needs the live server - you are offline.';
    }
  }

  void _applyLocal(String id, Map<String, dynamic> changes) {
    setState(() {
      final i = _groups.indexWhere((g) => fmt.s(g['id'] ?? g['ID']) == id);
      if (i >= 0) {
        _groups[i] = {..._groups[i], ...changes};
      } else {
        _groups.add({'id': id, ...changes});
      }
    });
  }

  Future<void> _save({Map<String, dynamic>? existing}) async {
    final id = TextEditingController(text: fmt.s(existing?['id'] ?? existing?['ID']));
    final label = TextEditingController(text: fmt.s(existing?['label'] ?? existing?['LABEL']));
    final desc = TextEditingController(text: fmt.s(existing?['description'] ?? existing?['DESCRIPTION']));
    final order = TextEditingController(text: '${existing?['sortOrder'] ?? existing?['SORT_ORDER'] ?? ''}');
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'New track' : 'Edit track', style: T.title),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(key: const Key('track-id'), controller: id, enabled: existing == null, decoration: const InputDecoration(hintText: 'Track id, one word')),
            TextField(key: const Key('track-label'), controller: label, decoration: const InputDecoration(hintText: 'Label')),
            TextField(key: const Key('track-desc'), controller: desc, decoration: const InputDecoration(hintText: 'Description (optional)')),
            TextField(key: const Key('track-order'), controller: order, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'Order (a number)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: T.body2.copyWith(color: C.text3))),
          FilledButton(key: const Key('track-save'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (go != true || !mounted) return;
    final r = trackBody(id: id.text, label: label.text, description: desc.text, sortOrder: order.text, status: trackArchived(existing ?? const {}) ? 'archived' : 'active');
    if (r.body == null) {
      toast(context, r.problem!, error: true);
      return;
    }
    setState(() => _busy = true);
    final err = await _post('/api/learning/group', r.body!);
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      toast(context, err, error: true);
      return;
    }
    _applyLocal(fmt.s(r.body!['id']), {'label': r.body!['label'], 'description': r.body!['description'], 'sortOrder': r.body!['sortOrder'], 'status': r.body!['status']});
    toast(context, 'Track saved');
    AppScope.of(context).store.learning.refresh();
  }

  Future<void> _archive(Map<String, dynamic> g, {required bool archive}) async {
    final id = fmt.s(g['id'] ?? g['ID']);
    final name = fmt.s(g['label'] ?? g['LABEL']).isEmpty ? id : fmt.s(g['label'] ?? g['LABEL']);
    final sure = await confirmDialog(
      context,
      archive ? 'Archive $name?' : 'Restore $name?',
      archive ? 'It leaves the Study list. Nothing is deleted, and you can restore it here.' : 'It comes back to the Study list.',
      action: archive ? 'Archive' : 'Restore',
    );
    if (!sure || !mounted) return;
    setState(() => _busy = true);
    final status = archive ? 'archived' : 'active';
    final err = await _post('/api/learning/group/archive', {'id': id, 'status': status});
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      toast(context, err, error: true);
      return;
    }
    _applyLocal(id, {'status': status});
    toast(context, archive ? 'Track archived' : 'Track restored');
    AppScope.of(context).store.learning.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Manage tracks', style: T.title),
            const SizedBox(height: 4),
            Text('Archiving hides a track and can be undone. Nothing is deleted.', style: T.small.copyWith(color: C.text3)),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  if (_groups.isEmpty) Text('No tracks yet.', style: T.small.copyWith(color: C.text3)),
                  for (final g in _groups)
                    Padding(
                      key: Key('track-${fmt.s(g['id'] ?? g['ID'])}'),
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(fmt.s(g['label'] ?? g['LABEL']).isEmpty ? fmt.s(g['id'] ?? g['ID']) : fmt.s(g['label'] ?? g['LABEL']), style: T.body2.copyWith(color: trackArchived(g) ? C.text3 : C.text)),
                            Text(trackArchived(g) ? 'archived' : 'active', style: T.monoSmall),
                          ]),
                        ),
                        TextButton(key: Key('track-edit-${fmt.s(g['id'] ?? g['ID'])}'), onPressed: _busy ? null : () => _save(existing: g), child: const Text('Edit')),
                        TextButton(
                          key: Key('track-archive-${fmt.s(g['id'] ?? g['ID'])}'),
                          onPressed: _busy ? null : () => _archive(g, archive: !trackArchived(g)),
                          child: Text(trackArchived(g) ? 'Restore' : 'Archive'),
                        ),
                      ]),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(key: const Key('track-new'), onPressed: _busy ? null : () => _save(), child: const Text('New track')),
          ],
        ),
      ),
    );
  }
}
