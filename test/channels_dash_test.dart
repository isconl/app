import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/ui/views/channels_dash_model.dart';

Map<String, dynamic> msg(String channel, DateTime t, {String status = 'new', String dir = 'in', String body = 'hello'}) => {
      'CHANNEL': channel,
      'RECEIVED_AT': t.toIso8601String(),
      'STATUS': status,
      'DIRECTION': dir,
      'BODY': body,
    };

void main() {
  final now = DateTime(2026, 10, 3, 12);

  test('counts unread, groups the last seven days by source, and compares with the week before', () {
    final feed = [
      msg('gmail', DateTime(2026, 10, 3, 9)),
      msg('teams', DateTime(2026, 10, 2, 9)),
      msg('whatsapp', DateTime(2026, 9, 30, 9), status: 'read'),
      msg('gmail', DateTime(2026, 9, 24, 9), status: 'read'),
      msg('gmail', DateTime(2026, 9, 23, 9), status: 'read'),
      msg('gmail', DateTime(2026, 10, 3, 10), dir: 'out'),
      msg('system', DateTime(2026, 10, 3, 8), body: '[system] x'),
    ];
    final d = ChannelsDash.from(feed: feed, jiraIssues: const [], buffer: const {}, now: now);
    expect(d.unread, 2);
    expect(d.perDay.length, 7);
    expect(d.perDay.last['Mail'], 1);
    expect(d.perDay[5]['Teams'], 1);
    expect(d.perDay[3]['Other'], 1);
    expect(d.unreadDelta, 3 - 2);
    expect(d.oldestUnanswered, now.difference(DateTime(2026, 10, 2, 9)));
  });

  test('Kanban splits by status from either issue shape', () {
    final d = ChannelsDash.from(feed: const [], buffer: const {}, now: now, jiraIssues: [
      {'status': 'To Do'},
      {'fields': {'status': {'name': 'In Progress'}}},
      {'status': 'In Review'},
      {'status': 'Done'},
      {'status': 'Done'},
    ]);
    expect(d.kanban, {'To do': 1, 'In progress': 1, 'Review': 1, 'Done': 2});
    expect(d.inProgress, 1);
  });

  test('Buffer shows at most three queued posts with their times', () {
    final d = ChannelsDash.from(feed: const [], jiraIssues: const [], now: now, buffer: {
      'queue': [
        {'text': 'one', 'dueAt': DateTime(2026, 10, 3, 15).toIso8601String()},
        {'text': 'two'},
        {'title': 'three'},
        {'text': 'four'},
      ],
    });
    expect(d.bufferNext.length, 3);
    expect(d.bufferNext.first.title, 'one');
    expect(d.bufferNext.first.when, isNotEmpty);
    expect(d.bufferNext[1].when, '');
  });

  test('empty inputs give zeros and no oldest', () {
    final d = ChannelsDash.from(feed: const [], jiraIssues: const [], buffer: const {}, now: now);
    expect(d.unread, 0);
    expect(d.oldestUnanswered, isNull);
    expect(d.bufferNext, isEmpty);
  });

  test('age labels', () {
    expect(ChannelsDash.ageLabel(const Duration(days: 3)), '3');
    expect(ChannelsDash.ageUnit(const Duration(hours: 5)), 'h');
    expect(ChannelsDash.ageUnit(const Duration(minutes: 12)), 'min');
  });
}
