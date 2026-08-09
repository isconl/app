import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/ui/widgets/brand.dart';

/// The mark's geometry is exact, and "exact" is only true while someone is
/// checking. These tests are the check: they prove the arithmetic the SVG and
/// the painter both claim, so an edit to one constant fails here instead of
/// shipping a mark whose node floats off its own ring.
void main() {
  group('geometry', () {
    test('the node sits ON the ring centreline, exactly', () {
      // 68^2 + 51^2 = 4624 + 2601 = 7225 = 85^2. That is 17x(3,4,5), which is
      // why every coordinate in the mark is an integer.
      expect(BrandGeometry.nodeIsOnCentreline, isTrue);
      expect(
        BrandGeometry.nodeDx * BrandGeometry.nodeDx +
            BrandGeometry.nodeDy * BrandGeometry.nodeDy,
        BrandGeometry.ringRadius * BrandGeometry.ringRadius,
      );
    });

    test('the gap keeps the content box a centred square', () {
      // The constraint that fixes the gap: the hole's right edge is flush with
      // the ring's outer edge, which makes the bounding box symmetric.
      expect(
        BrandGeometry.nodeRadius + BrandGeometry.gap,
        BrandGeometry.ringRadius -
            BrandGeometry.nodeDx +
            BrandGeometry.ringWidth / 2,
      );

      final outer = BrandGeometry.ringRadius + BrandGeometry.ringWidth / 2;
      final nodeX = BrandGeometry.cx + BrandGeometry.nodeDx;
      final nodeY = BrandGeometry.cy - BrandGeometry.nodeDy;
      final x0 = BrandGeometry.cx - outer;
      final x1 = math.max(BrandGeometry.cx + outer,
          nodeX + BrandGeometry.holeRadius);
      final y0 = math.min(BrandGeometry.cy - outer,
          nodeY - BrandGeometry.holeRadius);
      final y1 = BrandGeometry.cy + outer;

      expect(x0, 22);
      expect(x1, 234);
      expect(y0, 22);
      expect(y1, 234);
      expect(x1 - x0, y1 - y0, reason: 'the content box must be square');
      // Uniform margin on all four sides.
      expect(x0, BrandGeometry.canvas - x1);
      expect(y0, BrandGeometry.canvas - y1);
    });

    test('the rest angle matches the triple', () {
      expect(BrandGeometry.restAngle,
          closeTo(-math.atan(51 / 68), 1e-12));
      expect(BrandGeometry.restAngle * 180 / math.pi,
          closeTo(-36.869898, 1e-5));
    });

    test('circumference is the value the dash animation uses', () {
      // dashboard/style.css and logo-motion.svg both hardcode 534.0708. If this
      // drifts, the web splash desynchronises from its own stroke.
      expect(BrandGeometry.circumference, closeTo(534.0708, 1e-4));
    });

    test('the ring stays inside the canvas', () {
      expect(BrandGeometry.ringRadius + BrandGeometry.ringWidth / 2,
          lessThan(BrandGeometry.canvas / 2));
    });
  });

  group('painting', () {
    Future<void> pump(WidgetTester tester, BrandMotion motion) =>
        tester.pumpWidget(MaterialApp(
          home: Scaffold(body: Center(child: BrandMark(size: 64, motion: motion))),
        ));

    testWidgets('rest paints without animating', (tester) async {
      await pump(tester, BrandMotion.rest);
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('working keeps ticking', (tester) async {
      await pump(tester, BrandMotion.working);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
    });

    testWidgets('drawing completes and reports', (tester) async {
      var drawn = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: BrandMark(
            size: 64,
            motion: BrandMotion.drawing,
            onDrawn: () => drawn = true,
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 1200));
      await tester.pumpAndSettle();
      expect(drawn, isTrue, reason: 'the splash must hand over when it lands');
    });
  });
}
