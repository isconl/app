import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/data/finance_repo.dart';
import 'package:isconl/ui/views/possessions.dart';

/// A fixture hub: the possessions registry in memory, recording every call.
class FakeHub {
  final rows = <Map<String, dynamic>>[
    {'ID': 'pos-laptop', 'ITEM': 'Laptop', 'CATEGORY': 'electronics', 'VALUE': '120000', 'ACQUIRED_DATE': '2025-01-10', 'LOCATION': 'home', 'CONDITION': 'good', 'NOTES': '-'},
    {'ID': 'pos-bike', 'ITEM': 'Bicycle', 'CATEGORY': 'vehicle', 'VALUE': '30000', 'ACQUIRED_DATE': '-', 'LOCATION': '-', 'CONDITION': '-', 'NOTES': '-'},
    {'ID': '-', 'ITEM': 'Placeholder', 'VALUE': '0'},
  ];
  final calls = <String>[];
  final bodies = <Map<String, dynamic>>[];

  Future<dynamic> get(String path) async {
    calls.add('GET $path');
    return {'possessions': rows};
  }

  Future<dynamic> post(String path, Map<String, dynamic> body) async {
    calls.add('POST $path');
    bodies.add(body);
    if (path.endsWith('/delete')) {
      rows.removeWhere((r) => r['ID'] == body['id']);
      return {'success': true, 'id': body['id']};
    }
    final id = (body['id'] as String?) ?? 'pos-new';
    rows.removeWhere((r) => r['ID'] == id);
    rows.add({'ID': id, 'ITEM': body['item'], 'VALUE': '${body['value']}'});
    return {'success': true, 'id': id, 'created': body['id'] == null};
  }

  FinanceRepository repo() => FinanceRepository(get: get, post: post);
}

Widget host(FakeHub hub, {required Future<bool> Function() unlock}) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: PossessionsSection(repo: hub.repo(), unlock: unlock))),
    );

void main() {
  group('repository', () {
    test('lists possessions by name, skipping rows without an id, and reads the registry columns', () async {
      final list = await FakeHub().repo().possessions();
      expect(list.map((p) => p.item), ['Bicycle', 'Laptop']);
      final laptop = list.last;
      expect(laptop.value, 120000);
      expect(laptop.location, 'home');
      expect(list.first.location, '', reason: "'-' is the registry's empty value");
    });

    test('a new possession posts without an id; an edit carries it in the body, never the URL', () async {
      final hub = FakeHub();
      final repo = hub.repo();
      expect(await repo.savePossession(const Possession(id: '', item: 'Phone', value: 25000)), 'pos-new');
      expect(hub.bodies.last.containsKey('id'), isFalse);
      await repo.savePossession(const Possession(id: 'pos-bike', item: 'Bicycle', value: 28000));
      expect(hub.bodies.last['id'], 'pos-bike');
      expect(hub.calls.where((c) => c.startsWith('POST')), ['POST /api/possessions/upsert', 'POST /api/possessions/upsert']);
    });

    test('a nameless new possession is refused before any call, and a refusal from the hub is an error', () async {
      final hub = FakeHub();
      expect(() => hub.repo().savePossession(const Possession(id: '', item: '  ')), throwsArgumentError);
      expect(hub.calls, isEmpty);
      final refusing = FinanceRepository(get: hub.get, post: (_, _) async => {'success': false, 'error': 'No possession x'});
      expect(() => refusing.deletePossession('x'), throwsStateError);
    });
  });

  group('section', () {
    testWidgets('values are masked until the device unlocks, and stay masked when it refuses', (tester) async {
      var answer = false;
      var asked = 0;
      final hub = FakeHub();
      await tester.pumpWidget(host(hub, unlock: () async {
        asked++;
        return answer;
      }));
      await tester.pumpAndSettle();
      expect(find.text('Laptop'), findsOneWidget);
      expect(find.textContaining('120'), findsNothing, reason: 'no figure shows while masked');
      expect(find.text('••••'), findsNWidgets(3), reason: 'the total and both rows');

      await tester.tap(find.byKey(const Key('possessions-reveal')));
      await tester.pumpAndSettle();
      expect(asked, 1);
      expect(find.textContaining('120'), findsNothing);

      answer = true;
      await tester.tap(find.byKey(const Key('possessions-reveal')));
      await tester.pumpAndSettle();
      expect(find.textContaining('120'), findsWidgets);
      expect(find.text('••••'), findsNothing);

      // Leaving the app masks them again.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(find.text('••••'), findsNWidgets(3));
    });

    testWidgets('delete asks first; cancelling deletes nothing, confirming removes the row', (tester) async {
      final hub = FakeHub();
      await tester.pumpWidget(host(hub, unlock: () async => false));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('possession-delete-pos-bike')));
      await tester.pumpAndSettle();
      expect(find.text('Delete Bicycle?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(hub.calls.where((c) => c.contains('delete')), isEmpty);

      await tester.tap(find.byKey(const ValueKey('possession-delete-pos-bike')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(hub.bodies.last, {'id': 'pos-bike'});
      expect(find.text('Bicycle'), findsNothing);
    });

    testWidgets('editing while masked does not show the value and keeps it when left empty', (tester) async {
      final hub = FakeHub();
      await tester.pumpWidget(host(hub, unlock: () async => false));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Laptop'));
      await tester.pumpAndSettle();
      expect(find.text('120000'), findsNothing, reason: 'the form must not reveal a hidden figure');
      await tester.ensureVisible(find.byKey(const Key('possession-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('possession-save')));
      await tester.pumpAndSettle();
      expect(hub.bodies.last['id'], 'pos-laptop');
      expect(hub.bodies.last['value'], 120000);
    });
  });
}
