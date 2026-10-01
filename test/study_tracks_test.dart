import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/theme.dart';
import 'package:isconl/ui/views/learning.dart';

void main() {
  group('BI26092611: Mobile Study tracks', () {
    testWidgets('a wide track spans two columns and a square track spans one', (tester) async {
      final wideGroup = LearningGroup.fromApi({
        'id': 'wide-track',
        'label': 'Wide Track',
        'description': 'A wide track spanning two columns',
        'color': '#3B82F6',
        'tile': 'wide',
        'sortOrder': 1,
        'courseCount': 4,
        'moduleCount': 20,
        'progressPct': 50,
      });

      final squareGroup = LearningGroup.fromApi({
        'id': 'square-track',
        'label': 'Square Track',
        'description': 'A square track taking one cell',
        'color': '#10B981',
        'tile': 'square',
        'sortOrder': 2,
        'courseCount': 2,
        'moduleCount': 8,
        'progressPct': 25,
      });

      const wideKey = Key('wide-card');
      const squareKey = Key('square-card');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              child: StaggeredGrid.count(
                crossAxisCount: 2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                children: [
                  StaggeredGridTile.fit(
                    crossAxisCellCount: wideGroup.isWide ? 2 : 1,
                    child: TrackCard(
                      key: wideKey,
                      group: wideGroup,
                      courses: const [],
                    ),
                  ),
                  StaggeredGridTile.fit(
                    crossAxisCellCount: squareGroup.isWide ? 2 : 1,
                    child: TrackCard(
                      key: squareKey,
                      group: squareGroup,
                      courses: const [],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      final wideRect = tester.getRect(find.byKey(wideKey));
      final squareRect = tester.getRect(find.byKey(squareKey));

      expect(wideGroup.isWide, isTrue);
      expect(squareGroup.isWide, isFalse);

      // In a 360px container with 8px crossAxisSpacing:
      // Wide spans full width (360px)
      // Square spans 1 column ((360 - 8) / 2 = 176px)
      expect(wideRect.width, 360);
      expect(squareRect.width, 176);
      expect(wideRect.width, greaterThan(squareRect.width * 1.8),
          reason: 'wide track must span both columns');

      // Check aspect ratio bounds: square card is about 1:1, wide card is about 2:1
      final wideRatio = wideRect.width / wideRect.height;
      final squareRatio = squareRect.width / squareRect.height;
      expect(wideRatio, inInclusiveRange(1.8, 2.8),
          reason: 'wide card should be about 2:1');
      expect(squareRatio, inInclusiveRange(0.8, 1.4),
          reason: 'square card should be about 1:1');
    });

    testWidgets('a missing or invalid colour falls back to C.green', (tester) async {
      // 1. Missing / null colour
      final missingColorGroup = LearningGroup.fromApi({
        'id': 'no-color',
        'label': 'Missing Color Track',
        'tile': 'square',
      });
      expect(missingColorGroup.color, C.green);

      // 2. Empty string colour
      final emptyColorGroup = LearningGroup.fromApi({
        'id': 'empty-color',
        'label': 'Empty Color Track',
        'color': '',
      });
      expect(emptyColorGroup.color, C.green);

      // 3. Invalid hex colour
      final invalidHexGroup = LearningGroup.fromApi({
        'id': 'invalid-hex',
        'label': 'Invalid Hex Track',
        'color': 'not-a-hex-value',
      });
      expect(invalidHexGroup.color, C.green);

      // 4. Valid hex colour
      final validHexGroup = LearningGroup.fromApi({
        'id': 'valid-hex',
        'label': 'Valid Hex Track',
        'color': '#58A6FF',
      });
      expect(validHexGroup.color, const Color(0xFF58A6FF));

      // Pump TrackCard with missing colour and verify it renders using C.green
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TrackCard(
              group: missingColorGroup,
              courses: const [],
            ),
          ),
        ),
      );

      final progressIndicator = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(progressIndicator.backgroundColor, C.border,
          reason: 'progress bar track must be C.border');
      expect(
        progressIndicator.valueColor?.value,
        C.green,
        reason: 'progress bar fill must fall back to C.green',
      );

      // Top band in C.green
      final containers = tester.widgetList<Container>(find.byType(Container));
      final hasTopBand = containers.any(
        (c) => c.color == C.green && c.constraints?.minHeight == 3.5,
      );
      expect(hasTopBand, isTrue, reason: 'thin top band should use C.green fallback');
    });

    testWidgets('no Text on the card contains an emoji codepoint', (tester) async {
      final emojiGroup = LearningGroup.fromApi({
        'id': 'corporate-mandate',
        'label': 'Corporate Mandate 🏛️ 💼',
        'description': 'Executive leadership 🚀, boardroom strategy 📊, and execution 🎯',
        'ICON': '🏛️',
        'color': '#BC8CFF',
        'tile': 'wide',
        'courseCount': 5,
        'moduleCount': 25,
        'progressPct': 80,
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TrackCard(
              group: emojiGroup,
              courses: const [],
            ),
          ),
        ),
      );

      final emojiRegex = RegExp(
        r'[\u{1F300}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}\u{1F1E6}-\u{1F1FF}\u{1F600}-\u{1F64F}\u{1F680}-\u{1F6FF}\u{1FA00}-\u{1FAFF}]',
        unicode: true,
      );

      final textWidgets = tester.widgetList<Text>(
        find.descendant(of: find.byType(TrackCard), matching: find.byType(Text)),
      );

      expect(textWidgets, isNotEmpty);
      for (final t in textWidgets) {
        final text = t.data ?? (t.textSpan?.toPlainText() ?? '');
        expect(
          emojiRegex.hasMatch(text),
          isFalse,
          reason: 'Rendered text "$text" must not contain any emoji codepoint',
        );
      }
    });

    test('hexColor helper handles various formats and invalid inputs', () {
      expect(hexColor(null), C.green);
      expect(hexColor(''), C.green);
      expect(hexColor('invalid'), C.green);
      expect(hexColor('12345'), C.green);
      expect(hexColor('#12345'), C.green);
      expect(hexColor('#3FB950'), const Color(0xFF3FB950));
      expect(hexColor('3FB950'), const Color(0xFF3FB950));
      expect(hexColor('#D29922'), const Color(0xFFD29922));
    });

    test('LearningGroup defaults tile to square when missing or invalid', () {
      final defaultTile = LearningGroup.fromApi({
        'id': 'test',
        'label': 'Test',
      });
      expect(defaultTile.tile, 'square');
      expect(defaultTile.isWide, isFalse);

      final invalidTile = LearningGroup.fromApi({
        'id': 'test',
        'label': 'Test',
        'tile': 'unknown_format',
      });
      expect(invalidTile.tile, 'square');
      expect(invalidTile.isWide, isFalse);

      final wideTile = LearningGroup.fromApi({
        'id': 'test',
        'label': 'Test',
        'tile': 'wide',
      });
      expect(wideTile.tile, 'wide');
      expect(wideTile.isWide, isTrue);
    });
  });
}
