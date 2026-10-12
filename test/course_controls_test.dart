import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/api/client.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/data/module_ops.dart';
import 'package:isconl/ui/widgets/course_controls.dart';
import 'package:isconl/ui/widgets/module_lifecycle.dart';

import 'support/test_services.dart';

class CourseApi extends ScriptedApi {
  CourseApi(super.answers, {this.exportRefused = false, this.statusError});
  final bool exportRefused;
  final String? statusError;
  final List<Map<String, dynamic>> posts = [];

  @override
  Future<dynamic> postJson(String path, Map<String, dynamic> body, {bool cold = false}) async {
    posts.add({'path': path, ...body});
    if (exportRefused && path == '/api/learning/export/set') throw ApiException(403, 'forbidden');
    if (statusError != null && path == '/api/learning/course/status') return {'success': false, 'error': statusError};
    return {'success': true, 'ok': true};
  }
}

Map<String, dynamic> row(int id, String status, {String op = 'retire', String module = 'm-1', bool dry = false, String? error}) => {
      'id': id,
      'path': '/api/learning/module/manifest',
      'status': status,
      'error': error,
      'body': jsonEncode({'op': op, 'modules': [module], 'why': 'x', 'dryRun': dry}),
    };

void main() {
  setUp(() => CourseControls.exportAllowed = null);

  test('status and export read as the server holds them, with the safe reading for anything odd', () {
    expect(courseStatusOf({'STATUS': 'archived'}), 'archived');
    expect(courseStatusOf({'status': 'Disabled'}), 'disabled');
    expect(courseStatusOf({}), 'active');
    expect(courseStatusOf({'STATUS': 'weird'}), 'active');
    expect(courseExportOf({'EXPORT': 'publishable'}), 'publishable');
    expect(courseExportOf({'EXPORT': 'internal'}), 'internal');
    expect(courseExportOf({}), 'internal');
    expect(courseExportOf({'EXPORT': 'oops'}), 'internal');
  });

  test('a refusal gives the server\'s reason, and a 403 says whose session it needs', () {
    expect(courseWriteReason(403, {}), 'Only your own signed-in session can do this.');
    expect(courseWriteReason(200, {'errors': ['Not allowed.', 'Try later.']}), 'Not allowed. Try later.');
    expect(courseWriteReason(200, {'error': 'Course is locked'}), 'Course is locked');
    expect(courseWriteReason(200, {}), 'It did not apply.');
  });

  test('the outbox rows become one badge per module: the newest pending or refused action, nothing for sent or dry runs', () {
    final ops = moduleOpsFromOutbox([
      row(9, 'pending', op: 'restore', module: 'm-1'),
      row(8, 'failed', op: 'retire', module: 'm-1', error: 'old'),
      row(7, 'failed', op: 'retire', module: 'm-2', error: 'Module has live learners.'),
      row(6, 'sent', module: 'm-3'),
      row(5, 'pending', module: 'm-4', dry: true),
      {'id': 4, 'path': '/api/tasks', 'status': 'pending', 'body': '{}'},
      {'id': 3, 'path': '/api/learning/module/manifest', 'status': 'pending', 'body': 'not json'},
    ]);
    expect(ops.keys.toSet(), {'m-1', 'm-2'});
    expect(ops['m-1']!.op, 'restore');
    expect(ops['m-1']!.failed, isFalse);
    expect(ops['m-2']!.failed, isTrue);
    expect(ops['m-2']!.reason, 'Module has live learners.');
  });

  test('the badge labels say pending or refused with the action', () {
    final l = <String, dynamic>{'lifecycle': 'live'};
    expect(lifecycleBadges(l, op: const ModuleOp(op: 'retire', failed: false)).map((b) => b.label).toList(), ['retire pending']);
    expect(lifecycleBadges(l, op: const ModuleOp(op: 'restore', failed: true)).map((b) => b.label).toList(), ['restore refused']);
    expect(lifecycleBadges(l), isEmpty);
  });

  Future<({CourseApi api, AppServices services})> pump(WidgetTester tester, Widget body, {CourseApi? api, bool online = true}) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final a = api ?? CourseApi({});
    final services = (await tester.runAsync(() => buildTestServices(a, online: online)))!;
    await tester.pumpWidget(AppScope(services: services, child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: body)))));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 80));
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 40)));
    }
    return (api: a, services: services);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 80));
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 40)));
    }
  }

  const course = {'ID': 'c-1', 'STATUS': 'active', 'EXPORT': 'internal'};

  testWidgets('for Sconl\'s own session the probe is accepted and the export control is on; the probe repeats the current value', (tester) async {
    final r = await pump(tester, const CourseControls(courseId: 'c-1', course: course));
    expect(find.text('status: active'), findsOneWidget);
    expect(find.text('export: internal'), findsOneWidget);
    final probe = r.api.posts.firstWhere((p) => p['path'] == '/api/learning/export/set');
    expect(probe['course'], 'c-1');
    expect(probe['export'], 'internal', reason: 'the probe changes nothing');
    expect(tester.widget<TextButton>(find.byKey(const Key('course-export-change'))).onPressed, isNotNull);
  });

  testWidgets('for any other session the export control stays off', (tester) async {
    await pump(tester, const CourseControls(courseId: 'c-1', course: course), api: CourseApi({}, exportRefused: true));
    expect(tester.widget<TextButton>(find.byKey(const Key('course-export-change'))).onPressed, isNull);
    expect(tester.widget<TextButton>(find.byKey(const Key('course-status-change'))).onPressed, isNotNull);
  });

  testWidgets('changing the status posts the course id and the new status', (tester) async {
    final r = await pump(tester, const CourseControls(courseId: 'c-1', course: course));
    await tester.tap(find.byKey(const Key('course-status-change')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('archived'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('course-save')));
    await settle(tester);
    final sent = r.api.posts.firstWhere((p) => p['path'] == '/api/learning/course/status');
    expect(sent['courseId'], 'c-1');
    expect(sent['status'], 'archived');
  });

  testWidgets('changing the export class posts the course and the new class', (tester) async {
    final r = await pump(tester, const CourseControls(courseId: 'c-1', course: course));
    await tester.tap(find.byKey(const Key('course-export-change')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('publishable'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('course-save')));
    await settle(tester);
    final sets = r.api.posts.where((p) => p['path'] == '/api/learning/export/set').toList();
    expect(sets.last['course'], 'c-1');
    expect(sets.last['export'], 'publishable');
  });

  testWidgets('a refused status change shows the server\'s reason', (tester) async {
    await pump(tester, const CourseControls(courseId: 'c-1', course: course), api: CourseApi({}, statusError: 'Course has an active cohort.'));
    await tester.tap(find.byKey(const Key('course-status-change')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('disabled'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('course-save')));
    await settle(tester);
    expect(find.text('Course has an active cohort.'), findsOneWidget);
  });

  testWidgets('a retire made offline shows a pending badge, and a refusal shows the reason', (tester) async {
    final lesson = <String, dynamic>{'moduleId': 'm-1', 'lifecycle': 'live'};
    final r = await pump(tester, LifecycleBadges(lesson), online: false);
    expect(find.byKey(const Key('lifecycle-retire pending')), findsNothing);
    await tester.runAsync(() => r.services.mutations.moduleLifecycle(op: 'retire', moduleId: 'm-1', why: 'old'));
    await settle(tester);
    expect(find.byKey(const Key('lifecycle-retire pending')), findsOneWidget);

    final id = (await tester.runAsync(() => r.services.db.outboxHistory()))!.first['id'] as int;
    await tester.runAsync(() => r.services.db.markOutbox(id, 'failed', 'Module has live learners.'));
    await tester.runAsync(() => r.services.outbox.refreshCount());
    await settle(tester);
    expect(find.byKey(const Key('lifecycle-retire pending')), findsNothing);
    expect(find.byKey(const Key('lifecycle-retire refused')), findsOneWidget);
    expect(find.text('Module has live learners.'), findsOneWidget);
  });
}
