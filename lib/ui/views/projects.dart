import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../widgets/common.dart';

/// Ventures / products / platforms with live health checks.
class ProjectsView extends StatelessWidget {
  const ProjectsView({super.key});

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return SnapshotView(
      snapshot: services.store.projects,
      builder: (context, data) {
        final projects = fmt.lm(fmt.m(data)['projects']);
        if (projects.isEmpty) {
          return const EmptyState(
            'No projects registered',
            'Ventures and products from the finance vault appear here.',
            icon: Icons.rocket_launch_rounded,
          );
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
