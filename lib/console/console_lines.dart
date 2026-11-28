/// BI26101806: the two lines under the ring on every Console face, so the card keeps one shape. Pure strings, tested
/// from fixed times; the faces only draw them.
library;

import '../util/current_block.dart' show nairobiClock;

class ConsoleLines {
  const ConsoleLines(this.line1, this.line2, {this.chip = ''});
  final String line1;
  final String line2;

  /// A small chip at the end of line 2 (the progress face's load badge).
  final String chip;
}

/// `42m`, `1h 5m`, `2h`, or `under 1m`.
String leftWords(num mins) {
  if (mins < 1) return 'under 1m';
  final total = mins.floor();
  final h = total ~/ 60, m = total % 60;
  if (h == 0) return '${m}m';
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

/// The progress face (daily block): the current block and the time left, then the next block and its start.
///
/// Outside the plan: `Before the day starts` and `Day done`. [load] is the existing load badge (`2/4 slots`, `personal`).
ConsoleLines pulseLines({
  String? currentName,
  num? leftMins,
  String? nextName,
  String? nextStart,
  bool before = false,
  bool after = false,
  String load = '',
}) {
  final String line1;
  if (currentName != null) {
    line1 = '$currentName · ${leftWords(leftMins ?? 0)} left';
  } else if (before) {
    line1 = 'Before the day starts';
  } else if (after) {
    line1 = 'Day done';
  } else {
    line1 = 'Between blocks';
  }
  final String line2;
  if (nextName != null) {
    line2 = nextStart == null || nextStart.isEmpty ? 'Next: $nextName' : 'Next: $nextName at $nextStart';
  } else if (after) {
    line2 = 'Back at 08:00 tomorrow';
  } else {
    line2 = 'No more blocks today';
  }
  return ConsoleLines(line1, line2, chip: load);
}

enum RecState { idle, recording, paused, review }

String _mmss(Duration d) {
  final s = d.inSeconds;
  return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// `17 Oct 15:42` in Nairobi time.
String whenWords(int epochMs) {
  final t = nairobiClock(DateTime.fromMillisecondsSinceEpoch(epochMs, isUtc: true));
  return '${t.day} ${_months[t.month - 1]} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

/// The recorder face: the state, then where it goes and the last one.
///
/// [savedFor] is the length of the take just kept (shown as `Saved 02:13` until the next recording starts).
ConsoleLines recorderLines({
  required RecState state,
  Duration elapsed = Duration.zero,
  Duration? savedFor,
  int? lastAtMs,
}) {
  final line1 = switch (state) {
    RecState.recording => 'Recording ${_mmss(elapsed)}',
    RecState.paused => 'Paused ${_mmss(elapsed)}',
    RecState.review => 'Take ${_mmss(elapsed)} · keep or discard',
    RecState.idle => savedFor != null ? 'Saved ${_mmss(savedFor)}' : 'Ready to record',
  };
  final last = lastAtMs == null || lastAtMs <= 0 ? 'none yet' : 'last ${whenWords(lastAtMs)}';
  return ConsoleLines(line1, 'Saves to hold · Audio/recordings · $last');
}
