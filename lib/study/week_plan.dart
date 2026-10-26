import 'pick/models.dart';

class DailyPlanItem {
  const DailyPlanItem({
    required this.dayIndex, // 1 to lengthDays
    required this.freeMinutes,
    required this.plannedMinutes,
    required this.trackId,
    required this.isMissed,
  });

  final int dayIndex;
  final int freeMinutes;
  final int plannedMinutes;
  final String trackId;
  final bool isMissed;
}

/// Cycle week plan (BI26101606):
/// At the start of each cycle (from /api/cycle-theme), plan the cycle: each day's free
/// study minutes from its blocks, filled by track debt first, then relevance to that week's events.
/// Shown in 4/5's week strip; re-planned when a day is missed.
class CycleWeekPlan {
  const CycleWeekPlan({
    required this.days,
    required this.totalPlannedMinutes,
  });

  final List<DailyPlanItem> days;
  final int totalPlannedMinutes;

  static CycleWeekPlan plan({
    required CycleInfo cycle,
    required Map<String, TrackState> tracks,
    required List<int> dailyFreeMinutes,
    required int currentDay,
  }) {
    final items = <DailyPlanItem>[];
    final length = cycle.lengthDays.clamp(1, 14);

    final sortedTracks = tracks.entries.toList()
      ..sort((a, b) => b.value.cyclesBehind.compareTo(a.value.cyclesBehind));

    var trackIdx = 0;
    var total = 0;

    for (var d = 1; d <= length; d++) {
      final free = d <= dailyFreeMinutes.length ? dailyFreeMinutes[d - 1] : 30;
      final isPast = d < currentDay;

      final track = sortedTracks.isNotEmpty ? sortedTracks[trackIdx % sortedTracks.length] : null;
      final planned = free.clamp(15, 60);

      items.add(DailyPlanItem(
        dayIndex: d,
        freeMinutes: free,
        plannedMinutes: planned,
        trackId: track?.key ?? '',
        isMissed: isPast,
      ));
      total += planned;
      trackIdx++;
    }

    return CycleWeekPlan(days: items, totalPlannedMinutes: total);
  }
}
