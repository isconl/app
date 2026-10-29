import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/data/db.dart';
import 'package:isconl/ui/views/continue_reading.dart';
import 'package:isconl/ui/views/learning.dart' show ReadingBar;
import 'package:isconl/util/markdown.dart';

import 'console/test_services.dart';

/// BI26100325: "Continue reading" to the exact place, by block.
void main() {
  setUpAll(initSqfliteForTests);

  String module() {
    final b = StringBuffer('# A Module\n\n');
    for (final m in ['ORIENT', 'GRASP', 'SEE', 'BUILD']) {
      b.writeln('## $m · A Movement\n');
      for (var i = 0; i < 12; i++) {
        b.writeln('Paragraph $m-$i. ${'word ' * 60}\n');
      }
    }
    return b.toString();
  }

  Future<void> pumpModule(WidgetTester t, MarkdownAnchors a, ScrollController c, {double font = 15.5}) =>
      t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            controller: c,
            child: Markdown(module(),
                anchors: a,
                variant: MarkdownVariant.reading,
                baseStyle: TextStyle(fontSize: font, height: 1.6)),
          ),
        ),
      ));

  group('block anchors', () {
    testWidgets('a saved block re-opens at the same block after a font-size change', (t) async {
      await t.binding.setSurfaceSize(const Size(400, 800));
      final a = MarkdownAnchors();
      final c = ScrollController();
      await pumpModule(t, a, c);
      expect(a.count, greaterThan(40));
      c.jumpTo(c.position.maxScrollExtent * 0.55);
      await t.pump();
      final block = a.topVisible(c);
      final movement = a.movementOf(block);
      expect(block, greaterThan(10));
      expect(movement, contains('·'));

      // A bigger font reflows every block; the pixel offset would now be wrong.
      final a2 = MarkdownAnchors();
      final c2 = ScrollController();
      await pumpModule(t, a2, c2, font: 20);
      expect(a2.reveal(block), isTrue);
      await t.pump();
      expect(a2.topVisible(c2), block);
      expect(a2.movementOf(block), movement);
    });

    testWidgets('a block that no longer exists falls back to its movement', (t) async {
      final a = MarkdownAnchors();
      await pumpModule(t, a, ScrollController());
      expect(a.reveal(a.count + 50), isFalse);
      expect(a.firstBlockOf(a.movementOf(30)), isNotNull);
      expect(a.firstBlockOf('NO SUCH MOVEMENT'), isNull);
    });

    testWidgets('words left shrink as the block moves down', (t) async {
      final a = MarkdownAnchors();
      await pumpModule(t, a, ScrollController());
      expect(a.wordsFrom(0), greaterThan(a.wordsFrom(a.count ~/ 2)));
      expect(a.wordsFrom(a.count), 0);
    });
  });

  group('saved position', () {
    test('minutes left follow 200 words a minute, at least one while words remain', () {
      const a = ReadingAnchor(block: 4, movement: 'GRASP', blocksTotal: 20, wordsLeft: 450);
      expect(a.minutesLeft, 3);
      expect(const ReadingAnchor(block: 0, movement: '', blocksTotal: 1, wordsLeft: 1).minutesLeft, 1);
      expect(const ReadingAnchor(block: 0, movement: '', blocksTotal: 1, wordsLeft: 0).minutesLeft, 0);
    });

    test('the newest unfinished module wins; done drops off; pre-anchor rows are ignored', () async {
      final s = await buildTestServices();
      ReadingAnchor an(String t, int b) => ReadingAnchor(
          block: b, movement: 'GRASP · Why', blocksTotal: 30, wordsLeft: 600, title: t);
      await s.db.saveLessonResumeLocal(
          course: 'c1', file: 'old.md', scrollPct: 10, updatedAt: 1000, anchor: an('Old', 3));
      await s.db.saveLessonResumeLocal(
          course: 'c2', file: 'new.md', scrollPct: 50, updatedAt: 2000, anchor: an('New', 12));
      await s.db.saveLessonResumeLocal(
          course: 'c3', file: 'legacy.md', scrollPct: 90, updatedAt: 3000); // fraction only

      var latest = await s.db.latestUnfinishedReading();
      expect(latest?.file, 'new.md');
      expect(latest?.block, 12);
      expect(latest?.title, 'New');
      expect(latest?.movement, 'GRASP · Why');

      await s.db.saveLessonStatusLocal(course: 'c2', file: 'new.md', status: 'done');
      latest = await s.db.latestUnfinishedReading();
      expect(latest?.file, 'old.md');

      await s.db.saveLessonStatusLocal(course: 'c1', file: 'old.md', status: 'done');
      expect(await s.db.latestUnfinishedReading(), isNull);

      final one = await s.db.lessonAnchorLocal(course: 'c2', file: 'new.md');
      expect(one?.block, 12);
      expect(await s.db.lessonAnchorLocal(course: 'c3', file: 'legacy.md'), isNull);
    });

    test('an older write never overwrites a newer position', () async {
      final s = await buildTestServices();
      const a = ReadingAnchor(block: 9, movement: 'SEE', blocksTotal: 20, wordsLeft: 100, title: 'T');
      await s.db.saveLessonResumeLocal(course: 'c', file: 'f.md', scrollPct: 60, updatedAt: 5000, anchor: a);
      await s.db.saveLessonResumeLocal(
          course: 'c',
          file: 'f.md',
          scrollPct: 5,
          updatedAt: 1000,
          anchor: const ReadingAnchor(block: 1, movement: 'ORIENT', blocksTotal: 20, wordsLeft: 900));
      expect((await s.db.lessonAnchorLocal(course: 'c', file: 'f.md'))?.block, 9);
    });
  });

  group('Today card', () {
    testWidgets('shows title, course, movement and minutes left; absent when nothing is unfinished',
        (t) async {
      final s = (await t.runAsync(buildTestServices))!;
      Widget app() => AppScope(
          services: s,
          child: const MaterialApp(home: Scaffold(body: ContinueReadingCard())));

      // sqlite runs on real async, so let it finish outside the fake clock.
      Future<void> settle() async {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await t.pump();
      }

      await t.pumpWidget(app());
      await settle();
      expect(find.byKey(const Key('continue-reading-card')), findsNothing);

      await t.runAsync(() => s.db.saveLessonResumeLocal(
            course: 'sales-closing',
            file: 'm03.md',
            scrollPct: 40,
            anchor: const ReadingAnchor(
                block: 7,
                movement: 'BUILD · The Close',
                blocksTotal: 25,
                wordsLeft: 1000,
                title: 'The Close'),
          ));
      await t.pumpWidget(AppScope(
          key: UniqueKey(),
          services: s,
          child: const MaterialApp(home: Scaffold(body: ContinueReadingCard()))));
      await settle();
      expect(find.text('Continue reading'), findsOneWidget);
      expect(find.text('The Close'), findsOneWidget);
      expect(find.textContaining('sales-closing · BUILD · The Close · about 5 min left'), findsOneWidget);
    });
  });

  group('progress bar', () {
    testWidgets('shows under a module with a saved position and not otherwise', (t) async {
      final s = (await t.runAsync(buildTestServices))!;
      Future<void> show(String file) async {
        await t.pumpWidget(AppScope(
            key: UniqueKey(),
            services: s,
            child: MaterialApp(
                home: Scaffold(body: ReadingBar(course: 'c', file: file, color: Colors.green)))));
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await t.pump();
      }

      await show('none.md');
      expect(find.byKey(const Key('reading-bar')), findsNothing);

      await t.runAsync(() => s.db.saveLessonResumeLocal(
          course: 'c', file: 'half.md', scrollPct: 50, fraction: 0.5));
      await show('half.md');
      expect(find.byKey(const Key('reading-bar')), findsOneWidget);
      expect(t.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, 0.5);
    });
  });
}
