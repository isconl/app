import '../../util/day_blocks.dart';
import '../../util/fmt.dart' as fmt;

/// BI26100130: the numbers behind the Personal dashboard, from the rhythm and
/// day-plan rows the app already holds. Pure, so tested without a widget.
class HabitTrend {
  HabitTrend(this.id, this.name, this.streak, this.last14);
  final String id;
  final String name;
  final int streak;

  /// Running count of days done across the last 14 days, oldest first, so the
  /// sparkline rises when the habit holds and flattens when it slips.
  final List<double> last14;
}

class BlocksProgress {
  BlocksProgress(this.done, this.total, this.currentName);
  final int done;
  final int total;
  final String currentName;
}

/// Consecutive done days ending today (today not yet done does not break it).
int habitStreak(Map<String, dynamic> logs, String habitId, DateTime today) {
  var streak = 0;
  for (var i = 0; i < 400; i++) {
    final d = today.subtract(Duration(days: i));
    final done = fmt.b(fmt.m(logs[fmt.isoDate(d)])[habitId]);
    if (done) {
      streak++;
    } else if (i != 0) {
      break;
    }
  }
  return streak;
}

/// The top [n] habits by streak (ties keep their order), each with a 14-day trend.
List<HabitTrend> topHabits(List<Map<String, dynamic>> habits, Map<String, dynamic> logs, DateTime today, {int n = 3}) {
  final out = <HabitTrend>[];
  for (final h in habits) {
    final id = fmt.s(h['id']);
    if (id.isEmpty) continue;
    var running = 0.0;
    final series = <double>[];
    for (var i = 13; i >= 0; i--) {
      final d = today.subtract(Duration(days: i));
      if (fmt.b(fmt.m(logs[fmt.isoDate(d)])[id])) running++;
      series.add(running);
    }
    out.add(HabitTrend(id, fmt.s(h['name']).isEmpty ? id : fmt.s(h['name']), habitStreak(logs, id, today), series));
  }
  out.sort((a, b) => b.streak.compareTo(a.streak));
  return out.take(n).toList();
}

/// Blocks finished against blocks planned today, and the one running now.
/// [blocks] are the `/api/blocks` rows, or [kDefaultDayBlocks] when none.
BlocksProgress blocksProgress(List<Map<String, dynamic>> blocks, DateTime now) {
  final rows = blocks.isEmpty ? kDefaultDayBlocks : blocks;
  // The day starts at 05:00; minutes are measured from there so Rest wraps cleanly.
  int rel(int m) => ((m - 300) % 1440 + 1440) % 1440;
  final nowRel = rel(now.hour * 60 + now.minute);
  var done = 0;
  var current = '';
  for (final b in rows) {
    final s = rel(fmt.i(b['start']));
    var e = rel(fmt.i(b['end']));
    if (e <= s) e += 1440;
    if (e <= nowRel) {
      done++;
    } else if (s <= nowRel) {
      current = fmt.s(b['name']);
    }
  }
  return BlocksProgress(done, rows.length, current);
}
