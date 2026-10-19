import 'package:flutter/material.dart';

import '../../api/client.dart';
import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../widgets/common.dart';

/// Teams - the team operating system as a channel, on the phone (BI26092655).
///
/// ONE BOARD, FIVE PER LEADER, THREE DAYS DEEP. Three tabs, the same as the console: Board (the work in lanes, a depth
/// chip per person), People (the reporting tree with role, forces and depth, and the Architect panel) and Talk (a
/// placeholder until phase 2). An organisation and a team picker sit above them. Management (creating a team, boarding a
/// person, moving work) stays on the console; the phone is where he SEES.

/// One lane of the board: its title, what it holds, and the items in it.
class TeamLane {
  const TeamLane(this.key, this.title, this.hint, this.items);
  final String key;
  final String title;
  final String hint;
  final List<Map<String, dynamic>> items;
}

/// The board's lanes, left to right: Ready, Doing, Blocked, Awaiting sign-off, Done this sprint, with a Draft lane in
/// front only when something is a draft. The sprint is the trailing [shipWindowDays] (7) the server counts signatures in.
List<TeamLane> teamLanes(Map<String, dynamic> team, {int shipWindowDays = 7, DateTime? now}) {
  final cutoff = (now ?? DateTime.now()).toUtc().subtract(Duration(days: shipWindowDays)).toIso8601String();
  final work = fmt.lm(team['work']);
  List<Map<String, dynamic>> by(bool Function(Map<String, dynamic>) f) => [for (final w in work) if (f(fmt.m(w))) fmt.m(w)];
  final lanes = <TeamLane>[
    TeamLane('ready', 'Ready', 'queued, not started', by((w) => fmt.s(w['status']) == 'queued')),
    TeamLane('doing', 'Doing', 'started', by((w) => fmt.s(w['status']) == 'active')),
    TeamLane('blocked', 'Blocked', 'waiting on something', by((w) => fmt.s(w['status']) == 'blocked')),
    TeamLane('sign', 'Awaiting sign-off', 'finished, the leader confirms', by((w) => fmt.s(w['status']) == 'finished')),
    TeamLane('done', 'Done this sprint', 'signed in the last week',
        by((w) => fmt.s(w['status']) == 'signed' && fmt.s(w['signedAt']).compareTo(cutoff) >= 0)),
  ];
  final drafts = by((w) => fmt.s(w['status']) == 'draft');
  if (drafts.isNotEmpty) lanes.insert(0, TeamLane('draft', 'Draft', 'missing a field, cannot start', drafts));
  return lanes;
}

/// The teams of one organisation in tree order (a parent, then its sub-teams), each with its depth.
List<({Map<String, dynamic> team, int depth})> teamTreeOrder(List<Map<String, dynamic>> teams) {
  final ids = {for (final t in teams) fmt.s(t['id'])};
  final kids = <String, List<Map<String, dynamic>>>{};
  for (final t in teams) {
    final p = fmt.s(t['parentTeamId']);
    kids.putIfAbsent(p.isNotEmpty && ids.contains(p) ? p : '', () => []).add(t);
  }
  final out = <({Map<String, dynamic> team, int depth})>[];
  void walk(String parent, int depth) {
    final list = [...(kids[parent] ?? const [])]..sort((a, b) => fmt.s(a['title']).compareTo(fmt.s(b['title'])));
    for (final t in list) {
      out.add((team: t, depth: depth));
      walk(fmt.s(t['id']), depth + 1);
    }
  }

  walk('', 0);
  return out;
}

/// A team's members as the reporting tree: (member, depth) in display order, skipping the reports of any folded member.
List<({Map<String, dynamic> member, int depth, bool hasKids})> memberTree(Map<String, dynamic> team, Set<String> folded) {
  final members = fmt.lm(team['members']).map(fmt.m).toList();
  final kids = fmt.m(team['children']);
  final byId = {for (final m in members) fmt.s(m['id']): m};
  final out = <({Map<String, dynamic> member, int depth, bool hasKids})>[];
  void walk(String id, int depth) {
    final m = byId[id];
    if (m == null) return;
    final k = (kids[id] is List) ? (kids[id] as List).map(fmt.s).toList() : <String>[];
    out.add((member: m, depth: depth, hasKids: k.isNotEmpty));
    if (!folded.contains(id)) {
      for (final c in k) {
        walk(c, depth + 1);
      }
    }
  }

  final roots = (kids['_root'] is List) ? (kids['_root'] as List).map(fmt.s).toList() : [for (final m in members) fmt.s(m['id'])];
  for (final r in roots) {
    walk(r, 0);
  }
  return out;
}

class TeamsView extends StatefulWidget {
  const TeamsView({super.key});

  @override
  State<TeamsView> createState() => _TeamsViewState();
}

class _TeamsViewState extends State<TeamsView> {
  Future<dynamic>? _future;
  String? _teamId;
  int _tab = 0;
  final Set<String> _folded = {};

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
          return const Padding(padding: EdgeInsets.only(top: 48), child: Center(child: MiniSpinner()));
        }
        if (snap.hasError) {
          final e = snap.error;
          final msg = e is OfflineException ? 'offline' : e is ApiException ? e.message : 'Could not load teams';
          return ErrorRetry(msg, onRetry: () => setState(_load));
        }
        final data = fmt.m(snap.data);
        final teams = fmt.lm(data['teams']).map(fmt.m).toList();
        final orgs = fmt.lm(data['orgs']).map(fmt.m).toList();
        final spanLimit = fmt.d(data['spanLimit']).toInt();
        if (teams.isEmpty) {
          return const EmptyState(
            'No teams yet',
            'Build a team on the console - one board, five per leader, three days of ready work each. It shows here once it exists.',
            icon: Icons.groups_rounded,
          );
        }
        final team = teams.firstWhere((t) => fmt.s(t['id']) == _teamId, orElse: () => teams.first);
        final orgId = fmt.s(team['orgId']);
        final inOrg = teams.where((t) => fmt.s(t['orgId']) == orgId).toList();
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
              _Switcher(
                orgs: orgs,
                orgId: orgId,
                team: team,
                teams: inOrg,
                onOrg: (id) {
                  final first = teamTreeOrder(teams.where((t) => fmt.s(t['orgId']) == id).toList());
                  if (first.isNotEmpty) setState(() => _teamId = fmt.s(first.first.team['id']));
                },
                onTeam: (id) => setState(() => _teamId = id),
              ),
              const SizedBox(height: 8),
              _Tabs(index: _tab, onTab: (i) => setState(() => _tab = i)),
              const SizedBox(height: 10),
              if (_tab == 0)
                _Board(team: team, org: orgs.cast<Map<String, dynamic>?>().firstWhere((o) => fmt.s(o?['id']) == orgId, orElse: () => null))
              else if (_tab == 1)
                _People(
                  team: team,
                  spanLimit: spanLimit,
                  folded: _folded,
                  onFold: (id) => setState(() => _folded.contains(id) ? _folded.remove(id) : _folded.add(id)),
                )
              else
                const _Talk(),
            ],
          ),
        );
      },
    );
  }
}

class _Switcher extends StatelessWidget {
  const _Switcher({required this.orgs, required this.orgId, required this.team, required this.teams, required this.onOrg, required this.onTeam});
  final List<Map<String, dynamic>> orgs;
  final String orgId;
  final Map<String, dynamic> team;
  final List<Map<String, dynamic>> teams;
  final ValueChanged<String> onOrg;
  final ValueChanged<String> onTeam;

  @override
  Widget build(BuildContext context) {
    final tree = teamTreeOrder(teams);
    return Row(
      children: [
        if (orgs.length > 1) ...[
          Expanded(
            child: DropdownButton<String>(
              key: const Key('teams-org'),
              isExpanded: true,
              value: orgs.any((o) => fmt.s(o['id']) == orgId) ? orgId : null,
              items: [
                for (final o in orgs)
                  DropdownMenuItem(
                    value: fmt.s(o['id']),
                    child: Text('${fmt.s(o['name'])}${fmt.s(o['kind']) == 'engagement' ? ' (engagement)' : ''}', overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) {
                if (v != null) onOrg(v);
              },
            ),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: DropdownButton<String>(
            key: const Key('teams-team'),
            isExpanded: true,
            value: fmt.s(team['id']),
            items: [
              for (final e in tree)
                DropdownMenuItem(
                  value: fmt.s(e.team['id']),
                  child: Text('${'  ' * e.depth}${e.depth > 0 ? '↳ ' : ''}${fmt.s(e.team['title'])}', overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) {
              if (v != null) onTeam(v);
            },
          ),
        ),
      ],
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.index, required this.onTab});
  final int index;
  final ValueChanged<int> onTab;

  @override
  Widget build(BuildContext context) {
    const labels = ['Board', 'People', 'Talk'];
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          ChoiceChip(
            key: Key('teams-tab-${labels[i].toLowerCase()}'),
            label: Text(labels[i]),
            selected: index == i,
            onSelected: (_) => onTab(i),
          ),
          const SizedBox(width: 8),
        ],
      ],
    );
  }
}

Color _levelFg(String level) => level == 'green' ? C.greenBright : level == 'amber' ? C.amber : C.red;
Color _levelBg(String level) => level == 'green' ? C.greenBg : level == 'amber' ? C.amberBg : C.redBg;
String _days(double d) => d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toStringAsFixed(1);

class _Board extends StatelessWidget {
  const _Board({required this.team, required this.org});
  final Map<String, dynamic> team;
  final Map<String, dynamic>? org;

  @override
  Widget build(BuildContext context) {
    final members = fmt.lm(team['members']).map(fmt.m).toList();
    final names = {for (final m in members) fmt.s(m['id']): fmt.s(m['name'])};
    final lanes = teamLanes(team);
    final counts = fmt.m(team['counts']);
    final slipped = fmt.d(counts['slipped']).toInt();
    final engagement = org != null && fmt.s(org!['kind']) == 'engagement';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (engagement)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${fmt.s(org!['name'])} is an engagement: its board is Jira. This view models the people and shows the work held here.',
              style: T.tiny.copyWith(color: C.text3),
            ),
          ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final m in members)
              Badge2('${fmt.s(m['name'])} ${_days(fmt.d(m['depth']))}d',
                  color: _levelBg(fmt.s(m['depthLevel'])), textColor: _levelFg(fmt.s(m['depthLevel']))),
          ],
        ),
        if (slipped > 0) ...[
          const SizedBox(height: 8),
          Text('$slipped ${slipped == 1 ? 'item is' : 'items are'} past due', style: T.monoSmall.copyWith(color: C.red)),
        ],
        const SizedBox(height: 10),
        for (final lane in lanes) _LaneCard(lane: lane, names: names),
      ],
    );
  }
}

class _LaneCard extends StatelessWidget {
  const _LaneCard({required this.lane, required this.names});
  final TeamLane lane;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context) {
    return Panel(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(lane.title, style: T.title)),
              Text('${lane.items.length}', key: Key('lane-count-${lane.key}'), style: T.monoSmall),
            ],
          ),
          const SizedBox(height: 6),
          if (lane.items.isEmpty)
            Text('${lane.hint}: nothing here', style: T.tiny.copyWith(color: C.text3))
          else
            for (final w in lane.items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(fmt.s(w['title']), style: T.body2),
                    Text(
                      [
                        if ((names[fmt.s(w['memberId'])] ?? '').isNotEmpty) names[fmt.s(w['memberId'])]!,
                        if (fmt.s(w['due']).isNotEmpty) 'due ${fmt.s(w['due'])}${w['late'] == true ? ' - late' : ''}',
                        '${_days(fmt.d(w['effortDays']))}d',
                        if (fmt.s(w['blockedNote']).isNotEmpty) 'blocked: ${fmt.s(w['blockedNote'])}',
                      ].join(' · '),
                      style: T.tiny.copyWith(color: w['late'] == true ? C.red : C.text3),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _People extends StatelessWidget {
  const _People({required this.team, required this.spanLimit, required this.folded, required this.onFold});
  final Map<String, dynamic> team;
  final int spanLimit;
  final Set<String> folded;
  final ValueChanged<String> onFold;

  static const _forces = ['captain', 'strategist', 'operator', 'warrior', 'scout', 'guardian'];
  static const _label = {
    'healthy': 'Healthy', 'quiet': 'Quiet', 'corrupted': 'Corrupted', 'quiet+corrupted': 'Quiet + corrupted', 'unstaffed': 'Unstaffed',
  };
  String _cap(String f) => f.isEmpty ? f : '${f[0].toUpperCase()}${f.substring(1)}';

  @override
  Widget build(BuildContext context) {
    final tree = memberTree(team, folded);
    final architects = fmt.lm(fmt.m(team['forces'])['architects']);
    final diagnosis = fmt.m(team['architect']);
    final owner = fmt.s(team['owner']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Panel(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Architect', style: T.title),
              const SizedBox(height: 4),
              if (architects.isEmpty)
                Text('No one on this team is flagged Architect yet. Set it on a member on the console.', style: T.tiny.copyWith(color: C.text3))
              else ...[
                Text('Holding the position: ${architects.map((a) => fmt.s(fmt.m(a)['name'])).join(', ')}', style: T.tiny.copyWith(color: C.text3)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final f in _forces)
                      Builder(builder: (_) {
                        final d = fmt.m(diagnosis[f]);
                        final st = fmt.s(d['status']).isEmpty ? 'unstaffed' : fmt.s(d['status']);
                        final ok = st == 'healthy';
                        return Badge2('${_cap(f)}: ${_label[st] ?? st}',
                            color: ok ? C.greenBg : st == 'unstaffed' ? C.redBg : C.amberBg,
                            textColor: ok ? C.greenBright : st == 'unstaffed' ? C.red : C.amber);
                      }),
                  ],
                ),
              ],
            ],
          ),
        ),
        Panel(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Who reports to who', style: T.title),
              if (owner.isNotEmpty) Text('$owner at the root', style: T.tiny.copyWith(color: C.text3)),
              const SizedBox(height: 6),
              if (tree.isEmpty) Text('nobody yet', style: T.tiny.copyWith(color: C.text3)),
              for (final e in tree) _MemberRow(entry: e, spanLimit: spanLimit, folded: folded.contains(fmt.s(e.member['id'])), onFold: onFold),
            ],
          ),
        ),
      ],
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.entry, required this.spanLimit, required this.folded, required this.onFold});
  final ({Map<String, dynamic> member, int depth, bool hasKids}) entry;
  final int spanLimit;
  final bool folded;
  final ValueChanged<String> onFold;

  @override
  Widget build(BuildContext context) {
    final m = entry.member;
    final id = fmt.s(m['id']);
    final level = fmt.s(m['depthLevel']);
    final directs = fmt.d(m['directs']).toInt();
    final forces = [
      if (fmt.s(m['forcePrimary']).isNotEmpty) fmt.s(m['forcePrimary']),
      if (fmt.s(m['forceSecondary']).isNotEmpty) '${fmt.s(m['forceSecondary'])} (2nd)',
    ].join(', ');
    final over = m['spanOver'] == true;
    final full = directs >= spanLimit && !over;
    final line = [
      if (fmt.s(m['role']).isNotEmpty) fmt.s(m['role']),
      if (forces.isNotEmpty) forces,
      if (m['isArchitect'] == true) 'Architect',
      if (directs > 0) 'leads $directs of $spanLimit',
    ].join(' · ');
    return Padding(
      padding: EdgeInsets.only(left: 18.0 * entry.depth, top: 4, bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: entry.hasKids
                ? IconButton(
                    key: Key('fold-$id'),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    icon: Icon(folded ? Icons.chevron_right_rounded : Icons.expand_more_rounded),
                    onPressed: () => onFold(id),
                  )
                : null,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(fmt.s(m['name']), style: T.body2),
                if (line.isNotEmpty) Text(line, style: T.tiny.copyWith(color: C.text3)),
                if (over) Text('over the span of $spanLimit - split the team', style: T.tiny.copyWith(color: C.red)),
                if (full) Text('full - the next report needs a split', key: Key('span-full-$id'), style: T.tiny.copyWith(color: C.amber)),
              ],
            ),
          ),
          Badge2('${_days(fmt.d(m['depth']))}d', color: _levelBg(level), textColor: _levelFg(level)),
        ],
      ),
    );
  }
}

class _Talk extends StatelessWidget {
  const _Talk();

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      'Talk comes next',
      'Channels, threads and calls for this team arrive in phase 2, through Cover. Until then the team is reached through the Inbox or person to person in Cover.',
      icon: Icons.forum_rounded,
    );
  }
}
