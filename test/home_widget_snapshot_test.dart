import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/services/home_widget_snapshot.dart';
import 'package:isconl/ui/quick_capture.dart' show voiceNoteInboxText;

void main() {
  final now = DateTime(2026, 10, 13, 10, 15);
  int ms(int h, int m, {int day = 13}) => DateTime(2026, 10, day, h, m).millisecondsSinceEpoch;

  final day = {
    'blocks': [
      {'name': 'Innovator', 'startClock': '08:00', 'endClock': '10:00', 'tasks': [{'title': 'Done earlier'}]},
      {
        'name': 'Visionary',
        'startClock': '10:00',
        'endClock': '12:00',
        'tasks': [
          {'title': 'Write the brief'},
          {'title': 'Pay the rent', 'axis': 'finance'},
          {'title': 'Already done', 'status': 'done'},
        ],
      },
      {'name': 'Creator', 'start': 840, 'end': 960, 'tasks': [{'title': 'Record the tutorial'}]},
      {'name': 'Rest', 'startClock': '21:00', 'endClock': '05:00'},
    ],
  };
  final calendar = {
    'events': [
      {'date': '2026-10-13', 'time': '11:30', 'title': 'Call with the CEO'},
      {'date': '2026-10-13', 'time': '09:00', 'title': 'Long past'},
      {'date': '2026-10-13', 'time': '15:00', 'title': 'Clinic', 'category': 'health'},
      {'date': '2026-10-20', 'time': '09:00', 'title': 'Next week'},
    ],
  };

  test('blocks carry minutes past midnight from either clocks or minutes, and keep the overnight block', () {
    final s = buildWidgetSnapshot(day: day, calendar: calendar, now: now);
    expect(s['blocks'], [
      {'name': 'Innovator', 'start': 480, 'end': 600},
      {'name': 'Visionary', 'start': 600, 'end': 720},
      {'name': 'Creator', 'start': 840, 'end': 960},
      {'name': 'Rest', 'start': 1260, 'end': 300},
    ]);
  });

  test('items are the open tasks of current and later blocks and the coming events, in time order', () {
    final items = buildWidgetSnapshot(day: day, calendar: calendar, now: now)['items'] as List;
    expect(items.map((i) => i['title']), ['Write the brief', 'Call with the CEO', 'Record the tutorial', 'Done earlier']);
    expect(items[0]['at'], ms(10, 0));
    expect(items[0]['until'], ms(12, 0));
    expect(items[1]['until'], ms(12, 0), reason: 'an event stays next for 30 minutes after it starts');
    // A block that already closed today rolls to tomorrow rather than vanishing.
    expect(items[3]['at'], ms(8, 0, day: 14));
  });

  test('nothing from finance or health, and nothing done, reaches the widget', () {
    final titles = (buildWidgetSnapshot(day: day, calendar: calendar, now: now)['items'] as List).map((i) => i['title']);
    expect(titles, isNot(contains('Pay the rent')));
    expect(titles, isNot(contains('Clinic')));
    expect(titles, isNot(contains('Already done')));
    expect(titles, isNot(contains('Next week')), reason: 'only the next two days');
    final tiered = buildWidgetSnapshot(
      day: {
        'blocks': [
          {'name': 'Work', 'startClock': '10:00', 'endClock': '11:00', 'tasks': [{'title': 'Secret', 'tier': 'T3'}]},
        ],
      },
      calendar: null,
      now: now,
    );
    expect(tiered['items'], isEmpty);
  });

  test('hidden titles keep the time and say only Event or Task', () {
    final items = buildWidgetSnapshot(day: day, calendar: calendar, now: now, hideTitles: true)['items'] as List;
    expect(items.map((i) => i['title']).toSet(), {'Task', 'Event'});
    expect(items[1]['at'], ms(11, 30));
  });

  test('nothing synced yet gives an empty snapshot, not an error', () {
    final s = buildWidgetSnapshot(day: null, calendar: 'garbage', now: now);
    expect(s['blocks'], isEmpty);
    expect(s['items'], isEmpty);
    expect(s['v'], 1);
  });

  test('a voice note inbox entry says how long it is and where the audio is', () {
    expect(voiceNoteInboxText(const Duration(seconds: 75), DateTime(2026, 10, 13, 9, 5), 'voice-1.m4a'),
        'Voice note, 1:15, recorded at 09:05. The audio is on the phone (voice-1.m4a) '
        'and is transcribed once the server takes audio.');
  });
}
