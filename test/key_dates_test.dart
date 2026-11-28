// BI26111595: key dates are worked out on the phone, every day and offline.
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/util/key_dates.dart';

Map<String, dynamic> d(String id, String title, String date, String kind, {String recurs = 'yearly'}) =>
    {'ID': id, 'TITLE': title, 'DATE': date, 'KIND': kind, 'RECURS': recurs};

void main() {
  final today = DateTime(2026, 11, 15);

  test('a birthday counts to its next day, and a placeholder 2000 is never an age', () {
    final k = keyDateFrom(d('D1', 'Olive', '2000-11-27', 'birthday'), today)!;
    expect(k.daysAway, 12);
    expect(k.yearKnown, isFalse);
    expect(k.what, 'birthday');
    expect(k.dayMonth(withYear: true), '27 Nov', reason: 'no year shown when it is a stand-in');
    final real = keyDateFrom(d('D2', 'Sconl', '1992-11-20', 'birthday'), today)!;
    expect(real.what, 'turns 34');
    expect(real.dayMonth(withYear: true), '20 Nov 1992');
  });

  test('a birthday already past this year counts to next year', () {
    expect(keyDateFrom(d('D1', 'X', '1990-03-01', 'birthday'), today)!.next, DateTime(2027, 3, 1));
  });

  test('29 Feb falls on 28 Feb in a common year', () {
    expect(keyDateFrom(d('D1', 'X', '1996-02-29', 'birthday'), today)!.next, DateTime(2027, 2, 28));
  });

  test('a past one-off counts toward its next round number of days', () {
    final k = keyDateFrom(d('D1', 'First day at Viva', '2026-08-01', 'first job', recurs: '-'), today)!;
    expect(k.daysSince, 106);
    expect(k.what, '365 days');
    expect(k.next, DateTime(2027, 8, 1));
  });

  test('today wins; then birthdays and deadlines are pulled forward by weight; three are picked', () {
    final list = [
      d('A', 'Work first', '2026-11-30', 'first', recurs: '-'), // 15 days, weight 1 -> 15
      d('B', 'Olive', '2000-12-05', 'birthday'), // 20 days / 1.6 -> 12.5
      d('C', 'Wedding', '2015-11-15', 'anniversary'), // today
      d('D', 'Far', '2000-06-01', 'birthday'), // far
    ];
    final p = pickKeyDates(list, today);
    expect(p.map((k) => k.id), ['C', 'B', 'A']);
  });

  test('the pick is the same all day and changes with the date', () {
    final list = [d('B', 'Olive', '2000-11-16', 'birthday'), d('A', 'Deadline', '2026-11-20', 'deadline', recurs: '-')];
    expect(pickKeyDates(list, today).first.id, 'B');
    expect(pickKeyDates(list, DateTime(2026, 11, 17)).first.id, 'A', reason: 'the birthday has passed for the year');
  });

  test('key dates become calendar events in the range, birthdays with the age only when known', () {
    final ev = keyDateEvents([d('D1', 'Olive', '2000-11-27', 'birthday'), d('D2', 'Sconl', '1992-11-20', 'birthday')],
        DateTime(2026, 11, 1), DateTime(2026, 12, 31));
    expect(ev['2026-11-27']!.single['title'], 'Olive');
    expect(ev['2026-11-20']!.single['title'], 'Sconl (turns 34)');
    expect(ev['2026-11-20']!.single['source'], 'keydate');
  });

  test('upcoming birthdays within two weeks, soonest first', () {
    final b = upcomingBirthdays([d('1', 'Far', '2000-12-20', 'birthday'), d('2', 'Near', '2000-11-17', 'birthday'),
      d('3', 'Mid', '2000-11-25', 'birthday')], today);
    expect(b.map((k) => k.title), ['Near', 'Mid']);
  });
}
