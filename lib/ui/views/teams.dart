import 'package:flutter/material.dart';

import '../../api/client.dart';
import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../widgets/common.dart';

/// Teams - the team operating system as a channel, on the phone.
///
/// ONE BOARD, FIVE PER LEADER, THREE DAYS DEEP. This reads the model the
/// server computes (lib/teams.js): each person's ready-work DEPTH as a number,
/// and each team's health as the count of people who are green (3+ days),
/// amber (thin) or red (dry). Management - creating a team, boarding a person,
/// moving work - stays on the console; the phone is where he SEES, at a glance
/// and offline-tolerant, whether anyone is about to run out of work.
class TeamsView extends StatefulWidget {
  const TeamsView({super.key});

  @override
  State<TeamsView> createState() => _TeamsViewState();
}

class _TeamsViewState extends State<TeamsView> {
  Future<dynamic>? _future;

  void _load() {
    _future = AppScope.of(context).api.getJson('/api/teams');
  }

  @override
  Widget build(BuildContext context) {
    _future ??= AppScope.of(context).api.getJson('/api/teams');
    return FutureBuilder<dynamic>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.only(top: 48),
            child: Center(child: MiniSpinner()),
          );
        }
        if (snap.hasError) {
          final e = snap.error;
          final msg = e is OfflineException
              ? 'offline'
              : e is ApiException
                  ? e.message
                  : 'Could not load teams';
          return ErrorRetry(msg, onRetry: () => setState(_load));
        }
        final data = fmt.m(snap.data);
        final teams = fmt.lm(data['teams']);
        final spanLimit = fmt.d(data['spanLimit']).toInt();
        if (teams.isEmpty) {
          return const EmptyState(
            'No teams yet',
            'Build a team on the console - one board, five per leader, three '
                'days of ready work each. It shows here once it exists.',
            icon: Icons.groups_rounded,
          );
        }
        return RefreshIndicator(
          onRefresh: () async {
            final f = AppScope.of(context).api.getJson('/api/teams');
            setState(() => _future = f);
            try {
              await f;
            } catch (_) {}
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 96),
            children: [
              for (final t in teams)
                _TeamCard(team: fmt.m(t), spanLimit: spanLimit),
            ],
          ),
        );
      },
    );
  }
}

class _TeamCard extends StatelessWidget {
  const _TeamCard({required this.team, required this.spanLimit});
  final Map<String, dynamic> team;
  final int spanLimit;

  @override
  Widget build(BuildContext context) {
    final title = fmt.s(team['title']);
    final org = fmt.s(team['org']);
    final owner = fmt.s(team['owner']);
    final cadence = fmt.s(team['cadence']);
    final layers = fmt.d(team['layers']).toInt();
    final health = fmt.m(team['health']);
    final counts = fmt.m(team['counts']);
    final members = fmt.lm(team['members']);

    final subtitle = [
      if (org.isNotEmpty) org,
      if (owner.isNotEmpty) 'led by $owner',
      '$layers ${layers == 1 ? 'layer' : 'layers'}',
    ].join('  ·  ');

    final slipped = fmt.d(counts['slipped']).toInt();

    return Panel(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: T.title),
          const SizedBox(height: 3),
          Text(subtitle, style: T.monoSmall),
          const SizedBox(height: 10),
          Row(
            children: [
              _health('${fmt.d(health['green']).toInt()} ready',
                  C.greenBright, C.greenBg),
              const SizedBox(width: 6),
              _health('${fmt.d(health['amber']).toInt()} thin', C.amber,
                  C.amberBg),
              const SizedBox(width: 6),
              _health(
                  '${fmt.d(health['red']).toInt()} dry', C.red, C.redBg),
            ],
          ),
          const SizedBox(height: 12),
          for (final m in members) _MemberRow(member: fmt.m(m), spanLimit: spanLimit),
          if (slipped > 0) ...[
            const SizedBox(height: 8),
            Text('$slipped ${slipped == 1 ? 'item is' : 'items are'} past due',
                style: T.monoSmall.copyWith(color: C.red)),
          ],
          const SizedBox(height: 8),
          Text(
            'queued ${fmt.d(counts['queued']).toInt()}'
            ' · active ${fmt.d(counts['active']).toInt()}'
            ' · blocked ${fmt.d(counts['blocked']).toInt()}'
            ' · awaiting sign-off ${fmt.d(counts['awaitingSign']).toInt()}'
            ' · signed this week ${fmt.d(counts['signedWeek']).toInt()}',
            style: T.tiny.copyWith(color: C.text3),
          ),
          if (cadence.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text('reports $cadence', style: T.tiny.copyWith(color: C.text3)),
          ],
        ],
      ),
    );
  }

  Widget _health(String label, Color fg, Color bg) =>
      Badge2(label, color: bg, textColor: fg);
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.member, required this.spanLimit});
  final Map<String, dynamic> member;
  final int spanLimit;

  @override
  Widget build(BuildContext context) {
    final name = fmt.s(member['name']);
    final role = fmt.s(member['role']);
    final level = fmt.s(member['depthLevel']);
    final depth = fmt.d(member['depth']);
    final directs = fmt.d(member['directs']).toInt();
    final open = fmt.d(member['openCount']).toInt();
    final blocked = fmt.d(member['blockedCount']).toInt();
    final spanOver = member['spanOver'] == true;

    final fg = level == 'green'
        ? C.greenBright
        : level == 'amber'
            ? C.amber
            : C.red;
    final bg = level == 'green'
        ? C.greenBg
        : level == 'amber'
            ? C.amberBg
            : C.redBg;
    final depthLabel = depth == depth.roundToDouble()
        ? depth.toStringAsFixed(0)
        : depth.toStringAsFixed(1);

    final line = [
      if (role.isNotEmpty) role,
      if (directs > 0) 'leads $directs',
      if (blocked > 0) '$blocked blocked',
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: T.body2),
                if (line.isNotEmpty)
                  Text(line, style: T.tiny.copyWith(color: C.text3)),
              ],
            ),
          ),
          if (spanOver) ...[
            Badge2('span $directs > $spanLimit',
                color: C.redBg, textColor: C.red),
            const SizedBox(width: 6),
          ],
          Badge2('${depthLabel}d · $open open', color: bg, textColor: fg),
        ],
      ),
    );
  }
}
