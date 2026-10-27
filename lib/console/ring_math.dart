/// BI26092648: the geometry of the Console ring in Player and Recorder modes.
///
/// The ring starts at 12 o'clock and runs clockwise, the same as the Progress arc.
library;

import 'dart:math' as math;
import 'dart:ui' show Offset;

/// The fraction of a lap (0 to 1) that a touch point is at, measured clockwise
/// from 12 o'clock around [center].
double angleFraction(Offset point, Offset center) {
  final dx = point.dx - center.dx;
  final dy = point.dy - center.dy;
  // atan2 gives 0 at 3 o'clock and runs clockwise on screen (y grows downwards);
  // shift a quarter turn so 0 is 12 o'clock.
  var a = math.atan2(dy, dx) + math.pi / 2;
  if (a < 0) a += 2 * math.pi;
  if (a >= 2 * math.pi) a -= 2 * math.pi;
  return a / (2 * math.pi);
}

/// Folds a drag that crosses 12 o'clock into the nearest end instead of jumping
/// from the last second to the first: going from 0.97 to 0.02 means "scrubbed to
/// the end", not "back to the start".
double unwrapDrag(double previous, double next) {
  if ((next - previous).abs() <= 0.5) return next;
  return previous > next ? 1.0 : 0.0;
}

/// A playback position for a ring fraction, clamped to the track.
Duration positionForFraction(double fraction, Duration total) {
  final f = fraction.clamp(0.0, 1.0);
  return Duration(milliseconds: (total.inMilliseconds * f).round());
}

/// The ring fraction of a playback position, 0 when the length is unknown.
double fractionOfPosition(Duration position, Duration total) {
  if (total <= Duration.zero) return 0;
  return (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
}

/// The Recorder's lap length: one turn of the ring per ten minutes.
const recorderLap = Duration(minutes: 10);

/// Completed laps of the recording clock (0 during the first ten minutes).
int lapCount(Duration elapsed) => elapsed.inMilliseconds ~/ recorderLap.inMilliseconds;

/// How far round the current lap the recording clock is, 0 to 1.
double lapFraction(Duration elapsed) =>
    (elapsed.inMilliseconds % recorderLap.inMilliseconds) / recorderLap.inMilliseconds;

/// `12:40`, or `1:02:03` once past an hour.
String clock(Duration d) {
  final total = d.inSeconds < 0 ? 0 : d.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}
