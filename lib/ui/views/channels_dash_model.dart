import '../../util/fmt.dart' as fmt;
import 'inbox_threads.dart';

/// BI26100128: the numbers behind the Channels dashboard, computed from rows
/// the app already holds (the inbox feed, the Jira board, the Buffer desk).
/// Pure, so it is tested without a widget. A figure the app cannot compute
/// from what it holds is null and the tile says "No data yet"; the hub
/// aggregate that fills those is a separate row (counts only, no content).
class ChannelsDash {
  ChannelsDash({
    required this.unread,
    required this.unreadDelta,
    required this.oldestUnanswered,
    required this.perDay,
    required this.kanban,
    required this.inProgress,
    required this.bufferNext,
  });

  final int unread;

  /// Items received in the last 7 days minus the 7 days before.
  final int unreadDelta;
  final Duration? oldestUnanswered;

  /// Seven days, oldest first; each map is source -> count.
  final List<Map<String, int>> perDay;
  final Map<String, int> kanban;
  final int inProgress;
  final List<({String title, String when})> bufferNext;

  static const sources = ['Mail', 'Teams', 'Jira', 'Buffer', 'SMS', 'Other'];

  static String sourceOf(String channel) {
    final k = channel.toLowerCase();
    if (k == 'email' || k == 'gmail' || k == 'outlook' || k == 'mail') return 'Mail';
    if (k.contains('teams')) return 'Teams';
    if (k == 'jira') return 'Jira';
    if (k == 'buffer' || k == 'social') return 'Buffer';
    if (k == 'sms') return 'SMS';
    return 'Other';
  }

  static String statusOf(Map<String, dynamic> issue) {
    final direct = fmt.s(issue['status']);
    if (direct.isNotEmpty) return direct;
    return fmt.s(fmt.m(fmt.m(issue['fields'])['status'])['name']);
  }

  static ChannelsDash from({
    required List<Map<String, dynamic>> feed,
    required List<Map<String, dynamic>> jiraIssues,
    required Map<String, dynamic> buffer,
    required DateTime now,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    final perDay = [for (var i = 0; i < 7; i++) <String, int>{}];
    var unread = 0, last7 = 0, prev7 = 0;
    DateTime? oldest;
    for (final m in feed) {
      if (messageKind(m) == MessageKind.system) continue;
      final inbound = fmt.s(m['DIRECTION']) != 'out';
      final t = fmt.parseDate(receivedAt(m));
      if (inbound && fmt.s(m['STATUS']) == 'new') {
        unread++;
        if (t != null && (oldest == null || t.isBefore(oldest))) oldest = t;
      }
      if (t == null || !inbound) continue;
      final day = DateTime(t.year, t.month, t.day);
      final ago = today.difference(day).inDays;
      if (ago >= 0 && ago < 7) {
        last7++;
        final src = sourceOf(fmt.s(m['CHANNEL']));
        final bucket = perDay[6 - ago];
        bucket[src] = (bucket[src] ?? 0) + 1;
      } else if (ago >= 7 && ago < 14) {
        prev7++;
      }
    }

    final kanban = {'To do': 0, 'In progress': 0, 'Review': 0, 'Done': 0};
    for (final i in jiraIssues) {
      final s = statusOf(i).toLowerCase();
      final key = s.contains('progress')
          ? 'In progress'
          : s.contains('review')
              ? 'Review'
              : (s.contains('done') || s.contains('closed') || s.contains('resolved'))
                  ? 'Done'
                  : 'To do';
      kanban[key] = kanban[key]! + 1;
    }

    final queue = fmt.lm(buffer['queue']);
    final next = <({String title, String when})>[];
    for (final p in queue.take(3)) {
      final text = fmt.s(p['text']).isNotEmpty ? fmt.s(p['text']) : fmt.s(p['title']);
      final raw = p['dueAt'] ?? p['scheduledAt'] ?? p['due_at'] ?? p['time'];
      final t = fmt.parseDate(raw);
      next.add((title: text.isEmpty ? 'Scheduled post' : text, when: t == null ? '' : _when(t, now)));
    }

    return ChannelsDash(
      unread: unread,
      unreadDelta: last7 - prev7,
      oldestUnanswered: oldest == null ? null : now.difference(oldest),
      perDay: perDay,
      kanban: kanban,
      inProgress: kanban['In progress']!,
      bufferNext: next,
    );
  }

  static String _when(DateTime t, DateTime now) {
    final sameDay = t.year == now.year && t.month == now.month && t.day == now.day;
    return sameDay ? fmt.hhmm(t) : fmt.shortDate(t.toIso8601String());
  }

  /// "3 d", "5 h", "12 min" for the oldest-unanswered tile.
  static String ageLabel(Duration d) {
    if (d.inDays >= 1) return '${d.inDays}';
    if (d.inHours >= 1) return '${d.inHours}';
    return '${d.inMinutes.clamp(0, 59)}';
  }

  static String ageUnit(Duration d) => d.inDays >= 1 ? 'd' : (d.inHours >= 1 ? 'h' : 'min');
}
