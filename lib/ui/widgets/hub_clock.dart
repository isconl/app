import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../util/server_clock.dart';

/// BI26101801: the Hub's live clock, `HH:MM:SS`, 24-hour, in the app's green.
/// It ticks on the whole second and rebuilds only itself, never the Hub around it.
/// BI26102404: the clock's size, a little above the date line's height, and its weight.
/// Sconl, 28 Oct 2026: the app's own font, not seven-segment digits; tabular figures keep the digits from jumping.
const double hubClockSize = 16;

class HubClock extends StatefulWidget {
  const HubClock({super.key, this.clock});

  /// The time source (tests pass a fixed one). Defaults to the phone's clock corrected by the hub's `Date` header.
  final DateTime Function()? clock;

  @override
  State<HubClock> createState() => _HubClockState();
}

class _HubClockState extends State<HubClock> {
  Timer? _timer;

  DateTime _now() => (widget.clock ?? ServerClock.instance.now)();

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  /// Aligned to the next whole second, so the display flips with the second hand instead of drifting off it.
  void _schedule() {
    final ms = 1000 - _now().millisecond;
    _timer = Timer(Duration(milliseconds: ms <= 0 ? 1000 : ms), () {
      if (!mounted) return;
      setState(() {});
      _schedule();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  static String two(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final t = _now();
    final text = '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
    return Semantics(
      label: 'Time $text',
      excludeSemantics: true,
      child: Text(
        text,
        key: const Key('hub-clock'),
        maxLines: 1,
        style: const TextStyle(
          color: C.greenBright,
          fontSize: hubClockSize,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
