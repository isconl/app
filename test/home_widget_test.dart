import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/services/home_widget.dart';
import 'package:isconl/services/platform.dart' show SharedFile;
import 'package:isconl/services/share_intake.dart';
import 'package:isconl/ui/widgets/share_sheet.dart';

class Sink implements ShareSink {
  final inbox = <String>[];
  bool ok = true;
  @override
  Future<bool> addInbox({required String body, String title = ''}) async {
    inbox.add(body);
    return ok;
  }

  @override
  Future<bool> addTask({required String title}) async => ok;
  @override
  Future<bool> addJournal({required String body}) async => ok;
  @override
  Future<String> keepFile(SharedFile f) async => f.path;
}

final day = {
  'currentId': 'b2',
  'blocks': [
    {'id': 'b1', 'name': 'Deep work', 'startClock': '08:00', 'endClock': '10:00'},
    {'id': 'b2', 'name': 'Admin', 'startClock': '10:00', 'endClock': '11:30'},
  ],
};

Map<String, dynamic> task(String title, String due, {String status = 'today', String tag = ''}) =>
    {'TITLE': title, 'DUE_DATE': due, 'STATUS': status, 'TAG': tag.isEmpty ? '-' : tag};

void main() {
  final now = DateTime(2026, 10, 15, 10, 45);

  test('the current block and the time left', () {
    final s = buildWidgetSnapshot(day: day, tasks: const [], now: now);
    expect(s.block, 'Admin');
    expect(s.blockLeft, '45 min left');
    expect(s.asOf, '10:45');
    expect(buildWidgetSnapshot(day: day, tasks: const [], now: DateTime(2026, 10, 15, 9, 0)).blockLeft, '2 h 30 min left');
    expect(buildWidgetSnapshot(day: const {}, tasks: const [], now: now).block, '');
  });

  test('the next item is the earliest open one, never done or past, and never finance or health', () {
    final s = buildWidgetSnapshot(day: day, now: now, tasks: [
      task('Old', '2026-10-01'),
      task('Done one', '2026-10-15', status: 'done'),
      task('Pay the tax', '2026-10-15', tag: 'finance'),
      task('Book dentist', '2026-10-15', tag: 'Health'),
      task('Later', '2026-10-20'),
      task('Send the deck', '2026-10-16'),
    ]);
    expect(s.next, 'Send the deck, due 2026-10-16');
  });

  test('hiding the next item keeps the fact but drops the title', () {
    final s = buildWidgetSnapshot(day: day, now: now, hideNext: true, tasks: [task('Secret plan', '2026-10-15')]);
    expect(s.next, 'An item is due today');
    expect(s.toJson().values.join(), isNot(contains('Secret')));
  });

  test('no task due means an empty next line', () {
    expect(buildWidgetSnapshot(day: day, now: now, tasks: [task('No date', '-')]).next, '');
  });

  testWidgets('quick capture saves to the inbox and refuses an empty box', (t) async {
    final s = Sink();
    var done = 0;
    await t.pumpWidget(MaterialApp(home: Scaffold(body: QuickCapture(sink: s, onDone: () => done++))));
    await t.tap(find.byKey(const Key('capture-save')));
    await t.pumpAndSettle();
    expect(s.inbox, isEmpty);
    expect(find.text('Write something first.'), findsOneWidget);
    await t.enterText(find.byKey(const Key('capture-text')), 'call the bank');
    await t.tap(find.byKey(const Key('capture-save')));
    await t.pumpAndSettle();
    expect(s.inbox, ['call the bank']);
    expect(done, 1);
  });
}
