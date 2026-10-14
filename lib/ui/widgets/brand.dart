import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// THE MARK: the loop, and the agent's position on it
/// ═══════════════════════════════════════════════════════════════════════════
///
/// The grey annulus is the runtime loop - SENSE, THINK, GATE, ACT, LOG. The
/// green disc is where the agent currently is on it. The gap between them is
/// background, not a third colour, so the mark is correct on the night ground,
/// on a light launcher, and at 16px.
///
/// TWO COLOURS. Ring `C.text3` (#7d8590), node `C.green` (#3fb950). No
/// gradient, no glow, no outline.
///
/// Drawn rather than loaded from an asset: this is one path, one circle and one
/// masked hole, which a painter does exactly and a raster asset only
/// approximates. It also means the mark animates without a second file and
/// without adding an SVG dependency to pubspec.
///
/// ─── GEOMETRY, IDENTICAL TO dashboard/logo.svg ─────────────────────────────
///
/// Every number is exact on a 256 unit canvas and scales by size/256.
///
///   centre C  = (128, 128)
///   ring      R = 85 centreline, W = 42 thick  -> outer 106, inner 64
///   node      N = (196, 77), r = 30
///   gap       g = 8, so the masked hole is r + g = 38
///
/// N is ON the centreline exactly: its offset from C is (+68, -51) and
/// 68^2 + 51^2 = 7225 = 85^2. That is 17x(3,4,5), so the node sits on a
/// Pythagorean lattice point and nothing here is a rounded approximation. The
/// rest angle is atan(51/68) = 36.869898 degrees above horizontal.
///
/// The gap radius is fixed by requiring the hole's right edge flush with the
/// ring's outer edge: r + g = R - 68 + W/2 = 38. That one constraint makes the
/// content box exactly [22, 234] on both axes - a 212 square, centred, with a
/// uniform 22 margin. Nothing is nudged by eye.
class BrandGeometry {
  static const canvas = 256.0;
  static const cx = 128.0;
  static const cy = 128.0;
  static const ringRadius = 85.0;
  static const ringWidth = 42.0;
  static const nodeDx = 68.0;
  static const nodeDy = 51.0;
  static const nodeRadius = 30.0;
  static const gap = 8.0;

  static double get holeRadius => nodeRadius + gap;

  /// The node's resting angle, measured the way a canvas measures: radians,
  /// clockwise from the +x axis. Negative because the node sits above centre.
  static double get restAngle => math.atan2(-nodeDy, nodeDx);

  static double get circumference => 2 * math.pi * ringRadius;

  /// Asserted rather than trusted. If someone edits a constant, this fails in
  /// the test suite instead of shipping a mark whose node floats off its ring.
  static bool get nodeIsOnCentreline =>
      (nodeDx * nodeDx + nodeDy * nodeDy) == (ringRadius * ringRadius);
}

/// What the mark is currently saying.
///
/// Motion here is a status channel, not decoration. Each state means one thing
/// and nothing animates for the sake of animating.
enum BrandMotion {
  /// Idle and reachable. Completely still.
  rest,

  /// Something is running right now. The node orbits, linear, forever - an
  /// eased loop reads as a stutter every time it wraps.
  working,

  /// The splash: the node travels one revolution and draws the loop behind it.
  drawing,
}

/// The mark. [size] is the drawn square in logical pixels.
class BrandMark extends StatefulWidget {
  const BrandMark({
    super.key,
    this.size = 26,
    this.motion = BrandMotion.rest,
    this.onDrawn,
  });

  final double size;
  final BrandMotion motion;

  /// Fired once when a [BrandMotion.drawing] pass completes - the splash uses
  /// it to hand over to the shell.
  final VoidCallback? onDrawn;

  @override
  State<BrandMark> createState() => _BrandMarkState();
}

class _BrandMarkState extends State<BrandMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  static const _orbit = Duration(milliseconds: 1600);
  static const _draw = Duration(milliseconds: 1100);

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: _draw);
    _apply();
  }

  @override
  void didUpdateWidget(BrandMark old) {
    super.didUpdateWidget(old);
    if (old.motion != widget.motion) _apply();
  }

  void _apply() {
    _c.stop();
    switch (widget.motion) {
      case BrandMotion.rest:
        _c.value = 1;
      case BrandMotion.working:
        _c.duration = _orbit;
        _c.repeat();
      case BrandMotion.drawing:
        _c.duration = _draw;
        _c.forward(from: 0).then((_) {
          if (mounted) widget.onDrawn?.call();
        });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A person who asked the OS to stop animating things did not make an
    // exception for a logo.
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final motion = still ? BrandMotion.rest : widget.motion;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          painter: _BrandPainter(
            motion: motion,
            t: motion == BrandMotion.rest ? 1.0 : _c.value,
          ),
        ),
      ),
    );
  }
}

class _BrandPainter extends CustomPainter {
  _BrandPainter({required this.motion, required this.t});

  final BrandMotion motion;

  /// 0..1 through the current animation.
  final double t;

  /// Symmetric ease: calm at both ends, spending its speed in the middle. A
  /// linear sweep reads mechanical; an ease-out reads like it is falling over
  /// the line.
  static const _ease = Cubic(0.65, 0, 0.35, 1);

  @override
  void paint(Canvas canvas, Size size) {
    final g = size.width / BrandGeometry.canvas;
    final c = Offset(BrandGeometry.cx * g, BrandGeometry.cy * g);

    // How far round the node has travelled, and how much ring exists.
    final eased = motion == BrandMotion.rest ? 1.0 : _ease.transform(t);
    final sweep = switch (motion) {
      BrandMotion.rest => 1.0,
      BrandMotion.working => t,        // linear on purpose
      BrandMotion.drawing => eased,
    };

    final nodeAngle = BrandGeometry.restAngle +
        (motion == BrandMotion.rest ? 0 : sweep * 2 * math.pi);
    final nodeCentre = c +
        Offset(math.cos(nodeAngle), math.sin(nodeAngle)) *
            (BrandGeometry.ringRadius * g);

    // The node is only revealed in the last 18% of a drawing pass, as it lands
    // back on its own start point. Revealing it earlier means two things move at
    // once and the drawing gesture stops being legible.
    final nodeScale = motion == BrandMotion.drawing
        ? Curves.easeOutBack.transform(((eased - 0.818) / 0.182).clamp(0.0, 1.0))
        : 1.0;

    // ── the ring, with the node's hole punched out of it ──
    //
    // saveLayer + BlendMode.dstOut is the mask: the hole is cut from the ring
    // only, so whatever is behind the mark shows through it. Filling the gap
    // with a background colour instead would look identical on the night ground
    // and wrong on every other surface.
    canvas.saveLayer(Offset.zero & size, Paint());

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = BrandGeometry.ringWidth * g
      ..color = C.text3;

    if (motion == BrandMotion.drawing) {
      // Drawn BY the node's travel, so the arc's leading edge is exactly the
      // node's angle. Same parameter, same easing - if these diverged the node
      // would visibly outrun its own trail.
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: BrandGeometry.ringRadius * g),
        BrandGeometry.restAngle,
        sweep * 2 * math.pi,
        false,
        ring,
      );
    } else {
      canvas.drawCircle(c, BrandGeometry.ringRadius * g, ring);
    }

    canvas.drawCircle(
      nodeCentre,
      BrandGeometry.holeRadius * g,
      Paint()..blendMode = BlendMode.dstOut,
    );
    canvas.restore();

    // ── the node ──
    if (nodeScale > 0) {
      canvas.drawCircle(
        nodeCentre,
        BrandGeometry.nodeRadius * g * nodeScale,
        Paint()..color = C.green,
      );
    }
  }

  @override
  bool shouldRepaint(_BrandPainter old) =>
      old.t != t || old.motion != motion;
}
