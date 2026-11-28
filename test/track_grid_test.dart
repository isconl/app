// BI26101803: the Tracks tab rhythm (wide, two squares, wide, ...) and the module list subtitle.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/ui/views/learning.dart';
import 'package:isconl/ui/widgets/track_grid.dart';

LearningGroup _g(int i) => LearningGroup.fromApi({
      'id': 't$i',
      'label': 'Track $i',
      'description': 'About track $i',
      'color': '#10B981',
      'tile': i.isEven ? 'wide' : 'square', // the old per-track flag must not decide the shape any more
      'sortOrder': i,
      'courseCount': 2,
      'moduleCount': 8,
      'progressPct': 10,
    });

Future<List<Rect>> _pump(WidgetTester t, int n) async {
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: SizedBox(
          width: 360,
          child: TrackGrid(groups: [for (var i = 0; i < n; i++) _g(i)], coursesFor: (_) => const []),
        ),
      ),
    ),
  ));
  return [for (var i = 0; i < n; i++) t.getRect(find.byKey(Key('track-tile-$i')))];
}

void main() {
  test('the span pattern: wide, square, square, wide, square, square; a lone square becomes wide', () {
    expect(trackSpans(0), <int>[]);
    expect(trackSpans(1), [2]);
    expect(trackSpans(2), [2, 2]);
    expect(trackSpans(3), [2, 1, 1]);
    expect(trackSpans(4), [2, 1, 1, 2]);
    expect(trackSpans(5), [2, 1, 1, 2, 2]);
    expect(trackSpans(6), [2, 1, 1, 2, 1, 1]);
  });

  for (final n in [1, 3, 4, 6]) {
    testWidgets('$n tracks: widths follow the rhythm', (t) async {
      final rects = await _pump(t, n);
      final spans = trackSpans(n);
      for (var i = 0; i < n; i++) {
        expect(rects[i].width, spans[i] == 2 ? 360 : 176, reason: 'tile $i');
      }
      // two squares sit side by side on one row with the same height
      for (var i = 0; i < n - 1; i++) {
        if (spans[i] == 1 && spans[i + 1] == 1 && (i == 0 || spans[i - 1] == 2)) {
          expect(rects[i].top, rects[i + 1].top);
          expect(rects[i].height, rects[i + 1].height);
          expect(rects[i + 1].left, closeTo(rects[i].right + 8, 0.01));
        }
      }
      // rows run in track order, top to bottom
      for (var i = 1; i < n; i++) {
        expect(rects[i].top, greaterThanOrEqualTo(rects[i - 1].top));
      }
      // a wide tile is at least 2.2:1 and a square at least 1:1 tall
      for (var i = 0; i < n; i++) {
        if (spans[i] == 2) expect(rects[i].height, greaterThanOrEqualTo(360 / 2.2 - 0.5));
        if (spans[i] == 1) expect(rects[i].height, greaterThanOrEqualTo(176 - 0.5));
      }
    });
  }

  group('module subtitle', () {
    Future<void> row(WidgetTester t, Map<String, dynamic> lesson) => t.pumpWidget(MaterialApp(
          home: Scaffold(body: LessonRow(courseId: 'c', lesson: lesson)),
        ));

    testWidgets('a module with a subtitle shows it under the heading, one line, grey', (t) async {
      await row(t, {'file': 'm.md', 'title': 'Three Word Title', 'subtitle': 'What the module is about, in a line'});
      final sub = t.widget<Text>(find.byKey(const Key('module-subtitle')));
      expect(sub.data, 'What the module is about, in a line');
      expect(sub.maxLines, 1);
      expect(sub.overflow, TextOverflow.ellipsis);
      expect(t.getTopLeft(find.byKey(const Key('module-subtitle'))).dy, greaterThan(t.getTopLeft(find.byKey(const Key('module-title'))).dy));
    });

    testWidgets('a module without one shows nothing extra when it has no objective either', (t) async {
      await row(t, {'file': 'm.md', 'title': 'Three Word Title'});
      expect(find.byKey(const Key('module-subtitle')), findsNothing);
    });

    testWidgets('a module without a subtitle falls back to the first sentence of its objective, cut at 80 characters', (t) async {
      await row(t, {'file': 'm.md', 'title': 'Three Word Title', 'objective': 'Calculate the effect. A second sentence follows.'});
      expect(t.widget<Text>(find.byKey(const Key('module-subtitle'))).data, 'Calculate the effect.');
      final long = 'Explain ${'a very long objective ' * 10}end.';
      await row(t, {'file': 'm.md', 'title': 'Three Word Title', 'objective': long});
      final shown = t.widget<Text>(find.byKey(const Key('module-subtitle'))).data!;
      expect(shown.length, lessThanOrEqualTo(80));
      expect(shown.endsWith('…'), isTrue);
    });
  });
}
