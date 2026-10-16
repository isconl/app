import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../data/store.dart';
import '../util/fmt.dart' as fmt;
import 'shell.dart' show SecondaryScreen;
import 'views/backlog.dart';
import 'views/course_standard_view.dart';
import 'views/ops.dart';
import 'views/planning.dart';
import 'views/sync_status_view.dart';

/// Model representing a subtle app bar status chip.
class StatusChip {
  const StatusChip({
    required this.text,
    required this.onTap,
  });

  final String text;
  final VoidCallback onTap;
}

/// Interface for views to declare their status chip without the shell knowing internals.
abstract interface class StatusChipSource {
  ValueListenable<StatusChip?> statusChipListenable(BuildContext context);
}

/// Simple wrapper for providing a static or direct ValueListenable as a StatusChipSource.
class ValueStatusChipSource implements StatusChipSource {
  const ValueStatusChipSource(this.listenable);
  final ValueListenable<StatusChip?> listenable;

  @override
  ValueListenable<StatusChip?> statusChipListenable(BuildContext context) =>
      listenable;
}

/// Scope widget allowing any subtree to declare a StatusChipSource.
class StatusChipScope extends InheritedWidget {
  const StatusChipScope({
    super.key,
    required this.source,
    required super.child,
  });

  final StatusChipSource source;

  static StatusChipSource? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<StatusChipScope>()
        ?.source;
  }

  @override
  bool updateShouldNotify(StatusChipScope oldWidget) =>
      source != oldWidget.source;
}

/// Equicycle context helper for computing the cycle theme and day in cycle.
class EqContext {
  EqContext(DateTime today)
      : cycleStart = _computeCycleStart(today),
        dayInCycle = _computeDayInCycle(today),
        eqYear = today.month < 6 ? today.year - 1 : today.year {
    cycleNum = ((today.difference(cycleStart).inDays) ~/ 28) + 1;
  }

  late final DateTime cycleStart;
  late final int dayInCycle;
  late final int cycleNum;
  final int eqYear;

  static const _themes = [
    'Plant', 'Push', 'Climb', 'Reap', 'Dig', 'Weave', 'Mend', 'Scout',
    'Scale', 'Make', 'Run', 'Stock', 'Audit',
  ];

  String get theme => _themes[(cycleNum - 1).clamp(0, 12)];

  static DateTime _eqStart(DateTime today) {
    final eqYear = today.month < 6 ? today.year - 1 : today.year;
    final june1 = DateTime(eqYear, 6, 1);
    final daysAhead = (7 - june1.weekday % 7) % 7;
    return DateTime(eqYear, 6, 1 + daysAhead);
  }

  static int _daysSince(DateTime today) {
    final start = _eqStart(today);
    final diff = DateTime(today.year, today.month, today.day)
        .difference(DateTime(start.year, start.month, start.day))
        .inDays;
    return diff < 0 ? 0 : diff;
  }

  static int _computeDayInCycle(DateTime today) => (_daysSince(today) % 28) + 1;

  static DateTime _computeCycleStart(DateTime today) => DateTime(
          today.year, today.month, today.day)
      .subtract(Duration(days: _computeDayInCycle(today) - 1));
}

/// Default freshness chip for views: `live`, `2m ago`, `offline`, `3 queued`.
/// Tapping opens the Sync status page.
class FreshnessStatusChipSource implements StatusChipSource {
  FreshnessStatusChipSource({this.snapshot});
  final Snapshot? snapshot;

  @override
  ValueListenable<StatusChip?> statusChipListenable(BuildContext context) {
    final services = AppScope.of(context);
    final snap = snapshot;
    final notifier = ValueNotifier<StatusChip?>(null);

    void update() {
      String text;
      if (services.outbox.pending > 0) {
        text = '${services.outbox.pending} queued';
      } else if (!services.sync.online) {
        text = 'offline';
      } else {
        final fetchedAt = snap?.fetchedAt ?? services.sync.lastFullSync;
        if (fetchedAt == null) {
          text = 'live';
        } else {
          final diff = DateTime.now().difference(fetchedAt);
          if (diff.inSeconds < 60) {
            text = 'live';
          } else if (diff.inMinutes < 60) {
            text = '${diff.inMinutes}m ago';
          } else if (diff.inHours < 24) {
            text = '${diff.inHours}h ago';
          } else {
            text = '${diff.inDays}d ago';
          }
        }
      }

      notifier.value = StatusChip(
        text: text,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const SecondaryScreen(
                title: 'Sync status',
                child: SyncStatusView(),
              ),
            ),
          );
        },
      );
    }

    final listenable = Listenable.merge([
      services.sync,
      services.outbox,
      if (snap != null) snap,
    ]);

    listenable.addListener(update);
    update();
    return notifier;
  }
}

/// Specific chip for Command (all sub-tabs): cycle day, e.g. `reap d12/28`.
/// Tapping opens Compass / Planning view.
class CommandStatusChipSource implements StatusChipSource {
  const CommandStatusChipSource();

  @override
  ValueListenable<StatusChip?> statusChipListenable(BuildContext context) {
    final services = AppScope.of(context);
    final notifier = ValueNotifier<StatusChip?>(null);

    void update() {
      final eq = fmt.m(fmt.m(services.store.state.value)['time']);
      String theme = fmt.s(eq['theme']).isNotEmpty
          ? fmt.s(eq['theme'])
          : (fmt.s(eq['cycleTheme']).isNotEmpty
              ? fmt.s(eq['cycleTheme'])
              : (fmt.s(eq['cycleWord']).isNotEmpty
                  ? fmt.s(eq['cycleWord'])
                  : EqContext(DateTime.now()).theme));
      int dayInCycle = eq['dayInCycle'] is int
          ? eq['dayInCycle'] as int
          : EqContext(DateTime.now()).dayInCycle;

      final text = '${theme.toLowerCase()} d$dayInCycle/28';
      notifier.value = StatusChip(
        text: text,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const SecondaryScreen(
                title: 'Planning',
                child: PlanningView(),
              ),
            ),
          );
        },
      );
    }

    services.store.state.addListener(update);
    update();
    return notifier;
  }
}

/// Specific chip for Systems > Ops: `vm ok` or `vm 2 down`.
/// Tapping opens Ops view.
class OpsStatusChipSource implements StatusChipSource {
  const OpsStatusChipSource();

  @override
  ValueListenable<StatusChip?> statusChipListenable(BuildContext context) {
    final services = AppScope.of(context);
    final notifier = ValueNotifier<StatusChip?>(null);

    void update() {
      int downCount = 0;
      final hosted = services.store.hostedServices.value;
      if (hosted is Map) {
        if (hosted['down'] is int) {
          downCount = hosted['down'] as int;
        } else {
          final rows = fmt.lm(hosted['services']);
          for (final r in rows) {
            if (r['up'] == false || r['running'] == false) downCount++;
          }
        }
      }

      final ops = services.store.ops.value;
      if (ops is Map) {
        if (ops['down'] is int) {
          downCount = ops['down'] as int;
        } else if (ops['groups'] is Map) {
          final groups = ops['groups'] as Map;
          int gDown = 0;
          for (final g in groups.values) {
            if (g is List) {
              for (final s in g) {
                if (s is Map && s['running'] == false) gDown++;
              }
            }
          }
          if (gDown > 0) downCount = gDown;
        } else if (ops['services'] is List) {
          int sDown = 0;
          for (final s in ops['services'] as List) {
            if (s is Map && s['running'] == false) sDown++;
          }
          if (sDown > 0) downCount = sDown;
        }
      }

      final text = downCount > 0 ? 'vm $downCount down' : 'vm ok';
      notifier.value = StatusChip(
        text: text,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const SecondaryScreen(
                title: 'Ops',
                child: OpsView(),
              ),
            ),
          );
        },
      );
    }

    final listenable = Listenable.merge([
      services.store.hostedServices,
      services.store.ops,
    ]);
    listenable.addListener(update);
    update();
    return notifier;
  }
}

/// Specific chip for Systems > Backlog: `slate 298`.
/// Tapping opens Backlog view.
class BacklogStatusChipSource implements StatusChipSource {
  const BacklogStatusChipSource();

  @override
  ValueListenable<StatusChip?> statusChipListenable(BuildContext context) {
    final services = AppScope.of(context);
    final notifier = ValueNotifier<StatusChip?>(null);

    void update() {
      int count = 0;
      final data = services.store.backlog.value;
      if (data is Map) {
        if (data['total'] is int) {
          count = data['total'] as int;
        } else {
          final projects = fmt.lm(data['projects']);
          for (final p in projects) {
            count += fmt.lm(p['rows']).length;
          }
          if (count == 0 && data['tasks'] is List) {
            count = (data['tasks'] as List).length;
          }
        }
      }

      final text = 'slate $count';
      notifier.value = StatusChip(
        text: text,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const SecondaryScreen(
                title: 'Backlog',
                child: BacklogView(),
              ),
            ),
          );
        },
      );
    }

    services.store.backlog.addListener(update);
    update();
    return notifier;
  }
}

/// Specific chip for Study: course standard, e.g. `std v3.1`.
/// Tapping opens CourseStandardView.
class StudyStatusChipSource implements StatusChipSource {
  const StudyStatusChipSource();

  @override
  ValueListenable<StatusChip?> statusChipListenable(BuildContext context) {
    final services = AppScope.of(context);
    final notifier = ValueNotifier<StatusChip?>(null);

    void update() {
      String stdVer = 'v3.1';
      final data = services.store.learning.value;
      if (data is Map) {
        final v = fmt.s(data['standardVersion']).isNotEmpty
            ? fmt.s(data['standardVersion'])
            : (fmt.s(data['standard']).isNotEmpty
                ? fmt.s(data['standard'])
                : (fmt.s(data['courseStandard']).isNotEmpty
                    ? fmt.s(data['courseStandard'])
                    : 'v3.1'));
        stdVer = v.startsWith('v') ? v : 'v$v';
      }

      final text = 'std $stdVer';
      notifier.value = StatusChip(
        text: text,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const SecondaryScreen(
                title: 'Course Standard',
                child: CourseStandardView(),
              ),
            ),
          );
        },
      );
    }

    services.store.learning.addListener(update);
    update();
    return notifier;
  }
}
