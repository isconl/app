import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import 'common.dart';

/// Context ring widget atop the Command tab: countdown ring for the current
/// block, 3 corner readouts, urgency-based color theming, and the particle-network
/// background. Ported from web console's context-ring and ctxField implementations.
class ContextRingCard extends StatefulWidget {
  const ContextRingCard({super.key});

  @override
  State<ContextRingCard> createState() => _ContextRingCardState();
}

class _ContextRingCardState extends State<ContextRingCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 40),
    )..repeat();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([services.store.dayBlock, services.store.state]),
      builder: (context, _) {
        final rawBlocks = fmt.lm(fmt.m(services.store.dayBlock.value)['blocks']);
        final dayNow = _calculateDayNow(rawBlocks);

        final curBlock = dayNow.current;
        final nextBlock = dayNow.next;

        final double blockLeftFrac = curBlock != null && curBlock.minutes > 0
            ? (curBlock.leftMins / curBlock.minutes).clamp(0.0, 1.0)
            : (1.0 - dayNow.fraction).clamp(0.0, 1.0);

        final urgency = _Urgency.fromFrac(blockLeftFrac);

        final cornerElapsed = curBlock != null
            ? _formatMinutes((curBlock.minutes - curBlock.leftMins).clamp(0, 9999).toDouble())
            : '';
        final cornerLength = curBlock != null
            ? '${(curBlock.minutes / 60).toStringAsFixed(1)}h · ${curBlock.third}'
            : (dayNow.before ? 'Day ahead' : (dayNow.after ? 'Day done' : 'Active day'));
        final cornerLoad = curBlock != null
            ? (curBlock.placeable
                ? '${curBlock.tasksCount}/${curBlock.slots} slots'
                : 'personal')
            : '';

        final centerBig = curBlock != null
            ? _formatMinutes(curBlock.leftMins)
            : (nextBlock != null
                ? _formatMinutes(nextBlock.inMins)
                : (dayNow.before ? 'Starts 08:00' : 'Closed'));
        final centerLabel = curBlock != null
            ? curBlock.name.toUpperCase()
            : (nextBlock != null ? 'NEXT: ${nextBlock.name.toUpperCase()}' : (dayNow.after ? 'DAY DONE' : 'COMMAND'));
        final centerSub = curBlock != null
            ? '${curBlock.startClock} - ${curBlock.endClock}'
            : (nextBlock != null ? 'starts ${nextBlock.startClock}' : '08:00 - 17:00');

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: C.panel,
            borderRadius: BorderRadius.circular(Sz.rLg),
            border: Border.all(color: C.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _anim,
                  builder: (context, _) => CustomPaint(
                    painter: _ParticleNetworkPainter(
                      progress: _anim.value,
                      color: urgency.primary,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: urgency.bg,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Console',
                                style: T.monoSmall.copyWith(
                                  fontSize: 10,
                                  color: urgency.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (cornerElapsed.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Text('$cornerElapsed elapsed', style: T.tiny),
                            ],
                          ],
                        ),
                        Text(cornerLength, style: T.tiny),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: SizedBox(
                        width: 170,
                        height: 170,
                        child: CustomPaint(
                          painter: _RingPainter(
                            fraction: blockLeftFrac,
                            urgency: urgency,
                          ),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  centerBig,
                                  style: T.headline.copyWith(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    color: urgency.primary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  centerLabel,
                                  style: T.tiny.copyWith(
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.5,
                                    color: C.text,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  centerSub,
                                  style: T.tiny.copyWith(fontSize: 10, color: C.text3),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (cornerLoad.isNotEmpty)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Badge2(
                            cornerLoad,
                            color: C.surface,
                            textColor: C.text2,
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatMinutes(double mins) {
    if (mins >= 60) {
      final h = mins ~/ 60;
      final m = (mins % 60).toInt();
      return m > 0 ? '${h}h ${m}m' : '${h}h';
    }
    if (mins >= 1) return '${mins.toInt()}m';
    return '${(mins * 60).round()}s';
  }

  _DayCalc _calculateDayNow(List<Map<String, dynamic>> rawBlocks) {
    final now = DateTime.now();
    final mins = now.hour * 60.0 + now.minute + now.second / 60.0;

    final defaultBlocks = [
      {'start': 300, 'end': 360, 'name': 'Protected', 'axis': 'protected', 'third': 'Ground', 'slots': 0, 'placeable': false},
      {'start': 360, 'end': 420, 'name': 'Learning', 'axis': 'learning', 'third': 'Ground', 'slots': 1, 'placeable': true},
      {'start': 420, 'end': 480, 'name': 'Flex', 'axis': 'flex', 'third': 'Ground', 'slots': 0, 'placeable': false},
      {'start': 480, 'end': 600, 'name': 'Innovator', 'axis': 'innovator', 'third': 'Work', 'slots': 4, 'placeable': true},
      {'start': 600, 'end': 660, 'name': 'Flex', 'axis': 'flex', 'third': 'Work', 'slots': 0, 'placeable': false},
      {'start': 660, 'end': 780, 'name': 'Visionary', 'axis': 'visionary', 'third': 'Work', 'slots': 4, 'placeable': true},
      {'start': 780, 'end': 840, 'name': 'Lunch', 'axis': 'lunch', 'third': 'Work', 'slots': 0, 'placeable': false},
      {'start': 840, 'end': 960, 'name': 'Creator', 'axis': 'creator', 'third': 'Work', 'slots': 4, 'placeable': true},
      {'start': 960, 'end': 1020, 'name': 'Connection', 'axis': 'connection', 'third': 'Work', 'slots': 2, 'placeable': true},
      {'start': 1020, 'end': 1080, 'name': 'Flex', 'axis': 'flex', 'third': 'Ground', 'slots': 0, 'placeable': false},
      {'start': 1080, 'end': 1260, 'name': 'Hearth', 'axis': 'home', 'third': 'Ground', 'slots': 0, 'placeable': false},
      {'start': 1260, 'end': 300, 'name': 'Rest', 'axis': 'rest', 'third': 'Rest', 'slots': 0, 'placeable': false},
    ];

    final blockList = rawBlocks.isNotEmpty ? rawBlocks : defaultBlocks;
    final List<_BlockInfo> parsed = [];

    for (final b in blockList) {
      final s = fmt.i(b['start'], fmt.i(b['START']));
      final e = fmt.i(b['end'], fmt.i(b['END']));
      final name = fmt.s(b['name'] ?? b['NAME'] ?? 'Block');
      final axis = fmt.s(b['axis'] ?? b['AXIS'] ?? 'work');
      final third = fmt.s(b['third'] ?? b['THIRD'] ?? 'Work');
      final slots = fmt.i(b['slots'] ?? b['SLOTS'], 0);
      final placeable = fmt.b(b['placeable'] ?? b['PLACEABLE'] ?? (slots > 0));

      final startClock = '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
      final endClock = '${(e ~/ 60).toString().padLeft(2, '0')}:${(e % 60).toString().padLeft(2, '0')}';
      final duration = e <= s ? (e + 1440 - s) : (e - s);

      parsed.add(_BlockInfo(
        start: s,
        end: e,
        name: name,
        axis: axis,
        third: third,
        slots: slots,
        placeable: placeable,
        minutes: duration,
        startClock: startClock,
        endClock: endClock,
      ));
    }

    _BlockInfo? current;
    _BlockInfo? next;

    for (final b in parsed) {
      final wraps = b.end <= b.start;
      final inside = wraps ? (mins >= b.start || mins < b.end) : (mins >= b.start && mins < b.end);
      if (inside) {
        final left = wraps && mins >= b.start ? (b.end + 1440.0) - mins : (b.end - mins);
        current = b.copyWith(leftMins: left);
      }
      if (b.start > mins && next == null) {
        next = b.copyWith(inMins: b.start - mins);
      }
    }

    final dayStart = 480.0; // 08:00
    final dayEnd = 1020.0;  // 17:00
    final frac = ((mins - dayStart) / (dayEnd - dayStart)).clamp(0.0, 1.0);

    return _DayCalc(
      mins: mins,
      fraction: frac,
      before: mins < dayStart,
      after: mins >= dayEnd,
      current: current,
      next: next ?? (parsed.isNotEmpty ? parsed[0].copyWith(inMins: (parsed[0].start + 1440) - mins) : null),
    );
  }
}

class _BlockInfo {
  const _BlockInfo({
    required this.start,
    required this.end,
    required this.name,
    required this.axis,
    required this.third,
    required this.slots,
    required this.placeable,
    required this.minutes,
    required this.startClock,
    required this.endClock,
    this.leftMins = 0.0,
    this.inMins = 0.0,
    this.tasksCount = 0,
  });

  final int start;
  final int end;
  final String name;
  final String axis;
  final String third;
  final int slots;
  final bool placeable;
  final int minutes;
  final String startClock;
  final String endClock;
  final double leftMins;
  final double inMins;
  final int tasksCount;

  _BlockInfo copyWith({double? leftMins, double? inMins, int? tasksCount}) =>
      _BlockInfo(
        start: start,
        end: end,
        name: name,
        axis: axis,
        third: third,
        slots: slots,
        placeable: placeable,
        minutes: minutes,
        startClock: startClock,
        endClock: endClock,
        leftMins: leftMins ?? this.leftMins,
        inMins: inMins ?? this.inMins,
        tasksCount: tasksCount ?? this.tasksCount,
      );
}

class _DayCalc {
  const _DayCalc({
    required this.mins,
    required this.fraction,
    required this.before,
    required this.after,
    this.current,
    this.next,
  });

  final double mins;
  final double fraction;
  final bool before;
  final bool after;
  final _BlockInfo? current;
  final _BlockInfo? next;
}

class _Urgency {
  const _Urgency(this.primary, this.dim, this.bg);
  final Color primary;
  final Color dim;
  final Color bg;

  factory _Urgency.fromFrac(double frac) {
    if (frac > 0.5) {
      return const _Urgency(C.greenBright, C.greenDim, C.greenBg);
    }
    if (frac > 0.2) {
      return const _Urgency(C.amber, Color(0xFF9E6A03), C.amberBg);
    }
    return const _Urgency(C.red, Color(0xFF8B1E17), C.redBg);
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.fraction, required this.urgency});
  final double fraction;
  final _Urgency urgency;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 10;

    // Track circle
    final trackPaint = Paint()
      ..color = C.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;
    canvas.drawCircle(center, radius, trackPaint);

    // Countdown arc starting at top (-pi/2)
    final sweepAngle = 2 * math.pi * fraction;
    final arcPaint = Paint()
      ..shader = LinearGradient(
        colors: [urgency.dim, urgency.primary],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 6;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweepAngle,
      false,
      arcPaint,
    );

    // Inner glow
    final glowPaint = Paint()
      ..color = urgency.bg
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius - 16, glowPaint);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.fraction != fraction || old.urgency.primary != urgency.primary;
}

class _ParticleNetworkPainter extends CustomPainter {
  const _ParticleNetworkPainter({required this.progress, required this.color});
  final double progress;
  final Color color;

  static const _nodesA = [
    [0.2, 0.3], [0.7, 0.4], [0.3, 0.6], [0.6, 0.7],
    [0.4, 0.8], [0.8, 0.8], [0.2, 0.9], [0.1, 0.4],
  ];
  static const _edgesA = [
    [0, 1], [0, 2], [1, 3], [2, 4], [3, 4], [3, 5], [4, 6], [5, 6], [0, 7], [2, 7]
  ];

  static const _nodesB = [
    [0.4, 0.35], [0.65, 0.45], [0.45, 0.55], [0.7, 0.6], [0.3, 0.5], [0.55, 0.7], [0.4, 0.25],
  ];
  static const _edgesB = [
    [0, 1], [1, 2], [2, 3], [0, 4], [4, 2], [2, 5], [3, 5], [0, 6]
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = color.withOpacity(0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final dotPaint = Paint()
      ..color = color.withOpacity(0.12)
      ..style = PaintingStyle.fill;

    _drawLayer(canvas, size, _nodesA, _edgesA, progress * 2 * math.pi, linePaint, dotPaint);
    _drawLayer(canvas, size, _nodesB, _edgesB, -progress * 2 * math.pi, linePaint, dotPaint);
  }

  void _drawLayer(
    Canvas canvas,
    Size size,
    List<List<double>> nodes,
    List<List<int>> edges,
    double angle,
    Paint linePaint,
    Paint dotPaint,
  ) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    final points = nodes.map((n) {
      final x = n[0] * size.width - cx;
      final y = n[1] * size.height - cy;
      final rx = x * math.cos(angle * 0.05) - y * math.sin(angle * 0.05) + cx;
      final ry = x * math.sin(angle * 0.05) + y * math.cos(angle * 0.05) + cy;
      return Offset(rx, ry);
    }).toList();

    for (final e in edges) {
      if (e[0] < points.length && e[1] < points.length) {
        canvas.drawLine(points[e[0]], points[e[1]], linePaint);
      }
    }

    for (final p in points) {
      canvas.drawCircle(p, 1.5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticleNetworkPainter old) =>
      old.progress != progress || old.color != color;
}
