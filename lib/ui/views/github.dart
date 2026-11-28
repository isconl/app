import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../../services/study_extras.dart';
import '../widgets/common.dart';
import '../widgets/study_extras.dart';

/// GitHub snapshot: repos, notifications, contribution map.
class GithubView extends StatelessWidget {
  const GithubView({super.key});

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return SnapshotView(
      snapshot: services.store.github,
      builder: (context, data) {
        final map = fmt.m(data);
        final repos = fmt.lm(map['repos']);
        final notifications = fmt.lm(map['notifications']);
        final contributions = fmt.m(map['contributions']);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (contributions.isNotEmpty) ...[
              ContributionsCard(title: 'Activity', canRefresh: true, loader: (refresh) => HubStudyExtrasApi(services.api).githubContributions(refresh: refresh)),
            ],
            if (notifications.isNotEmpty) ...[
              const SectionLabel('Notifications'),
              Panel(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var idx = 0;
                        idx < notifications.length && idx < 10;
                        idx++) ...[
                      if (idx > 0) const Divider(),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: Sz.pad, vertical: 10),
                        child: Row(
                          children: [
                            StatusDot(
                                fmt.b(notifications[idx]['unread'])
                                    ? C.green
                                    : C.text3,
                                size: 6),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    fmt.s(fmt.m(notifications[idx]
                                            ['subject'])['title'])
                                        .isEmpty
                                        ? fmt.s(notifications[idx]
                                            ['subject'])
                                        : fmt.s(fmt.m(notifications[idx]
                                            ['subject'])['title']),
                                    style: T.small,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(fmt.s(notifications[idx]['repo']),
                                      style: T.monoSmall),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            if (repos.isNotEmpty) ...[
              const SectionLabel('Repositories'),
              ...repos.take(15).map((repo) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Panel(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  fmt.s(repo['name']).isEmpty
                                      ? fmt.s(repo['fullName'])
                                      : fmt.s(repo['name']),
                                  style: T.w500(T.body2
                                      .copyWith(color: C.cyan)),
                                ),
                              ),
                              if (fmt.b(repo['isPrivate']))
                                const Badge2('private'),
                            ],
                          ),
                          if (fmt.s(repo['description']).isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(fmt.s(repo['description']),
                                style: T.small.copyWith(color: C.text3),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                          ],
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              if (fmt.s(repo['language']).isNotEmpty ||
                                  fmt
                                      .s(fmt.m(repo['primaryLanguage'])[
                                          'name'])
                                      .isNotEmpty) ...[
                                const StatusDot(C.green, size: 6),
                                const SizedBox(width: 5),
                                Text(
                                  fmt.s(repo['language']).isEmpty
                                      ? fmt.s(fmt.m(repo['primaryLanguage'])['name'])
                                      : fmt.s(repo['language']),
                                  style: T.monoSmall,
                                ),
                                const SizedBox(width: 12),
                              ],
                              Text(fmt.ago(repo['updatedAt']),
                                  style: T.monoSmall),
                            ],
                          ),
                        ],
                      ),
                    ),
                  )),
            ],
            if (repos.isEmpty && notifications.isEmpty)
              const EmptyState(
                'GitHub not connected',
                'The snapshot appears once GITHUB_TOKEN is configured '
                    'on the agent.',
                icon: Icons.code_rounded,
              ),
          ],
        );
      },
    );
  }
}
