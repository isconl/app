import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../services/october.dart';
import '../../theme.dart';
import '../shell.dart' show openNavRoute;
import 'common.dart';

/// PI26093009: the Data October ring on Today. One ring for the share decided and moved, three arcs for the tiers,
/// "Day n of 28" in the middle (the feed's day, never this clock), and one line of counts under it. It hides when
/// the hub has no feed, polls every five minutes, and after the last day turns into a before-and-after card.
/// Counts only: no file or folder name is ever drawn.
class OctoberRingCard extends StatefulWidget {
  const OctoberRingCard({super.key, this.api, this.poll = true, this.now, this.onOpen});
  final OctoberApi? api;
  final bool poll;
  final DateTime Function()? now;

  /// The week's plan; by default Slate.
  final VoidCallback? onOpen;

  @override
  State<OctoberRingCard> createState() => _OctoberRingCardState();
}

class _OctoberRingCardState extends State<OctoberRingCard> {
  OctoberProgress? _p;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      if (widget.poll) _timer = Timer.periodic(const Duration(minutes: 5), (_) => _load());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final api = widget.api ?? HubOctoberApi(AppScope.of(context).api);
      final p = await api.progress();
      if (mounted) setState(() => _p = p);
    } catch (_) {
      // Offline or an older hub: keep whatever is showing, draw nothing if there was nothing.
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    if (p == null || !p.available) return const SizedBox.shrink();
    final now = (widget.now ?? DateTime.now)();
    final open = widget.onOpen ?? () => openNavRoute(context, 'slate');
    if (p.ended) return _summary(p, open);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Panel(
        key: const Key('october-ring'),
        onTap: open,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Data October', style: T.title),
          const SizedBox(height: 10),
          Center(
            child: SizedBox(
              width: 132,
              height: 132,
              child: Stack(alignment: Alignment.center, children: [
                CustomPaint(size: const Size(132, 132), painter: _RingPainter(p)),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('Day ${p.dayN} of ${p.daysTotal}', key: const Key('october-day'), style: T.body2.copyWith(color: C.text, fontWeight: FontWeight.w600)),
                  Text('${(p.share * 100).round()}% moved', style: T.tiny),
                ]),
              ]),
            ),
          ),
          const SizedBox(height: 10),
          Text('${p.line}.', key: const Key('october-line'), style: T.small),
          const SizedBox(height: 4),
          Wrap(spacing: 12, children: [
            _legend('Working', _RingPainter.working),
            _legend('Vault', _RingPainter.vault),
            _legend('Archive', _RingPainter.archive),
          ]),
          if (p.needsChunk(now))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Next chunk ready: about ${OctoberProgress.gb(p.nextChunkGb)} GB, about ${p.nextChunkMinutes} minutes.', key: const Key('october-next'), style: T.small.copyWith(color: C.amber)),
            ),
        ]),
      ),
    );
  }

  Widget _legend(String label, Color c) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: T.tiny),
      ]);

  Widget _summary(OctoberProgress p, VoidCallback open) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Panel(
          key: const Key('october-summary'),
          onTap: open,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Data October, done', style: T.title),
            const SizedBox(height: 6),
            Text('Before: ${OctoberProgress.gb(p.totalGb)} GB in OneDrive.', style: T.small),
            Text('After: ${OctoberProgress.gb(p.movedGb)} GB moved, ${OctoberProgress.gb(p.duplicatesGb)} GB of duplicates gone, ${p.foldersDecided} of ${p.foldersTotal} folders decided.', style: T.small),
          ]),
        ),
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.p);
  final OctoberProgress p;

  static const working = Color(0xFF58A6FF);
  static const vault = Color(0xFF3FB950);
  static const archive = Color(0xFFD29922);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final stroke = size.width * 0.12;
    final r = rect.deflate(stroke / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = C.border;
    canvas.drawArc(r, 0, math.pi * 2, false, base);
    var start = -math.pi / 2;
    for (final (gb, color) in [(p.working, working), (p.vault, vault), (p.archiveCold, archive)]) {
      if (gb <= 0 || p.totalGb <= 0) continue;
      final sweep = (gb / p.totalGb).clamp(0.0, 1.0) * math.pi * 2;
      canvas.drawArc(r, start, sweep, false, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = color);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.p != p;
}
