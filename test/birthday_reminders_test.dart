// BI26111595: birthdays in the next two weeks show at the top of Hub, worked out on the phone.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/api/client.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/ui/widgets/birthday_reminders.dart';

import 'support/test_services.dart';

class _Api extends ApiClient {
  _Api() : super(baseUrl: 'http://test', token: 'test');
  @override
  Future<dynamic> getJson(String path, {bool cold = false, bool stored = true}) async => <String, dynamic>{};
}

void main() {
  testWidgets('a birthday in three days shows; one in a month does not; no placeholder year', (t) async {
    final services = (await t.runAsync(() => buildTestServices(_Api(), online: false)))!;
    services.store.dates.value = {
      'dates': [
        {'ID': 'b1', 'KIND': 'birthday', 'TITLE': 'Olive', 'DATE': '2000-11-18', 'RECURS': 'yearly'},
        {'ID': 'b2', 'KIND': 'birthday', 'TITLE': 'Far', 'DATE': '1990-12-20', 'RECURS': 'yearly'},
        {'ID': 'b3', 'KIND': 'birthday', 'TITLE': 'Sconl', 'DATE': '1992-11-15', 'RECURS': 'yearly'},
      ],
    };
    await t.pumpWidget(AppScope(
      services: services,
      child: MaterialApp(home: Scaffold(body: BirthdayReminders(clock: () => DateTime(2026, 11, 15)))),
    ));
    await t.pump();
    expect(find.byKey(const Key('hub-birthday-b1')), findsOneWidget);
    expect(find.byKey(const Key('hub-birthday-b2')), findsNothing);
    expect(find.textContaining('in 3 days'), findsOneWidget);
    expect(find.textContaining('2000'), findsNothing);
    expect(find.textContaining('turns 34'), findsOneWidget, reason: 'a real year gives the age');
    expect(find.textContaining('Today: '), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });
}
