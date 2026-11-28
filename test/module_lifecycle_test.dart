import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/api/client.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/theme.dart';
import 'package:isconl/ui/widgets/module_lifecycle.dart';

import 'support/test_services.dart';

/// Records the manifest posts; the dry run and the real call can be answered separately.
class ManifestApi extends ScriptedApi {
  ManifestApi() : super({});
  final List<Map<String, dynamic>> posts = [];
  Object previewAnswer = {
    'ok': true,
    'changes': [
      {'before': 'live', 'after': 'retired'}
    ],
    'summary': {'affectedLearners': 3},
  };
  Object applyAnswer = {'ok': true, 'applied': true};

  @override
  Future<dynamic> postJson(String path, Map<String, dynamic> body, {bool cold = false}) async {
    posts.add({'path': path, ...body});
    final a = body['dryRun'] == true ? previewAnswer : applyAnswer;
    if (a is ApiException) throw a;
    return a;
  }
}

Map<String, dynamic> lesson({String lifecycle = 'live', bool missing = false, String id = 'm-1'}) => {
      'file': 'module_01.md',
      'TITLE': 'First module',
      'moduleId': id,
      'lifecycle': lifecycle,
      if (missing) 'missing': true,
    };

void main() {
  test('live modules carry no badge, other states and missing do', () {
    expect(lifecycleBadges(lesson()), isEmpty);
    expect(lifecycleBadges({'file': 'x.md'}), isEmpty);
    expect(lifecycleBadges(lesson(lifecycle: 'retired')).map((b) => b.label), ['retired']);
    expect(lifecycleBadges(lesson(lifecycle: 'retired')).single.color, C.red);
    expect(lifecycleBadges(lesson(lifecycle: 'superseded')).single.color, C.amber);
    expect(lifecycleBadges(lesson(lifecycle: 'draft')).single.color, C.text3);
    expect(lifecycleBadges(lesson(missing: true)).map((b) => b.label), ['missing']);
    expect(lifecycleBadges(lesson(lifecycle: 'archived', missing: true)).map((b) => b.label), ['archived', 'missing']);
  });

  Future<(ManifestApi, AppServices)> pump(WidgetTester tester, {bool online = true, String op = 'retire', Map<String, dynamic>? l, Object? preview, Object? apply}) async {
    final api = ManifestApi();
    if (preview != null) api.previewAnswer = preview;
    if (apply != null) api.applyAnswer = apply;
    final services = (await tester.runAsync(() => buildTestServices(api, online: online)))!;
    await tester.pumpWidget(AppScope(
      services: services,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              key: const Key('open'),
              onPressed: () => showModuleLifecycleSheet(context, op: op, courseId: 'course-a', lesson: l ?? lesson()),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.byKey(const Key('open')));
    await tester.pump();
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 60)));
    await tester.pumpAndSettle();
    return (api, services);
  }

  testWidgets('the sheet shows the dry-run manifest and posts nothing real until Confirm', (tester) async {
    final (api, _) = await pump(tester);
    expect(find.text('Retire this module?'), findsOneWidget);
    expect(find.text('live to retired'), findsOneWidget);
    expect(find.text('3 learners with progress on it. Their progress is kept; the module leaves the course and stays in history.'), findsOneWidget);
    expect(api.posts.length, 1);
    expect(api.posts.single['dryRun'], true);
    expect(api.posts.single['op'], 'retire');
    expect(api.posts.single['modules'], ['m-1']);
  });

  testWidgets('Confirm sends the real change with the reason, and closes the sheet', (tester) async {
    final (api, _) = await pump(tester);
    await tester.enterText(find.byKey(const Key('lifecycle-why')), 'out of date');
    await tester.tap(find.byKey(const Key('lifecycle-confirm')));
    await tester.pump();
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 60)));
    await tester.pumpAndSettle();
    final real = api.posts.where((p) => p['dryRun'] == false).toList();
    expect(real.length, 1);
    expect(real.single['why'], 'out of date');
    expect(real.single['op'], 'retire');
    expect(find.text('Retire this module?'), findsNothing, reason: 'the sheet closed');
  });

  testWidgets('a refusal from the server is shown as its own reason and the sheet stays open', (tester) async {
    final (api, _) = await pump(tester, apply: {'ok': false, 'errors': ['Only a signed-in session can retire a module.']});
    await tester.tap(find.byKey(const Key('lifecycle-confirm')));
    await tester.pump();
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 60)));
    await tester.pumpAndSettle();
    expect(find.text('Only a signed-in session can retire a module.'), findsOneWidget);
    expect(find.text('Retire this module?'), findsOneWidget);
    expect(api.posts.where((p) => p['dryRun'] == false).length, 1);
  });

  testWidgets('a preview the server refuses shows the reason and leaves nothing to confirm', (tester) async {
    await pump(tester, preview: {'ok': false, 'errors': ['This module is already retired.']});
    expect(find.text('This module is already retired.'), findsOneWidget);
    final confirm = tester.widget<FilledButton>(find.byKey(const Key('lifecycle-confirm')));
    expect(confirm.onPressed, isNull);
  });

  testWidgets('Restore is worded as restore, and sends op restore', (tester) async {
    final (api, _) = await pump(tester, op: 'restore', l: lesson(lifecycle: 'retired'));
    expect(find.text('Restore this module?'), findsOneWidget);
    expect(find.text('Confirm restore'), findsOneWidget);
    expect(api.posts.single['op'], 'restore');
  });

  testWidgets('offline, the manifest is not shown, and Confirm queues the change in the outbox', (tester) async {
    final (api, services) = await pump(tester, online: false);
    expect(find.byKey(const Key('lifecycle-offline')), findsOneWidget);
    expect(api.posts, isEmpty, reason: 'no call while offline');
    await tester.tap(find.byKey(const Key('lifecycle-confirm')));
    await tester.pump();
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 60)));
    await tester.pumpAndSettle();
    await tester.runAsync(() => services.outbox.refreshCount());
    await tester.pumpAndSettle();
    expect(services.outbox.pending, 1);
    expect(api.posts, isEmpty, reason: 'queued, not sent');
    expect(find.text('Retire this module?'), findsNothing);
  });

  testWidgets('a lesson with no module id opens nothing', (tester) async {
    final api = ManifestApi();
    final services = (await tester.runAsync(() => buildTestServices(api)))!;
    await tester.pumpWidget(AppScope(
      services: services,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) => TextButton(key: const Key('open'), onPressed: () => showModuleLifecycleSheet(context, op: 'retire', courseId: 'c', lesson: {'file': 'x.md'}), child: const Text('open'))),
        ),
      ),
    ));
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
    expect(find.text('Retire this module?'), findsNothing);
    expect(api.posts, isEmpty);
  });

  testWidgets('the History expander lists hidden modules with badges, and only retired ones can be restored', (tester) async {
    final api = ManifestApi();
    final services = (await tester.runAsync(() => buildTestServices(api)))!;
    final hidden = [
      lesson(lifecycle: 'retired', id: 'm-r'),
      {...lesson(lifecycle: 'superseded', id: 'm-s'), 'TITLE': 'Old module', 'supersededBy': 'module_09.md'},
    ];
    await tester.pumpWidget(AppScope(services: services, child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ModuleHistory(courseId: 'course-a', hidden: hidden))))));
    expect(find.text('History · 2'), findsOneWidget);
    await tester.tap(find.byKey(const Key('module-history')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('lifecycle-retired')), findsOneWidget);
    expect(find.byKey(const Key('lifecycle-superseded')), findsOneWidget);
    expect(find.text('replaced by module_09.md'), findsOneWidget);
    expect(find.byKey(const Key('history-restore-m-r')), findsOneWidget);
    expect(find.byKey(const Key('history-restore-m-s')), findsNothing);
  });

  testWidgets('no hidden modules means no History expander at all', (tester) async {
    final api = ManifestApi();
    final services = (await tester.runAsync(() => buildTestServices(api)))!;
    await tester.pumpWidget(AppScope(services: services, child: const MaterialApp(home: Scaffold(body: ModuleHistory(courseId: 'c', hidden: [])))));
    expect(find.byKey(const Key('module-history')), findsNothing);
  });
}
