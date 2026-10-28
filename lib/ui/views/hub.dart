import 'dart:async';

import 'continue_reading.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/current_block.dart';
import '../../util/day_close.dart';
import 'spaced_review_view.dart';
import '../../util/fmt.dart' as fmt;
import '../shell.dart' show openNavRoute;
import '../../util/freshness.dart';
import '../widgets/clock_card.dart';
import '../widgets/revenue_actions_card.dart';
import '../widgets/as_of_line.dart';
import '../widgets/block_card.dart';
import '../widgets/checkpoint_card.dart';
import '../widgets/common.dart';
import '../widgets/space_header.dart';
import '../widgets/parity3b_widgets.dart';
import '../widgets/context_ring_card.dart';
import '../widgets/hub_clock.dart';
import '../widgets/offsite_backup_line.dart';
import '../widgets/debrief_card.dart';
import '../widgets/october_ring_card.dart';
import '../widgets/refresher_cards.dart';
import '../widgets/vitals_card.dart';
import 'tasks.dart' show showAddTaskSheet, TaskRowTile;

/// Hub: answers "what needs me?" in under two seconds.
///
/// Named Command until 3 August 2026. The SPACE is still called COMMAND - it
/// is the group that holds Hub, Planning, Calendar and Ideas. This view is its
/// first child, and a child that shares its parent's name reads as though the
/// group were a single screen.
class HubView extends StatefulWidget {
  const HubView({super.key, this.clock});

  /// BI26101801: the time source for the date and the clock (tests pass a fixed one).
  final DateTime Function()? clock;

  @override
  State<HubView> createState() => _HubViewState();
}

/// The Hub's tab names and search hits, for the shared header and its tests.
const hubTabLabels = _HubViewState.tabLabels;
List<SpaceHit> hubHits(BuildContext context) => _HubViewState.hitsFor(context);

class _HubViewState extends State<HubView> with WidgetsBindingObserver {
  Timer? _minute;
  String? _lastBlockId;

  /// BI26101517: the block card follows the clock. Once a minute, when the current block has changed,
  /// the day snapshot is fetched again; it is also fetched when the app comes back to the foreground.
  void _tick() {
    if (!mounted) return;
    final services = AppScope.of(context);
    final id = currentBlockId(fmt.m(services.store.day.value), DateTime.now());
    if (_lastBlockId != null && id != _lastBlockId) services.store.day.refresh();
    _lastBlockId = id;
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      AppScope.of(context).store.day.refresh();
      setState(() {});
    }
  }

  @override
  void dispose() {
    _minute?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _minute = Timer.periodic(const Duration(minutes: 1), (_) => _tick());
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

  /// BI26101814: the Hub is Now (the date, signals, checkpoint and the console ring), Today (the day's blocks or
  /// today's tasks, the review strip and vitals) and Services. Every card the single page showed is in one of them.
  static const tabLabels = ['Now', 'Today', 'Services'];

  /// The search finds a signal, a day block, a task due today or a service, and opens the tab that holds it.
  static List<SpaceHit> hitsFor(BuildContext context) {
    final store = AppScope.of(context).store;
    final state = fmt.m(store.state.value);
    return [
      for (final s in fmt.lm(fmt.m(store.signals.value)['signals']))
        if (fmt.s(s['label']).isNotEmpty) SpaceHit(title: fmt.s(s['label']), subtitle: 'signal', tab: 0),
      for (final b in fmt.l(fmt.m(store.day.value)['blocks']))
        if (fmt.s(fmt.m(b)['title']).isNotEmpty) SpaceHit(title: fmt.s(fmt.m(b)['title']), subtitle: 'day block', tab: 1),
      for (final t in fmt.lm(state['tasks']))
        if (fmt.s(t['STATUS']).toLowerCase() == 'today' && fmt.s(t['TITLE']).isNotEmpty) SpaceHit(title: fmt.s(t['TITLE']), subtitle: 'today', tab: 1),
      for (final e in fmt.m(state['services']).entries)
        SpaceHit(title: e.key, subtitle: 'service', tab: 2),
    ];
  }

  Widget _part(int part) {
    final services = AppScope.of(context);
    return SnapshotView(
      snapshot: services.store.state,
      builder: (context, data) {
        final state = fmt.m(data);
        final eq = fmt.m(state['time']);
        final tasks = fmt.lm(state['tasks']);
        final now = (widget.clock ?? DateTime.now)();

        final todays = tasks.where((t) {
          final st = fmt.s(t['STATUS']).toLowerCase();
          return st == 'today';
        }).toList();
        final review = tasks
            .where((t) => fmt.s(t['STATUS']).toLowerCase() == 'review')
            .toList();
        final newAlerts = services.sync.newAlerts;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (part == 0) ...[
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
            const ContinueReadingCard(),
            // ---- hero — date/due/review card, always first ----
            // BI26100541: no card behind the date, badges and strip; they sit on the page.
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 2, 2, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ThemeOfDayLine(),
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
                    review.length,
                  ),
                ],
              ),
            ),
            // ---- checkpoint, between the date block and the ring (BI26092624) ----
            const CheckpointCard(),
            // ---- Data October (PI26093009): hides when the hub has no feed ----
            const OctoberRingCard(),
            // ---- the evening debrief, from 18:00 (BI26100529) ----
            const DebriefCard(),
            // ---- console ring ----
            const ContextRingCard(),
            // ---- BI26102202 / BI26102601: the first shilling stays in view, below console ----
            const RevenueActionsCard(),
            // ---- orientation ----
            const _OrientationStrip(),
            ],
            if (part == 1) ...[
            // ---- BI26101408: the one-tap work-hours clock ----
            const ClockCard(),
            // ---- block card / today's tasks (BI26092625 + BI26092628) ----
            ListenableBuilder(
              listenable: services.store.day,
              builder: (context, _) {
                final dayData = fmt.m(services.store.day.value);
                final rawBlocks = fmt.l(dayData['blocks']);
                final blocks = rawBlocks
                    .map((b) => Map<String, dynamic>.from(fmt.m(b)))
                    .toList();
                final currentId = currentBlockId(dayData, DateTime.now());

                // A plan from an earlier day is never shown as today's.
                if (blocks.isNotEmpty && dayIsStale(dayData, DateTime.now())) {
                  return const Panel(
                    key: Key('day-updating'),
                    child: Text('Updating…', style: TextStyle(color: C.text3)),
                  );
                }
                if (blocks.isNotEmpty) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      BlockCard(
                        blocks: blocks,
                        currentId: currentId,
                      ),
                      // BI26101521: the plan's own date shows a plan from another day as stale.
                      AsOfLine(snapshot: services.store.day, snapshotKey: 'day', sourceDate: parseSourceDate(dayData['date'])),
                    ],
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
            // ---- the review strip, just below the block card and above vitals (BI26101517) ----
            const ReviewCard(),
            // ---- vitals, right after the block card (BI26092630) ----
            const VitalsCard(),
            const OffsiteBackupLine(),
            const RefresherCards(),
            ],
            if (part == 2) ...[
            // ---- services ----
            const SectionLabel('Services'),
            _ServicesCard(services: fmt.m(state['services'])),
            ],
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = (widget.clock ?? DateTime.now)();
    return SpaceView(
      space: 'hub',
      showSearch: false,
      top: _buildDate(now),
      tabs: [for (var i = 0; i < tabLabels.length; i++) SpaceTab(tabLabels[i], _part(i))],
    );
  }

  /// BI26102404: the clock, then `Sunday · October 18, 2026`, on ONE line. Below 340 px the date shortens to `Sun 18 Oct`
  /// rather than wrapping; the date is never allowed a second line.
  Widget _buildDate(DateTime now) {
    return LayoutBuilder(
      key: const Key('hub-date-row'),
      builder: (context, box) {
        final narrow = box.maxWidth < 340;
        final dateSpan = narrow
            ? TextSpan(
                children: [
                  // Sconl, 28 Oct 2026: the day is always written in full ("Wednesday"); only the month shortens.
                  TextSpan(text: fmt.weekdaysFull[now.weekday - 1], style: const TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: ' ${now.day} ${fmt.monthsFull[now.month - 1].substring(0, 3)}', style: const TextStyle(fontWeight: FontWeight.w400)),
                ],
              )
            : TextSpan(
                children: [
                  TextSpan(text: fmt.weekdaysFull[now.weekday - 1], style: const TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: ' · ${fmt.monthsFull[now.month - 1]} ${now.day}, ${now.year}', style: const TextStyle(fontWeight: FontWeight.w400)),
                ],
              );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            HubClock(clock: widget.clock),
            const SizedBox(width: 12),
            Flexible(
              child: Text.rich(dateSpan, style: T.headline, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis),
            ),
          ],
        );
      },
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

  /// True when the signals snapshot is past its freshness budget (the amber tint replaces the old "as of" line).
  bool _signalsStale(AppServices services) {
    final at = services.store.signals.fetchedAt;
    if (at == null) return false;
    return DateTime.now().difference(at) > freshnessBudgetFor('signals');
  }

  Widget _buildSignalsStripOrFallback(
    BuildContext context,
    AppServices services,
    int alerts,
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
            // BI26101801: always three spots. Pulse's strip has at most one signal per area, so a quiet day shows
            // fewer than three; the rest are muted placeholders, tinted amber when the signals are past their budget.
            final stale = _signalsStale(services);
            return Wrap(
              key: const Key('hub-signal-strip'),
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (var idx = 0; idx < 3; idx++) ...[
                  if (idx > 0) Text('  ·  ', style: T.small.copyWith(color: C.text3)),
                  if (idx < validSignals.length)
                    _signalChip(context, validSignals[idx])
                  else
                    Text('All clear',
                        key: Key('hub-signal-clear-$idx'),
                        style: T.small.copyWith(color: stale ? C.amber : C.text3)),
                ],
              ],
            );
          }
        }
        return _needsYou(alerts, review);
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

  Widget _needsYou(int alerts, int review) {
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
    add('in review', review, C.cyan);
    // BI26101801: three spots here too; the third is a placeholder.
    parts.add(TextSpan(text: '  ·  ', style: T.small.copyWith(color: C.text3)));
    parts.add(TextSpan(text: 'All clear', style: T.small.copyWith(color: C.text3)));
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
