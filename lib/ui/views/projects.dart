import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../widgets/common.dart';
import '../widgets/space_header.dart';

/// BI26101815: which of Active, Building and Shipped a project's status belongs to. Every value lands in exactly one;
/// anything unknown or empty is Active.
int projectTabOf(String status) {
  final v = status.toLowerCase().trim();
  if (const {'building', 'build', 'wip', 'in progress', 'in-progress', 'developing', 'development', 'dev', 'design', 'designing', 'planned', 'planning', 'idea', 'prototype', 'draft', 'alpha', 'beta', 'pre-launch'}.contains(v)) return 1;
  if (const {'shipped', 'launched', 'released', 'done', 'complete', 'completed', 'sold', 'archived', 'retired', 'closed', 'sunset'}.contains(v)) return 2;
  return 0;
}

const projectTabLabels = ['Active', 'Building', 'Shipped'];

List<Map<String, dynamic>> _projectsOf(dynamic data, String? cat) {
  final all = fmt.lm(fmt.m(data)['projects']);
  if (cat == null || cat.isEmpty || cat.toLowerCase() == 'all') return all;
  return all.where((p) => fmt.s(p['CATEGORY'] ?? p['TYPE'] ?? p['cat']).toLowerCase().contains(cat.toLowerCase())).toList();
}

/// Ventures / products / platforms with live health checks, in three tabs by status (BI26101815).
class ProjectsView extends StatelessWidget {
  const ProjectsView({super.key, this.cat});
  final String? cat;

  /// The search finds a project by name, kind, note or address and opens the tab its status puts it in.
  static List<SpaceHit> hitsFor(BuildContext context, String? cat) => [
        for (final p in _projectsOf(AppScope.of(context).store.projects.value, cat))
          if (fmt.s(p['NAME']).isNotEmpty)
            SpaceHit(
              title: fmt.s(p['NAME']),
              subtitle: [fmt.s(p['KIND']), fmt.s(p['STATUS']), fmt.s(p['NOTE'])].where((x) => x.isNotEmpty).join(' · '),
              tab: projectTabOf(fmt.s(p['STATUS'])),
            ),
      ];

  Widget _tab(BuildContext context, int tab) {
    final services = AppScope.of(context);
    return SnapshotView(
      snapshot: services.store.projects,
      builder: (context, data) {
        final all = _projectsOf(data, cat);
        if (all.isEmpty) {
          return EmptyState(
            cat == null ? 'No projects registered' : 'No $cat projects registered',
            'Ventures and products from the finance vault appear here.',
            icon: Icons.rocket_launch_rounded,
          );
        }
        final projects = [for (final p in all) if (projectTabOf(fmt.s(p['STATUS'])) == tab) p];
        if (projects.isEmpty) {
          return EmptyState('Nothing ${projectTabLabels[tab].toLowerCase()}', 'Projects with this status appear here.', icon: Icons.rocket_launch_rounded);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final project in projects)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _ProjectTile(project: project),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final noun = (cat == null || cat!.isEmpty) ? 'projects' : '${cat!}s';
    return SpaceView(
      space: 'projects-${cat == null || cat!.isEmpty ? 'all' : cat}',
      searchHint: 'Search $noun',
      hits: (c) => hitsFor(c, cat),
      tabs: [for (var i = 0; i < projectTabLabels.length; i++) SpaceTab(projectTabLabels[i], _tab(context, i))],
    );
  }
}

class _ProjectTile extends StatelessWidget {
  const _ProjectTile({required this.project});
  final Map<String, dynamic> project;

  @override
  Widget build(BuildContext context) {
    final live = fmt.m(project['live']);
    final up = fmt.b(live['up']);
    final url = fmt.s(project['URL']).isEmpty
        ? fmt.s(project['url'])
        : fmt.s(project['URL']);
    return Panel(
      padding: const EdgeInsets.all(12),
      onTap: url.isEmpty
          ? null
          : () {
              final uri = Uri.tryParse(url);
              if (uri != null) {
                launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(fmt.s(project['NAME']), style: T.w600(T.body2)),
              ),
              if (live.isNotEmpty) ...[
                StatusDot(up ? C.green : C.red, glow: up, size: 6),
                const SizedBox(width: 6),
                Text(
                  up ? 'up · ${fmt.i(live['ms'])}ms' : 'down',
                  style:
                      T.monoSmall.copyWith(color: up ? C.green : C.red),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              if (fmt.s(project['KIND']).isNotEmpty)
                Badge2(fmt.s(project['KIND'])),
              const SizedBox(width: 6),
              if (fmt.s(project['STATUS']).isNotEmpty)
                Badge2(fmt.s(project['STATUS']),
                    color: C.greenBg, textColor: C.greenBright),
              const Spacer(),
              if (url.isNotEmpty)
                Text(
                  url.replaceFirst(RegExp(r'^https?://'), ''),
                  style: T.monoSmall.copyWith(color: C.cyan),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
          if (fmt.s(project['NOTE']).isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(fmt.s(project['NOTE']),
                style: T.small.copyWith(color: C.text3),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    );
  }
}
