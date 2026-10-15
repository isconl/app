import 'package:flutter/material.dart';

import '../../services/teams_api.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;

const teamForces = ['captain', 'strategist', 'operator', 'warrior', 'scout', 'guardian'];

String _cap(String f) => f.isEmpty ? f : '${f[0].toUpperCase()}${f.substring(1)}';

/// What a person can do on a team from the phone: edit a member, mark one as left
/// (after asking), move work along, block it with a reason, sign it off, and give it
/// to someone else. Every write goes through [client] and then calls [onChanged] so
/// the board reloads; a refusal is shown in the server's own words.
class TeamActions {
  TeamActions({required this.client, required this.teamId, required this.onChanged});

  final TeamsClient client;
  final String teamId;
  final Future<void> Function() onChanged;

  void _say(ScaffoldMessengerState? m, String msg) {
    m?.hideCurrentSnackBar();
    m?.showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Runs a write, reloads the board, then tells the reader what happened. The
  /// messenger is taken before the reload because the reload replaces the list the
  /// tapped button lived in.
  Future<void> _do(BuildContext context, String ok, Future<Object?> Function() action) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final r = await action();
      await onChanged();
      _say(messenger, r is String && r.isNotEmpty ? 'Signed by $r. Now it is done.' : ok);
    } catch (e) {
      _say(messenger, '$e');
    }
  }
  Future<void> editMember(BuildContext context, Map<String, dynamic> team, Map<String, dynamic> member) async {
    final body = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => MemberDialog(team: team, member: member, teamId: teamId),
    );
    if (body == null || !context.mounted) return;
    await _do(context, 'Saved', () => client.saveMember(body).then((_) => null));
  }

  Future<void> removeMember(BuildContext context, Map<String, dynamic> member) async {
    final name = fmt.s(member['name']);
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$name leaves the team?'),
        content: const Text(
            'Their open work returns to the board unassigned, and anyone reporting to them moves up to their leader. The row is kept, marked left.',
            key: Key('remove-warning')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(key: const Key('remove-confirm'), onPressed: () => Navigator.pop(ctx, true), child: const Text('They have left')),
        ],
      ),
    );
    if (sure != true || !context.mounted) return;
    await _do(context, '$name marked as left. Their queue is back on the board.', () => client.removeMember(fmt.s(member['id'])).then((_) => null));
  }

  Future<void> move(BuildContext context, Map<String, dynamic> work, String to) async {
    String? note;
    if (to == 'blocked') {
      note = await showDialog<String>(context: context, builder: (_) => const _NoteDialog());
      if (note == null || !context.mounted) return;
    }
    await _do(context, to == 'blocked' ? 'Blocked. It will chase a decision on the one-pager.' : 'Moved to $to.',
        () => client.moveWork(fmt.s(work['id']), to, note: note));
  }

  Future<void> reassign(BuildContext context, Map<String, dynamic> team, Map<String, dynamic> work) async {
    final members = fmt.lm(team['members']).map(fmt.m).toList();
    final to = await showDialog<String>(
      context: context,
      builder: (_) => _ReassignDialog(members: members, current: fmt.s(work['memberId'])),
    );
    if (to == null || to == fmt.s(work['memberId']) || !context.mounted) return;
    await _do(context, 'Moved.', () => client.saveWork(workToSave(work, teamId, memberId: to)).then((_) => null));
  }
}

class MemberDialog extends StatefulWidget {
  const MemberDialog({super.key, required this.team, required this.member, required this.teamId});
  final Map<String, dynamic> team;
  final Map<String, dynamic> member;
  final String teamId;

  @override
  State<MemberDialog> createState() => _MemberDialogState();
}

class _MemberDialogState extends State<MemberDialog> {
  late final TextEditingController _name = TextEditingController(text: fmt.s(widget.member['name']));
  late final TextEditingController _role = TextEditingController(text: fmt.s(widget.member['role']));
  late String _reportsTo = _validLeader(fmt.s(widget.member['reportsTo']));
  late String _f1 = _force(fmt.s(widget.member['forcePrimary']));
  late String _f2 = _force(fmt.s(widget.member['forceSecondary']));
  late bool _architect = widget.member['isArchitect'] == true;

  List<Map<String, dynamic>> get _leaders => [
        for (final m in fmt.lm(widget.team['members']).map(fmt.m))
          if (fmt.s(m['id']) != fmt.s(widget.member['id'])) m,
      ];

  String _validLeader(String id) => _leaders.any((m) => fmt.s(m['id']) == id) ? id : '';
  String _force(String f) => teamForces.contains(f) ? f : '';

  @override
  void dispose() {
    _name.dispose();
    _role.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Edit ${fmt.s(widget.member['name'])}'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(key: const Key('member-name'), controller: _name, decoration: const InputDecoration(labelText: 'Name')),
            TextField(key: const Key('member-role'), controller: _role, decoration: const InputDecoration(labelText: 'Role on this team')),
            const SizedBox(height: 8),
            DropdownButton<String>(
              key: const Key('member-leader'),
              isExpanded: true,
              value: _reportsTo,
              items: [
                DropdownMenuItem(value: '', child: Text('reports to ${fmt.s(widget.team['owner'])} (root)')),
                for (final m in _leaders) DropdownMenuItem(value: fmt.s(m['id']), child: Text('reports to ${fmt.s(m['name'])}')),
              ],
              onChanged: (v) => setState(() => _reportsTo = v ?? ''),
            ),
            DropdownButton<String>(
              key: const Key('member-force1'),
              isExpanded: true,
              value: _f1,
              items: [
                const DropdownMenuItem(value: '', child: Text('no primary force')),
                for (final f in teamForces) DropdownMenuItem(value: f, child: Text('${_cap(f)} (primary)')),
              ],
              onChanged: (v) => setState(() => _f1 = v ?? ''),
            ),
            DropdownButton<String>(
              key: const Key('member-force2'),
              isExpanded: true,
              value: _f2,
              items: [
                const DropdownMenuItem(value: '', child: Text('no secondary force')),
                for (final f in teamForces) DropdownMenuItem(value: f, child: Text('${_cap(f)} (secondary)')),
              ],
              onChanged: (v) => setState(() => _f2 = v ?? ''),
            ),
            SwitchListTile(
              key: const Key('member-architect'),
              contentPadding: EdgeInsets.zero,
              title: Text('Architect', style: T.body2),
              subtitle: Text('A diagnostic position over the team, not a seventh force.', style: T.tiny),
              value: _architect,
              onChanged: (v) => setState(() => _architect = v),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            key: const Key('member-save'),
            onPressed: _name.text.trim().isEmpty
                ? null
                : () => Navigator.pop(
                      context,
                      memberToSave(
                        id: fmt.s(widget.member['id']),
                        teamId: widget.teamId,
                        name: _name.text,
                        role: _role.text,
                        reportsTo: _reportsTo,
                        personId: fmt.s(widget.member['personId']),
                        forcePrimary: _f1,
                        forceSecondary: _f2,
                        isArchitect: _architect,
                      ),
                    ),
            child: const Text('Save'),
          ),
        ],
      );
}

class _NoteDialog extends StatefulWidget {
  const _NoteDialog();
  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('What is it blocked on?'),
        content: TextField(
          key: const Key('block-note'),
          controller: _c,
          autofocus: true,
          decoration: const InputDecoration(helperText: 'The note travels to the one-pager under "Needs deciding"', hintText: 'waiting on...'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(key: const Key('block-confirm'), onPressed: () => Navigator.pop(context, _c.text.trim()), child: const Text('Block it')),
        ],
      );
}

class _ReassignDialog extends StatefulWidget {
  const _ReassignDialog({required this.members, required this.current});
  final List<Map<String, dynamic>> members;
  final String current;
  @override
  State<_ReassignDialog> createState() => _ReassignDialogState();
}

class _ReassignDialogState extends State<_ReassignDialog> {
  late String _to = widget.members.any((m) => fmt.s(m['id']) == widget.current) ? widget.current : '';

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Give this work to'),
        content: DropdownButton<String>(
          key: const Key('reassign-to'),
          isExpanded: true,
          value: _to,
          items: [
            const DropdownMenuItem(value: '', child: Text('no one (back on the board)')),
            for (final m in widget.members) DropdownMenuItem(value: fmt.s(m['id']), child: Text(fmt.s(m['name']))),
          ],
          onChanged: (v) => setState(() => _to = v ?? ''),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(key: const Key('reassign-confirm'), onPressed: () => Navigator.pop(context, _to), child: const Text('Move it')),
        ],
      );
}
