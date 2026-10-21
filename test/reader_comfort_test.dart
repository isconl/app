import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/api/client.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/ui/views/learning.dart';
import 'package:isconl/util/reader_prefs.dart';

import 'support/test_services.dart';

class _Api extends ApiClient {
  _Api() : super(baseUrl: 'http://test', token: 'test');
  @override
  Future<dynamic> getJson(String path, {bool cold = false}) async => <String, dynamic>{};
  @override
  Future<dynamic> postJson(String path, Map<String, dynamic> body, {bool cold = false}) async => <String, dynamic>{'ok': true};
}

final _doc = List.generate(60, (i) => 'Paragraph $i: detailed content designed to take up vertical height on the page.').join('\n\n');

/// Lets the real sqlite writes finish so no timer is left pending.
Future<void> settle(WidgetTester t) async {
  await t.pumpAndSettle();
  await t.runAsync(() => Future.delayed(const Duration(milliseconds: 60)));
  await t.pump();
}

void main() {
  tearDown(() => ReaderPrefs.instance.update(size: 1, relaxed: false, focus: false));

  test('the size multiplies the system scale and never passes 2.0', () {
    final p = ReaderPrefs.forTesting();
    expect(p.effectiveScale(1.0), 1.0);
    p.sizeStep = 0;
    expect(p.effectiveScale(1.0), 0.9);
    p.sizeStep = 2;
    expect(p.effectiveScale(1.0), 1.15);
    p.sizeStep = 3;
    expect(p.effectiveScale(1.0), 1.3);
    expect(p.effectiveScale(1.8), 2.0);
    expect(p.effectiveScale(3.0), 2.0);
  });

  test('the choice survives a restart', () async {
    final services = await buildTestServices(_Api());
    final a = ReaderPrefs.forTesting();
    await a.update(size: 3, relaxed: true, focus: true, db: services.db);
    final b = ReaderPrefs.forTesting();
    await b.ensureLoaded(services.db);
    expect(b.sizeStep, 3);
    expect(b.relaxed, true);
    expect(b.focus, true);
    expect(b.lineBoost, 0.2);
  });

  Future<AppServices> pumpLesson(WidgetTester t) async {
    t.view.physicalSize = const Size(600, 1000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final services = (await t.runAsync(() => buildTestServices(_Api(), online: false)))!;
    final data = {'content': _doc, 'status': 'new'};
    await t.runAsync(() => services.db.putSnapshot('lesson:c/f.md', data));
    services.store.detail('lesson', 'c/f.md', '/api/learning/lesson?course=c&file=f.md').value = data;
    await t.pumpWidget(AppScope(
      services: services,
      child: const MaterialApp(home: LessonScreen(course: 'c', file: 'f.md', title: 'Test', status: 'new')),
    ));
    await t.pump();
    await t.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
    await t.pump();
    return services;
  }

  double scaleOfBody(WidgetTester t) => MediaQuery.of(t.element(find.textContaining('Paragraph 0').first)).textScaler.scale(1.0);

  testWidgets('Aa opens the sheet; each size scales the text live', (t) async {
    await pumpLesson(t);
    expect(scaleOfBody(t), 1.0);
    await t.tap(find.byKey(const Key('reader-aa')));
    await t.pumpAndSettle();
    for (final (key, want) in [('S', 0.9), ('L', 1.15), ('XL', 1.3), ('M', 1.0)]) {
      await t.tap(find.byKey(Key('size-$key')));
      await settle(t);
      expect(scaleOfBody(t), want, reason: key);
    }
  });

  testWidgets('relaxed spacing adds 0.2 to the reading line height', (t) async {
    await pumpLesson(t);
    double height() {
      final rich = t.widget<RichText>(find.textContaining('Paragraph 0', findRichText: true).first);
      final root = rich.text as TextSpan;
      return (root.children?.first.style ?? root.style)!.height!;
    }

    final normal = height();
    await t.tap(find.byKey(const Key('reader-aa')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('spacing-relaxed')));
    await settle(t);
    expect(height(), closeTo(normal + 0.2, 0.001));
    await t.tap(find.byKey(const Key('spacing-normal')));
    await settle(t);
    expect(height(), closeTo(normal, 0.001));
  });

  testWidgets('focus mode hides the bar and buttons on the way down and restores them going up or at the top edge', (t) async {
    await pumpLesson(t);
    await ReaderPrefs.instance.update(focus: true);
    await t.pump();
    final slide = find.byType(AnimatedSlide);
    double barOffset() => t.widget<AnimatedSlide>(slide.first).offset.dy;
    expect(find.byKey(const Key('reader-top-edge')), findsNothing);

    final pos = t.state<ScrollableState>(find.byType(Scrollable).first).position;
    final g = await t.startGesture(const Offset(300, 500));
    await g.moveBy(const Offset(0, -300));
    await t.pump();
    await g.moveBy(const Offset(0, -300));
    await t.pump();
    await g.up();
    await t.pumpAndSettle();
    expect(pos.pixels, greaterThan(24));
    expect(find.byKey(const Key('reader-top-edge')), findsOneWidget);
    expect(t.widgetList<AnimatedSlide>(slide).any((s) => s.offset.dy < 0), true);

    await t.tapAt(const Offset(300, 10));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('reader-top-edge')), findsNothing);
    expect(barOffset(), 0);
    await settle(t);
  });

  testWidgets('focus off leaves the bar and buttons where they were', (t) async {
    await pumpLesson(t);
    final pos = t.state<ScrollableState>(find.byType(Scrollable).first).position;
    pos.jumpTo(600);
    await t.pump();
    expect(find.byKey(const Key('reader-top-edge')), findsNothing);
    expect(t.widgetList<AnimatedSlide>(find.byType(AnimatedSlide)).every((s) => s.offset.dy >= 0), true);
    await settle(t);
  });
}
