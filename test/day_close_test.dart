import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/api/client.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/ui/views/day_close.dart';
import 'package:isconl/util/day_close.dart';

import 'support/test_services.dart';

class _Api extends ApiClient {
  _Api() : super(baseUrl: 'http://test', token: 'test');
  @override
  Future<dynamic> getJson(String path, {bool cold = false}) async => <String, dynamic>{};
  @override
  Future<dynamic> postJson(String path, Map<String, dynamic> body, {bool cold = false}) async => <String, dynamic>{'ok': true};
}

void main() {
  final now = DateTime(2026, 10, 3, 20, 30); // a Saturday

  Map<String, dynamic> task(String id, String status, {String due = '-', String doneAt = '-'}) =>
      {'ID': id, 'TITLE': 'Task $id', 'STATUS': status, 'DUE_DATE': due, 'DONE_AT': doneAt};

  group('review times', () {
    test('one per day at the set time, none already past', () {
      final t = reviewTimes(now, hour: 21, minute: 0, days: 3);
      expect(t, [DateTime(2026, 10, 3, 21), DateTime(2026, 10, 4, 21), DateTime(2026, 10, 5, 21)]);
      final late = reviewTimes(DateTime(2026, 10, 3, 21, 30), hour: 21, minute: 0, days: 2);
      expect(late.first, DateTime(2026, 10, 4, 21));
    });

    test('weekends can be skipped', () {
      final t = reviewTimes(now, hour: 21, minute: 0, skipWeekends: true, days: 3);
      expect(t.map((d) => d.weekday).toSet().intersection({DateTime.saturday, DateTime.sunday}), isEmpty);
      expect(t.first, DateTime(2026, 10, 5, 21));
    });
  });

  test('done today uses DONE_AT; open is due today, overdue or in Today; dropped and done are not open', () {
    final tasks = [
      task('a', 'done', doneAt: '2026-10-03T09:00:00'),
      task('b', 'done', doneAt: '2026-10-02T09:00:00'),
      task('c', 'next', due: '2026-10-03'),
      task('d', 'next', due: '2026-09-30'),
      task('e', 'next', due: '2026-10-09'),
      task('f', 'today'),
      task('g', 'dropped', due: '2026-10-01'),
    ];
    expect(doneToday(tasks, now).map((t) => t['ID']), ['a']);
    expect(stillOpen(tasks, now).map((t) => t['ID']), ['c', 'd', 'f']);
  });

  test('the notification line', () {
    expect(dayCloseText(6, 3), 'Close the day: 6 done, 3 open');
    expect(dayCloseText(2, 0), 'Close the day: 2 done, nothing open');
  });

  test('prefs survive a restart and know when the day was closed', () async {
    final services = await buildTestServices(_Api());
    final a = DayClosePrefs.forTesting();
    await a.update(enabled: false, hour: 20, minute: 15, skipWeekends: true, closedOn: '2026-10-03', db: services.db);
    final b = DayClosePrefs.forTesting();
    await b.ensureLoaded(services.db);
    expect([b.enabled, b.hour, b.minute, b.skipWeekends], [false, 20, 15, true]);
    expect(b.closedToday(now), true);
    expect(b.closedToday(DateTime(2026, 10, 4)), false);
  });

  Future<AppServices> pump(WidgetTester t) async {
    t.view.physicalSize = const Size(600, 1600);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final services = (await t.runAsync(() => buildTestServices(_Api(), online: false)))!;
    final today = DateTime.now();
    String iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    services.store.state.value = {
      'tasks': [
        task('d1', 'done', doneAt: '${iso(today)}T08:00:00'),
        task('o1', 'next', due: iso(today)),
        task('o2', 'next', due: iso(today.subtract(const Duration(days: 2)))),
      ],
    };
    await t.pumpWidget(AppScope(services: services, child: const MaterialApp(home: DayCloseScreen())));
    await t.pump();
    return services;
  }

  Future<List<Map<String, dynamic>>> outbox(WidgetTester t, AppServices s) async {
    final rows = (await t.runAsync(() => s.db.pendingOutbox()))!;
    return [for (final r in rows) {'path': r['path'], 'body': jsonDecode('${r['body']}')}];
  }

  Future<void> settle(WidgetTester t) async {
    await t.pumpAndSettle();
    await t.runAsync(() => Future.delayed(const Duration(milliseconds: 80)));
    await t.pump();
  }

  testWidgets('shows what is done and what is open', (t) async {
    await pump(t);
    expect(find.text('Task d1'), findsOneWidget);
    expect(find.text('STILL OPEN · 2'), findsOneWidget);
    expect(find.text('Task o1'), findsOneWidget);
    await settle(t);
  });

  testWidgets('Tomorrow moves one task; the row leaves the list', (t) async {
    final s = await pump(t);
    await t.tap(find.descendant(of: find.byKey(const ValueKey('open-o1')), matching: find.text('Tomorrow')));
    await settle(t);
    final rows = await outbox(t, s);
    expect(rows.length, 1);
    expect(rows.first['path'], '/api/tasks/update');
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    expect(rows.first['body']['due_date'], startsWith('${tomorrow.year}-'));
    expect(rows.first['body']['taskId'], 'o1');
    expect(find.text('Task o1'), findsNothing);
    expect(find.text('STILL OPEN · 1'), findsOneWidget);
  });

  testWidgets('Carry all to tomorrow moves every open item', (t) async {
    final s = await pump(t);
    await t.tap(find.text('Carry all to tomorrow'));
    await settle(t);
    final rows = await outbox(t, s);
    expect(rows.map((r) => r['body']['taskId']).toSet(), {'o1', 'o2'});
    expect(find.text('Nothing left open.'), findsOneWidget);
  });

  testWidgets('Drop asks once, then marks the task dropped without deleting it', (t) async {
    final s = await pump(t);
    await t.tap(find.descendant(of: find.byKey(const ValueKey('open-o2')), matching: find.text('Drop')));
    await t.pumpAndSettle();
    expect(find.text('Drop this task?'), findsOneWidget);
    await t.tap(find.text('Drop').last);
    await settle(t);
    final rows = await outbox(t, s);
    expect(rows.single['path'], '/api/tasks/update');
    expect(rows.single['body']['status'], 'dropped');
  });

  testWidgets('closing saves the journal line and marks the day closed', (t) async {
    final s = await pump(t);
    await t.enterText(find.byType(TextField).last, 'The call with Joel went well');
    await t.pump();
    await t.tap(find.byKey(const Key('close-day')));
    await settle(t);
    final rows = await outbox(t, s);
    final j = rows.where((r) => r['path'] == '/api/journal/add').single;
    expect(j['body']['body'], 'The call with Joel went well');
    expect(DayClosePrefs.instance.closedToday(DateTime.now()), true);
    await DayClosePrefs.instance.update(closedOn: '');
  });
}
