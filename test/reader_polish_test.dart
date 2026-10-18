import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/api/client.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/services/narration.dart';
import 'package:isconl/theme.dart';
import 'package:isconl/ui/shell.dart';
import 'package:isconl/ui/views/learning.dart';
import 'package:isconl/util/reader_prefs.dart';

import 'support/test_services.dart';

// BI26101804: the module reader's chrome. Items 1 to 7 of the row; section 0 and the probe answers are in
// reader_callouts_test.dart.

class _Api extends ApiClient {
  _Api() : super(baseUrl: 'http://test', token: 'test');
  @override
  Future<dynamic> getJson(String path, {bool cold = false}) async => <String, dynamic>{};
  @override
  Future<dynamic> postJson(String path, Map<String, dynamic> body, {bool cold = false}) async => <String, dynamic>{'ok': true};
}

final _doc = List.generate(40, (i) => 'Paragraph $i: detailed content designed to take up vertical height on the page.').join('\n\n');

Future<void> settle(WidgetTester t) async {
  await t.pumpAndSettle();
  await t.runAsync(() => Future.delayed(const Duration(milliseconds: 60)));
  await t.pump();
}

void main() {
  tearDown(() => ReaderPrefs.instance.update(size: 1, relaxed: false, focus: false));

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

  test('there are three narration speeds and any other speed snaps to the nearest', () {
    expect(Narrator.speeds, [1.0, 1.25, 1.5]);
    expect(Narrator.snapSpeed(0.9), 1.0);
    expect(Narrator.snapSpeed(1.15), 1.25);
    expect(Narrator.snapSpeed(1.3), 1.25);
    expect(Narrator.snapSpeed(1.4), 1.5);
    expect(Narrator.snapSpeed(2.0), 1.5);
    expect(Narrator.snapSpeed(0.7), 1.0);
  });

  testWidgets('the Listen button is a fully rounded pill', (t) async {
    await pumpLesson(t);
    final button = t.widget<FilledButton>(find.byType(FilledButton).first);
    final shape = button.style!.shape!.resolve(<WidgetState>{});
    expect(shape, isA<StadiumBorder>());
    await settle(t);
  });

  testWidgets('speed and Aa both open one centred dialog holding the three speeds and the text controls', (t) async {
    final services = await pumpLesson(t);
    for (final key in ['listen-speed', 'reader-aa']) {
      await t.tap(find.byKey(Key(key)));
      await t.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget, reason: key);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byKey(const Key('speed-segments')), findsOneWidget);
      for (final s in ['1.0', '1.25', '1.5']) {
        expect(find.byKey(Key('speed-$s')), findsOneWidget, reason: s);
      }
      expect(find.byKey(const Key('size-M')), findsOneWidget);
      expect(find.byKey(const Key('spacing-relaxed')), findsOneWidget);
      // centred: the dialog's middle is near the screen's middle
      final c = t.getCenter(find.byKey(const Key('reader-comfort-dialog')));
      expect((c.dx - 300).abs(), lessThan(40));
      if (key == 'listen-speed') {
        await t.tap(find.byKey(const Key('speed-1.5')));
        await t.pumpAndSettle();
        expect(services.narrator.speed, 1.5);
      }
      await t.tap(find.byKey(const Key('reader-comfort-done')));
      await t.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
    }
    await settle(t);
  });

  testWidgets('the app bar holds one action, the download button, with the offline pin when the module is saved', (t) async {
    await pumpLesson(t);
    final bar = find.byType(AppBar);
    expect(find.descendant(of: bar, matching: find.byKey(const Key('reader-aa'))), findsNothing);
    expect(find.descendant(of: bar, matching: find.byKey(const Key('reader-tutor'))), findsNothing);
    expect(find.descendant(of: bar, matching: find.byTooltip(RegExp('Export this module'))), findsOneWidget);
    // saved on this device: the pin, not the plain arrow
    expect(find.byKey(const Key('export-saved')), findsOneWidget);
    expect(find.byKey(const Key('export-plain')), findsNothing);
    // one sync cloud in the bar
    expect(find.descendant(of: bar, matching: find.byType(SyncCloud)), findsOneWidget);
    await settle(t);
  });

  testWidgets('Ask the tutor is a secondary FAB directly above notes, toggles ask mode and shows a selected state', (t) async {
    await pumpLesson(t);
    final tutor = find.byTooltip('Ask the tutor');
    final notes = find.byTooltip('Notes');
    expect(tutor, findsOneWidget);
    final tp = t.getCenter(tutor);
    final np = t.getCenter(notes);
    expect(tp.dx, closeTo(np.dx, 0.5), reason: 'same column');
    expect(tp.dy, lessThan(np.dy), reason: 'above notes');
    expect(np.dy - tp.dy, lessThan(80), reason: 'directly above, no other button between');
    FloatingActionButton fab() => t.widget<FloatingActionButton>(find.ancestor(of: tutor, matching: find.byType(FloatingActionButton)));
    expect(fab().backgroundColor, NavTint.bg);
    expect((fab().shape as CircleBorder).side, BorderSide.none);
    await t.tap(tutor);
    await t.pump();
    expect(fab().backgroundColor, NavTint.bgOn);
    expect((fab().shape as CircleBorder).side.color, NavTint.border);
    await t.tap(tutor);
    await t.pump();
    expect(fab().backgroundColor, NavTint.bg);
    await settle(t);
  });

  testWidgets('every secondary FAB wears the same tint as the active bottom-nav tab', (t) async {
    await pumpLesson(t);
    final notesFab = t.widget<FloatingActionButton>(find.ancestor(of: find.byTooltip('Notes'), matching: find.byType(FloatingActionButton)));
    expect(notesFab.backgroundColor, NavTint.bg);
    expect(notesFab.foregroundColor, NavTint.fg);
    // the nav tint is the green the active sub-tab is drawn in (shell.dart reads the same three constants)
    expect(NavTint.bg, C.greenBg);
    expect(NavTint.fg, C.greenBright);
    await settle(t);
  });
}
