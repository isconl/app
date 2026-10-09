import 'continue_reading.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/day_close.dart';
import 'spaced_review_view.dart';
import '../../util/fmt.dart' as fmt;
import '../shell.dart' show openNavRoute;
import '../widgets/block_card.dart';
import '../widgets/checkpoint_card.dart';
import '../widgets/common.dart';
import '../widgets/context_ring_card.dart';
import '../widgets/vitals_card.dart';
import 'tasks.dart' show showAddTaskSheet, TaskRowTile;

/// Hub: answers "what needs me?" in under two seconds.
///
/// Named Command until 3 August 2026. The SPACE is still called COMMAND - it
/// is the group that holds Hub, Planning, Calendar and Ideas. This view is its
/// first child, and a child that shares its parent's name reads as though the
/// group were a single screen.
class HubView extends StatefulWidget {
  const HubView({super.key});

  @override
  State<HubView> createState() => _HubViewState();
}

class _HubViewState extends State<HubView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final store = AppScope.of(context).store;
        store.day.hydrate();
        DayClosePrefs.instance.ensureLoaded(AppScope.of(context).db);
        final sig = store.signals;
        sig.hydrate().then((_) {
          if (mounted && sig.value == null) sig.refresh();
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return SnapshotView(
      snapshot: services.store.state,
      builder: (context, data) {
        final state = fmt.m(data);
        final eq = fmt.m(state['time']);
        final tasks = fmt.lm(state['tasks']);
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
            ListenableBuilder(
              listenable: DayClosePrefs.instance,
              builder: (context, _) => DayClosePrefs.instance.closedToday(now)
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Panel(
                        key: const Key('day-closed'),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: Row(children: [
                          const Icon(Icons.check_circle_outline_rounded, size: 18, color: C.green),
                          const SizedBox(width: 8),
                          Text('Day closed', style: T.body2.copyWith(color: C.text)),
                        ]),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            const ReviewCard(),
            const ContinueReadingCard(),
            // ---- hero — date/due/review card, always first ----
            // BI26100541: no card behind the date and the status strip; they sit on the page background.
            Padding(
              key: const Key('hero-strip'),
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDate(now),
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
                  const SizedBox(height: 6),
                  _buildSignalsStripOrFallback(
                    context,
                    services,
                    newAlerts,
                    overdue.length,
                    review.length,
                  ),
                ],
              ),
            ),
            // ---- checkpoint, between the date block and the ring (BI26092624) ----
            const CheckpointCard(),
            // ---- console ring ----
            const ContextRingCard(),
            // ---- orientation ----
            const _OrientationStrip(),
            // ---- block card / today's tasks (BI26092625 + BI26092628) ----
            ListenableBuilder(
              listenable: services.store.day,
              builder: (context, _) {
                final dayData = fmt.m(services.store.day.value);
                final rawBlocks = fmt.l(dayData['blocks']);
                final blocks = rawBlocks
                    .map((b) => Map<String, dynamic>.from(fmt.m(b)))
                    .toList();
                final currentId = fmt.s(dayData['currentId'] ??
                    fmt.m(dayData['now'])['id']);

                if (blocks.isNotEmpty) {
                  return BlockCard(
                    blocks: blocks,
                    currentId: currentId,
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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
                  ],
                );
              },
            ),
            // ---- vitals, right after the block card (BI26092630) ----
            const VitalsCard(),
            if (overdue.isNotEmpty) ...[
              SectionLabel('Overdue · ${overdue.length}'),
              ...overdue.take(5).map((t) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TaskRowTile(task: t),
                  )),
            ],
            // ---- services ----
            const SectionLabel('Services'),
            _ServicesCard(services: fmt.m(state['services'])),
          ],
        );
      },
    );
  }

  Widget _buildDate(DateTime now) {
    // BI26100541: `Monday · 5 Oct 2026`, bold weekday and regular date.
    final full = fmt.commandDate(now);
    final dotIdx = full.indexOf(' · ');
    final weekday = full.substring(0, dotIdx);
    final rest = full.substring(dotIdx);
    return Text.rich(
      TextSpan(
        style: T.headline,
        children: [
          TextSpan(
            text: weekday,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          TextSpan(
            text: rest,
            style: const TextStyle(fontWeight: FontWeight.w400),
          ),
        ],
      ),
    );
  }

  Color _toneColor(String tone) => switch (tone.toLowerCase().trim()) {
        'urgent' => C.red,
        'soon' => C.amber,
        'waiting' => C.blue,
        'good' => C.green,
        'info' => C.text3,
        _ => C.text3,
      };

  Widget _buildSignalsStripOrFallback(
    BuildContext context,
    AppServices services,
    int alerts,
    int overdue,
    int review,
  ) {
    return ListenableBuilder(
      listenable: services.store.signals,
      builder: (context, _) {
        final signalsVal = services.store.signals.value;
        if (signalsVal is Map) {
          final rawStrip = fmt.l(signalsVal['strip']);
          final validSignals = rawStrip
              .whereType<Map>()
              .map((m) => m.cast<String, dynamic>())
              .where((m) => fmt.s(m['label']).isNotEmpty)
              .take(3)
              .toList();

          if (validSignals.isNotEmpty) {
            return Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (var idx = 0; idx < validSignals.length; idx++) ...[
                  if (idx > 0)
                    Text('  ·  ',
                        style: T.small.copyWith(color: C.text3)),
                  _signalChip(context, validSignals[idx]),
                ],
              ],
            );
          }
        }
        return _needsYou(alerts, overdue, review);
      },
    );
  }

  Widget _signalChip(BuildContext context, Map<String, dynamic> signal) {
    final label = fmt.s(signal['label']);
    final tone = fmt.s(signal['tone']);
    final route = fmt.s(signal['route']);
    final detail = fmt.s(signal['detail']);
    final color = _toneColor(tone);

    void handleTap() {
      HapticFeedback.selectionClick();
      if (route.isNotEmpty) {
        openNavRoute(context, route);
      }
    }

    void handleLongPress() {
      if (detail.isNotEmpty) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(detail),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }

    final textWidget = Text(
      label,
      style: T.small.copyWith(
        color: color,
        fontWeight: FontWeight.w600,
      ),
    );

    return Tooltip(
      message: detail.isNotEmpty ? detail : label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: handleTap,
          onLongPress: handleLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            child: textWidget,
          ),
        ),
      ),
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
