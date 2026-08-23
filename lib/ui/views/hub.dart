import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../widgets/common.dart';
import '../widgets/context_ring_card.dart';
import '../widgets/data_health_card.dart';
import 'tasks.dart' show showAddTaskSheet, TaskRowTile;

/// Hub: answers "what needs me?" in under two seconds.
///
/// Named Command until 3 August 2026. The SPACE is still called COMMAND - it
/// is the group that holds Hub, Planning, Calendar and Ideas. This view is its
/// first child, and a child that shares its parent's name reads as though the
/// group were a single screen.
class HubView extends StatelessWidget {
  const HubView({super.key});

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return SnapshotView(
      snapshot: services.store.state,
      builder: (context, data) {
        final state = fmt.m(data);
        final eq = fmt.m(state['time']);
        final tasks = fmt.lm(state['tasks']);
        final feed = fmt.lm(state['feed']);
        final now = DateTime.now();

        final todays = tasks.where((t) {
          final st = fmt.s(t['STATUS']).toLowerCase();
          return st == 'today';
        }).toList();
        final overdue = tasks.where((t) {
          final st = fmt.s(t['STATUS']).toLowerCase();
          if (st == 'done') return false;
          final days = fmt.daysUntil(t['DUE_DATE']);
          return days != null && days < 0;
        }).toList();
        final review = tasks
            .where((t) => fmt.s(t['STATUS']).toLowerCase() == 'review')
            .toList();
        final newAlerts = services.sync.newAlerts;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ContextRingCard(),
            const DataHealthCard(),
            // ---- hero ----
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(fmt.fullDate(now), style: T.headline),
                  const SizedBox(height: 4),
                  if (fmt.s(eq['eqShort']).isNotEmpty)
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        Badge2(fmt.s(eq['eqShort']),
                            color: C.greenBg,
                            textColor: C.greenBright),
                        Badge2(fmt.s(eq['sprintShort']),
                            color: C.surface, textColor: C.text2),
                        if (fmt.i(eq['yearPct']) > 0)
                          Badge2('${fmt.i(eq['yearPct'])}% of year',
                              color: C.surface, textColor: C.text3),
                      ],
                    ),
                  const SizedBox(height: 12),
                  _needsYou(newAlerts, overdue.length, review.length),
                ],
              ),
            ),
            // ---- orientation ----
            const _OrientationStrip(),
            // ---- today's tasks ----
            SectionLabel('Today · ${todays.length}',
                trailing: TextButton(
                  onPressed: () => showAddTaskSheet(context),
                  child: const Text('+ Add'),
                )),
            if (todays.isEmpty)
              const Panel(
                child: Text('Nothing scheduled for today. '
                    'Add a task or pull one forward from Next.'),
              )
            else
              ...todays.take(8).map((t) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TaskRowTile(task: t),
                  )),
            if (overdue.isNotEmpty) ...[
              SectionLabel('Overdue · ${overdue.length}'),
              ...overdue.take(5).map((t) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TaskRowTile(task: t),
                  )),
            ],
            // ---- feed ----
            if (feed.isNotEmpty) ...[
              const SectionLabel('Latest captures'),
              Panel(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var idx = 0; idx < feed.length && idx < 5; idx++) ...[
                      if (idx > 0) const Divider(),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: Sz.pad, vertical: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(_channelIcon(fmt.s(feed[idx]['CHANNEL'])),
                                size: 14, color: C.text3),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    fmt.s(feed[idx]['TITLE']).isEmpty
                                        ? fmt.truncate(
                                            fmt.s(feed[idx]['BODY']), 80)
                                        : fmt.s(feed[idx]['TITLE']),
                                    style: T.body2,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    [
                                      fmt.s(feed[idx]['SENDER']),
                                      fmt.ago(feed[idx]['RECEIVED'])
                                    ]
                                        .where((x) => x.isNotEmpty)
                                        .join(' · '),
                                    style: T.monoSmall,
                                  ),
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
            // ---- services ----
            const SectionLabel('Services'),
            _ServicesCard(services: fmt.m(state['services'])),
          ],
        );
      },
    );
  }

  Widget _needsYou(int alerts, int overdue, int review) {
    final parts = <InlineSpan>[
      TextSpan(text: 'Needs you:  ', style: T.small.copyWith(color: C.text3)),
    ];
    void add(String label, int n, Color color) {
      if (parts.length > 1) {
        parts.add(TextSpan(
            text: '  ·  ', style: T.small.copyWith(color: C.text3)));
      }
      parts.add(TextSpan(
        text: '$n $label',
        style: T.small.copyWith(
            color: n > 0 ? color : C.text3,
            fontWeight: n > 0 ? FontWeight.w600 : FontWeight.w400),
      ));
    }

    add('alerts', alerts, C.amber);
    add('overdue', overdue, C.red);
    add('in review', review, C.cyan);
    return Text.rich(TextSpan(children: parts));
  }

  IconData _channelIcon(String channel) => switch (channel.toLowerCase()) {
        'whatsapp' => Icons.chat_rounded,
        'email' || 'mail' => Icons.mail_rounded,
        'telegram' => Icons.send_rounded,
        'mobile' => Icons.smartphone_rounded,
        _ => Icons.inbox_rounded,
      };
}

class _OrientationStrip extends StatefulWidget {
  const _OrientationStrip();

  @override
  State<_OrientationStrip> createState() => _OrientationStripState();
}

class _OrientationStripState extends State<_OrientationStrip> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final snap = AppScope.of(context).store.orientation;
      snap.hydrate().then((_) {
        if (mounted && snap.value == null) snap.refresh();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final snap = AppScope.of(context).store.orientation;
    return ListenableBuilder(
      listenable: snap,
      builder: (context, _) {
        final data = fmt.m(snap.value);
        if (data['available'] == false || data.isEmpty) {
          return const SizedBox.shrink();
        }
        final line = fmt.s(data['headline']).isNotEmpty
            ? fmt.s(data['headline'])
            : fmt.s(data['summary']);
        if (line.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: Sz.gap),
          child: Panel(
            color: C.greenBg2,
            borderColor: C.greenDim.withValues(alpha: 0.45),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.explore_rounded,
                    size: 16, color: C.greenBright),
                const SizedBox(width: 10),
                Expanded(child: Text(line, style: T.body2)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ServicesCard extends StatelessWidget {
  const _ServicesCard({required this.services});
  final Map<String, dynamic> services;

  static const _order = [
    ('gemini', 'Gemini'),
    ('groq', 'Groq'),
    ('anthropic', 'Anthropic'),
    ('jira', 'Jira'),
    ('github', 'GitHub'),
    ('msgraph', 'M365'),
    ('telegram', 'Telegram'),
    ('buffer', 'Buffer'),
    ('ollama', 'Ollama'),
  ];

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];
    for (final (key, label) in _order) {
      final status = fmt.s(services[key]);
      if (status.isEmpty) continue;
      final up = status == 'connected';
      chips.add(Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusDot(up ? C.green : C.text3, glow: up, size: 6),
          const SizedBox(width: 6),
          Text(label,
              style: T.small.copyWith(color: up ? C.text2 : C.text3)),
        ],
      ));
    }
    if (chips.isEmpty) {
      return const Panel(
          child: Text('Service status appears after the first sync.'));
    }
    return Panel(
      child: Wrap(spacing: 16, runSpacing: 10, children: chips),
    );
  }
}
