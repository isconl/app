import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/ui/widgets/track_admin.dart';

import 'support/test_services.dart';

class TrackApi extends ScriptedApi {
  TrackApi(super.answers, {this.refuse});
  final String? refuse;
  final List<Map<String, dynamic>> posts = [];

  @override
  Future<dynamic> postJson(String path, Map<String, dynamic> body, {bool cold = false}) async {
    posts.add({'path': path, ...body});
    if (refuse != null) return {'success': false, 'error': refuse};
    return {'success': true};
  }
}

final groups = [
  {'id': 'craft', 'label': 'Craft', 'description': 'Making things', 'sortOrder': 1, 'status': 'active'},
  {'id': 'old', 'label': 'Old track', 'sortOrder': 2, 'status': 'archived'},
];

void main() {
  test('a track id is one short word', () {
    for (final ok in ['craft', 'a', 'track-2', 'Track_3', ' craft ']) {
      expect(trackIdOk(ok), isTrue, reason: ok);
    }
    for (final bad in ['', '-x', 'two words', 'a' * 41, 'a/b', 'é']) {
      expect(trackIdOk(bad), isFalse, reason: bad);
    }
  });

  test('the body is trimmed, ordered, and refused with a sentence when the form is not fit', () {
    final ok = trackBody(id: ' craft ', label: ' Craft ', description: ' d ', sortOrder: ' 3 ');
    expect(ok.problem, isNull);
    expect(ok.body, {'id': 'craft', 'label': 'Craft', 'description': 'd', 'sortOrder': 3, 'status': 'active'});
    expect(trackBody(id: 'craft', label: 'Craft').body!['sortOrder'], 1, reason: 'no order given');
    expect(trackBody(id: 'craft', label: 'Craft', icon: ' I ').body!['icon'], 'I');
    expect(trackBody(id: 'two words', label: 'x').problem, contains('one short word'));
    expect(trackBody(id: 'craft', label: '  ').problem, 'A track needs a label.');
    expect(trackBody(id: 'craft', label: 'x', sortOrder: 'abc').problem, 'The order is a whole number.');
    expect(trackBody(id: 'craft', label: 'x', status: 'archived').body!['status'], 'archived');
  });

  test('archived is read from either spelling', () {
    expect(trackArchived({'status': 'archived'}), isTrue);
    expect(trackArchived({'STATUS': 'Archived'}), isTrue);
    expect(trackArchived({'status': 'active'}), isFalse);
    expect(trackArchived({}), isFalse);
  });

  Future<TrackApi> pump(WidgetTester tester, {String? refuse}) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = TrackApi({}, refuse: refuse);
    final services = (await tester.runAsync(() => buildTestServices(api)))!;
    await tester.pumpWidget(AppScope(services: services, child: MaterialApp(home: Scaffold(body: TrackAdminSheet(groups: groups)))));
    await tester.pump();
    return api;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 80));
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 40)));
    }
  }

  testWidgets('the sheet lists tracks, an archived one reads as archived and offers Restore', (tester) async {
    await pump(tester);
    expect(find.text('Craft'), findsOneWidget);
    expect(find.text('Old track'), findsOneWidget);
    expect(find.text('archived'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('track-archive-craft')), matching: find.text('Archive')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('track-archive-old')), matching: find.text('Restore')), findsOneWidget);
  });

  testWidgets('archiving asks first, then posts the id with status archived and flips the row', (tester) async {
    final api = await pump(tester);
    await tester.tap(find.byKey(const Key('track-archive-craft')));
    await tester.pumpAndSettle();
    expect(api.posts, isEmpty, reason: 'nothing before the confirm');
    await tester.tap(find.text('Archive').last);
    await settle(tester);
    final p = api.posts.single;
    expect(p['path'], '/api/learning/group/archive');
    expect(p['id'], 'craft');
    expect(p['status'], 'archived');
    expect(find.descendant(of: find.byKey(const Key('track-archive-craft')), matching: find.text('Restore')), findsOneWidget);
  });

  testWidgets('restoring posts status active', (tester) async {
    final api = await pump(tester);
    await tester.tap(find.byKey(const Key('track-archive-old')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore').last);
    await settle(tester);
    expect(api.posts.single['status'], 'active');
    expect(api.posts.single['id'], 'old');
  });

  testWidgets('a new track posts its trimmed body and appears in the list', (tester) async {
    final api = await pump(tester);
    await tester.tap(find.byKey(const Key('track-new')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('track-id')), 'craft2');
    await tester.enterText(find.byKey(const Key('track-label')), 'Craft two');
    await tester.enterText(find.byKey(const Key('track-order')), '5');
    await tester.tap(find.byKey(const Key('track-save')));
    await settle(tester);
    final p = api.posts.single;
    expect(p['path'], '/api/learning/group');
    expect(p['id'], 'craft2');
    expect(p['label'], 'Craft two');
    expect(p['sortOrder'], 5);
    expect(find.text('Craft two'), findsOneWidget);
  });

  testWidgets('a form that is not fit sends nothing and says why', (tester) async {
    final api = await pump(tester);
    await tester.tap(find.byKey(const Key('track-new')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('track-id')), 'two words');
    await tester.enterText(find.byKey(const Key('track-label')), 'Label');
    await tester.tap(find.byKey(const Key('track-save')));
    await settle(tester);
    expect(api.posts, isEmpty);
    expect(find.textContaining('one short word'), findsOneWidget);
  });

  testWidgets('editing keeps the id fixed and saves the changed label', (tester) async {
    final api = await pump(tester);
    await tester.tap(find.byKey(const Key('track-edit-craft')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const Key('track-id'))).enabled, isFalse);
    await tester.enterText(find.byKey(const Key('track-label')), 'Crafts');
    await tester.tap(find.byKey(const Key('track-save')));
    await settle(tester);
    expect(api.posts.single['id'], 'craft');
    expect(api.posts.single['label'], 'Crafts');
    expect(api.posts.single['status'], 'active');
  });

  testWidgets('a refusal shows the server\'s reason and leaves the row alone', (tester) async {
    await pump(tester, refuse: 'Track has live courses.');
    await tester.tap(find.byKey(const Key('track-archive-craft')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive').last);
    await settle(tester);
    expect(find.text('Track has live courses.'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('track-archive-craft')), matching: find.text('Archive')), findsOneWidget);
  });
}
