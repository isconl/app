import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../widgets/common.dart';

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
              const SectionLabel('Contributions'),
              Panel(child: _ContributionMap(data: contributions)),
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

/// Contribution heatmap in brand greens.
class _ContributionMap extends StatelessWidget {
  const _ContributionMap({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    // Accept either {weeks: [{days:[{count}]}]} or {days: [{date,count}]}.
    List<List<int>> weeks = [];
    final weeksRaw = fmt.l(data['weeks']);
    if (weeksRaw.isNotEmpty) {
      weeks = [
        for (final w in weeksRaw)
          [
            for (final day in fmt.l(fmt.m(w)['days']))
              fmt.i(fmt.m(day)['count'])
          ]
      ];
    } else {
      final days = fmt.lm(data['days']);
      if (days.isEmpty) {
        return Text('No contribution data', style: T.small);
      }
      var week = <int>[];
      for (final day in days) {
        week.add(fmt.i(day['count']));
        if (week.length == 7) {
          weeks.add(week);
          week = [];
        }
      }
      if (week.isNotEmpty) weeks.add(week);
    }
    if (weeks.isEmpty) return Text('No contribution data', style: T.small);
    final recent = weeks.length > 20
        ? weeks.sublist(weeks.length - 20)
        : weeks;

    Color cellColor(int count) {
      if (count <= 0) return C.surface;
      if (count < 3) return C.greenDim.withValues(alpha: 0.45);
      if (count < 6) return C.greenDim;
      return C.greenBright;
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      child: Row(
        children: [
          for (final week in recent)
            Column(
              children: [
                for (var day = 0; day < 7; day++)
                  Container(
                    width: 9,
                    height: 9,
                    margin: const EdgeInsets.all(1.2),
                    decoration: BoxDecoration(
                      color: cellColor(
                          day < week.length ? week[day] : 0),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
