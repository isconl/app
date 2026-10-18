/// BI26092648: the Player and Recorder faces of the Console card.
///
/// Same layout as Progress: the 170 px ring, then a row under it. In Player the
/// ring is the timeline and the centre plays; in Recorder the ring is the
/// recording clock and the centre records. Theme tokens only; the recorder's red
/// is the same urgent tone Progress uses when a block is nearly over.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../console/console_lines.dart';
import '../../console/console_mode.dart';
import '../../console/console_player.dart';
import '../../console/console_recorder.dart';
import '../../console/console_services.dart';
import '../../console/ring_math.dart';
import '../../theme.dart';

const double kConsoleRingSize = 170;

/// The ring: a track, an arc, and (recording) a glow that follows the input level.
class ConsoleRingPainter extends CustomPainter {
  const ConsoleRingPainter({
    required this.fraction,
    required this.color,
    required this.dim,
    required this.fill,
    this.level = 0,
    this.laps = 0,
  });

  final double fraction;
  final Color color;
  final Color dim;
  final Color fill;

  /// 0 to 1 input level; draws a soft glow on the arc while it is above zero.
  final double level;

  /// Completed laps; each shows as a small tick above the ring.
  final int laps;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 10;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = C.border
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6);

    final sweep = 2 * math.pi * fraction.clamp(0.0, 1.0);
    if (level > 0.02 && sweep > 0) {
      canvas.drawArc(
          rect,
          -math.pi / 2,
          sweep,
          false,
          Paint()
            ..color = color.withValues(alpha: 0.18 + 0.4 * level)
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = 6 + 10 * level
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 + 6 * level));
    }
    canvas.drawArc(
        rect,
        -math.pi / 2,
        sweep,
        false,
        Paint()
          ..shader = LinearGradient(colors: [dim, color]).createShader(rect)
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 6);

    canvas.drawCircle(center, radius - 16, Paint()..color = fill);

    for (var i = 0; i < math.min(laps, 6); i++) {
      final x = center.dx - (math.min(laps, 6) - 1) * 4 + i * 8;
      canvas.drawCircle(Offset(x, center.dy - radius - 1), 1.8, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant ConsoleRingPainter old) =>
      old.fraction != fraction || old.color != color || old.level != level || old.laps != laps || old.fill != fill;
}

// ---- Shared layout (BI26101806) ----

/// Every face is the ring, a 10 px gap, then two lines: line 1 (13 px, w600, one line) and line 2 (11 px, one line).
/// The lines sit in fixed-height slots, so the card keeps the same height when you double-tap between faces.
class ConsoleFaceLayout extends StatelessWidget {
  const ConsoleFaceLayout({super.key, required this.ring, required this.line1, required this.line2, this.extra = const []});
  final Widget ring;
  final Widget line1;
  final Widget line2;

  /// Only for a face that needs more than two lines for a moment (the recorder's review step).
  final List<Widget> extra;

  static const double line1Height = 20;
  static const double line2Height = 26;

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Center(child: SizedBox(width: kConsoleRingSize, height: kConsoleRingSize, child: ring)),
      const SizedBox(height: 10),
      SizedBox(height: line1Height, child: Center(child: line1)),
      const SizedBox(height: 4),
      SizedBox(height: line2Height, child: Center(child: line2)),
      ...extra,
    ]);
  }
}

/// Line 1 of any face: 13 px, w600, one line, ellipsised.
Widget consoleLine1(String text, {Key? key, Color? color}) => Text(
      text,
      key: key,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: T.body.copyWith(fontWeight: FontWeight.w600, fontSize: 13, color: color),
    );

/// Line 2 of any face: 11 px, C.text2, one line.
Widget consoleLine2(String text, {Key? key}) => Text(
      text,
      key: key,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: T.monoSmall.copyWith(fontSize: 11, color: C.text2),
    );

// ---- Player ----

class PlayerFace extends StatelessWidget {
  const PlayerFace({super.key, required this.player, required this.services});
  final ConsolePlayer player;
  final ConsoleServices services;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final track = player.current;
        return ConsoleFaceLayout(
          ring: _ScrubRing(
            enabled: player.duration > Duration.zero,
            onFraction: player.seekFraction,
            child: CustomPaint(
              painter: ConsoleRingPainter(fraction: player.fraction, color: C.greenBright, dim: C.greenDim, fill: C.greenBg),
              child: Center(child: _PlayerControls(player: player)),
            ),
          ),
          line1: consoleLine1(track?.title ?? 'Nothing queued', key: const ValueKey('console-player-title')),
          line2: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
            Text('${clock(player.position)} / ${clock(player.duration)}',
                key: const ValueKey('console-player-time'), style: T.monoSmall.copyWith(fontSize: 11, color: C.text2)),
            const SizedBox(width: 10),
            _Chip(
              key: const ValueKey('console-player-speed'),
              label: '${_speedLabel(player.speed)}×',
              onTap: player.cycleSpeed,
            ),
            const SizedBox(width: 6),
            _Chip(
              key: const ValueKey('console-player-queue'),
              label: 'Queue ${player.queue.length}',
              icon: Icons.queue_music_rounded,
              onTap: () => showQueueSheet(context, services),
            ),
          ]),
          extra: [
            if (player.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(player.error!, style: T.tiny.copyWith(color: C.red)),
              ),
          ],
        );
      },
    );
  }

  static String _speedLabel(double s) => s == s.roundToDouble() ? s.toInt().toString() : s.toString();
}

class _PlayerControls extends StatelessWidget {
  const _PlayerControls({required this.player});
  final ConsolePlayer player;

  @override
  Widget build(BuildContext context) {
    final enabled = player.hasTrack;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _IconTap(
        key: const ValueKey('console-player-back'),
        icon: Icons.replay_10_rounded,
        size: 26,
        tooltip: 'Back 15 seconds',
        onTap: enabled ? player.skipBackward : null,
      ),
      _IconTap(
        key: const ValueKey('console-player-play'),
        icon: player.loading ? Icons.hourglass_empty_rounded : (player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
        size: 44,
        color: C.greenBright,
        tooltip: player.playing ? 'Pause' : 'Play',
        onTap: enabled ? player.togglePlay : null,
      ),
      _IconTap(
        key: const ValueKey('console-player-forward'),
        icon: Icons.forward_30_rounded,
        size: 26,
        tooltip: 'Forward 30 seconds',
        onTap: enabled ? player.skipForwardNow : null,
      ),
    ]);
  }
}

/// Turns a drag along the ring into a 0 to 1 fraction. A drag has to start on the
/// ring's band, so touching the middle (the buttons) or the corners never scrubs.
class _ScrubRing extends StatefulWidget {
  const _ScrubRing({required this.enabled, required this.onFraction, required this.child});
  final bool enabled;
  final Future<void> Function(double fraction) onFraction;
  final Widget child;

  @override
  State<_ScrubRing> createState() => _ScrubRingState();
}

class _ScrubRingState extends State<_ScrubRing> {
  bool _dragging = false;
  double _last = 0;

  bool _onBand(Offset p, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final d = (p - c).distance;
    final r = size.width / 2 - 10;
    return d >= r - 24 && d <= r + 14;
  }

  void _update(Offset p, Size size, {required bool start}) {
    final f = angleFraction(p, Offset(size.width / 2, size.height / 2));
    final next = start ? f : unwrapDrag(_last, f);
    _last = next;
    widget.onFraction(next);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final size = Size(c.maxWidth, c.maxHeight);
      return GestureDetector(
        key: const ValueKey('console-scrub-ring'),
        behavior: HitTestBehavior.translucent,
        onPanStart: widget.enabled
            ? (d) {
                _dragging = _onBand(d.localPosition, size);
                if (_dragging) _update(d.localPosition, size, start: true);
              }
            : null,
        onPanUpdate: widget.enabled
            ? (d) {
                if (_dragging) _update(d.localPosition, size, start: false);
              }
            : null,
        onPanEnd: (_) => _dragging = false,
        onPanCancel: () => _dragging = false,
        child: widget.child,
      );
    });
  }
}

// ---- Recorder ----

class RecorderFace extends StatefulWidget {
  const RecorderFace({super.key, required this.recorder, required this.services, this.explainMic});
  final ConsoleRecorder recorder;
  final ConsoleServices services;

  /// Shows the "why the microphone" explanation the first time; returns true to go on.
  /// Injectable so a test does not need a dialog.
  final Future<bool> Function(BuildContext context)? explainMic;

  @override
  State<RecorderFace> createState() => _RecorderFaceState();
}

class _RecorderFaceState extends State<RecorderFace> {
  final _title = TextEditingController();
  String? _seededFor;

  // BI26101806: line 2 names the last recording; read it when the face opens and after each state change.
  int? _lastAtMs;
  Duration? _savedFor;
  Duration _takeLength = Duration.zero;
  RecorderState? _seenState;

  @override
  void initState() {
    super.initState();
    _refreshLast();
  }

  Future<void> _refreshLast() async {
    try {
      final all = await widget.recorder.recordings();
      if (!mounted) return;
      setState(() {
        _lastAtMs = all.isEmpty ? null : all.first.createdAt;
      });
    } catch (_) {
      // No list to read: line 2 says "none yet".
    }
  }

  static const _explainedKey = 'console.mic_explained';

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _record() async {
    final r = widget.recorder;
    if (r.state == RecorderState.idle) {
      final store = widget.services.store;
      if (await store.read(_explainedKey) != 'yes') {
        if (!mounted) return;
        final go = await (widget.explainMic ?? _explain)(context);
        if (!go) return;
        await store.write(_explainedKey, 'yes');
      }
    }
    await r.toggleRecord();
  }

  static Future<bool> _explain(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: C.panel,
        title: const Text('Use the microphone?'),
        content: const Text(
            'The Recorder saves audio on this phone first, then sends it to your agent when you are online. '
            'Android will ask once for permission. Nothing is recorded until you press the red button.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Not now')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Continue')),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.recorder;
    return ListenableBuilder(
      listenable: r,
      builder: (context, _) {
        if (r.state == RecorderState.review && _seededFor == null) {
          _seededFor = 'take';
          _title.text = r.suggestedTitle ?? '';
        }
        if (r.state != RecorderState.review) _seededFor = null;
        final live = r.state == RecorderState.recording || r.state == RecorderState.paused;
        // A kept take reads "Saved 02:13" until the next recording starts; the list behind line 2 refreshes on each change.
        if (r.state == RecorderState.review) _takeLength = r.elapsed;
        if (_seenState != r.state) {
          if (_seenState == RecorderState.review && r.state == RecorderState.idle) _savedFor = _takeLength;
          if (r.state == RecorderState.recording) _savedFor = null;
          _seenState = r.state;
          WidgetsBinding.instance.addPostFrameCallback((_) => _refreshLast());
        }
        final lines = recorderLines(
          state: switch (r.state) {
            RecorderState.recording => RecState.recording,
            RecorderState.paused => RecState.paused,
            RecorderState.review => RecState.review,
            _ => RecState.idle,
          },
          elapsed: r.elapsed,
          savedFor: _savedFor,
          lastAtMs: _lastAtMs,
        );
        return ConsoleFaceLayout(
          ring: CustomPaint(
            painter: ConsoleRingPainter(
              fraction: r.state == RecorderState.review ? 1 : r.lap,
              color: C.red,
              dim: const Color(0xFF8B1E17),
              fill: C.redBg,
              level: r.state == RecorderState.recording ? r.level : 0,
              laps: r.laps,
            ),
            child: Center(
              child: GestureDetector(
                key: const ValueKey('console-record'),
                behavior: HitTestBehavior.opaque,
                onTap: r.state == RecorderState.review ? null : _record,
                onLongPress: live ? r.togglePause : null,
                child: Semantics(
                  button: true,
                  label: live ? 'Stop recording' : 'Record',
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: C.red, width: 2),
                      color: r.state == RecorderState.paused ? C.redBg : null,
                    ),
                    alignment: Alignment.center,
                    child: live
                        ? Container(
                            key: const ValueKey('console-stop-glyph'),
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(color: C.red, borderRadius: BorderRadius.circular(4)))
                        : Container(
                            key: const ValueKey('console-record-glyph'),
                            width: 34,
                            height: 34,
                            decoration: const BoxDecoration(color: C.red, shape: BoxShape.circle)),
                  ),
                ),
              ),
            ),
          ),
          line1: consoleLine1(lines.line1, key: const ValueKey('console-rec-clock'), color: live ? C.red : null),
          line2: consoleLine2(r.status != null && r.state == RecorderState.idle ? r.status! : lines.line2, key: const ValueKey('console-rec-status')),
          extra: [
            if (r.state == RecorderState.review) ...[
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('console-rec-title'),
                controller: _title,
                style: T.body.copyWith(fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: r.suggestedTitle ?? 'Title (optional)',
                  hintStyle: T.body2.copyWith(color: C.text3),
                  enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: C.border)),
                ),
              ),
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                TextButton(key: const ValueKey('console-rec-discard'), onPressed: r.discard, child: const Text('Discard')),
                const SizedBox(width: 8),
                FilledButton(
                  key: const ValueKey('console-rec-keep'),
                  style: FilledButton.styleFrom(backgroundColor: C.red),
                  onPressed: () => r.keep(_title.text),
                  child: const Text('Keep'),
                ),
              ]),
            ],
            if (r.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(r.error!, key: const ValueKey('console-rec-error'), style: T.tiny.copyWith(color: C.red), textAlign: TextAlign.center),
              ),
          ],
        );
      },
    );
  }
}

// ---- queue ----

Future<void> showQueueSheet(BuildContext context, ConsoleServices services) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: C.panel,
    isScrollControlled: true,
    builder: (_) => _QueueSheet(services: services),
  );
}

class _QueueSheet extends StatefulWidget {
  const _QueueSheet({required this.services});
  final ConsoleServices services;

  @override
  State<_QueueSheet> createState() => _QueueSheetState();
}

class _QueueSheetState extends State<_QueueSheet> {
  List<SavedRecording> _recordings = const [];

  @override
  void initState() {
    super.initState();
    widget.services.recorder.recordings().then((r) {
      if (mounted) setState(() => _recordings = r);
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final player = widget.services.player;
    final narrated = app.modules.narrated;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
        child: ListenableBuilder(
          listenable: player,
          builder: (context, _) => ListView(shrinkWrap: true, padding: const EdgeInsets.all(16), children: [
            Text('Queue', style: T.title),
            const SizedBox(height: 8),
            if (player.queue.isEmpty) Text('Nothing queued. Add a recording or a narration below.', style: T.body2),
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              onReorderItem: player.reorder,
              children: [
                for (var i = 0; i < player.queue.length; i++)
                  Dismissible(
                    key: ValueKey('q-${player.queue[i].id}'),
                    onDismissed: (_) => player.removeAt(i),
                    background: Container(color: C.redBg),
                    child: ListTile(
                      dense: true,
                      leading: Icon(i == player.index ? Icons.volume_up_rounded : Icons.drag_handle_rounded,
                          color: i == player.index ? C.greenBright : C.text3),
                      title: Text(player.queue[i].title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => player.playAt(i),
                      trailing: IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        tooltip: 'Remove',
                        onPressed: () => player.removeAt(i),
                      ),
                    ),
                  ),
              ],
            ),
            if (_recordings.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Recordings', style: T.label),
              for (final r in _recordings)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.mic_rounded, color: C.red, size: 18),
                  title: Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(clock(Duration(milliseconds: r.durationMs)), style: T.tiny),
                  trailing: const Icon(Icons.add_rounded),
                  onTap: () => player.addToQueue(ConsoleTrack(id: r.id, title: r.title, uri: r.path, isFile: true)),
                ),
            ],
            if (narrated.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Narrations', style: T.label),
              for (final n in narrated.take(40))
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.record_voice_over_rounded, color: C.cyan, size: 18),
                  title: Text(n.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: const Icon(Icons.add_rounded),
                  onTap: () => player.addToQueue(ConsoleTrack(
                    id: 'narration:${n.course}/${n.file}',
                    title: n.title,
                    uri: '${_base(app.api.baseUrl)}/api/learning/audio'
                        '?course=${Uri.encodeQueryComponent(n.course)}&file=${Uri.encodeQueryComponent(n.file)}',
                    headers: ConsoleServices.bearer(app.api.token),
                  )),
                ),
            ],
          ]),
        ),
      ),
    );
  }

  static String _base(String b) {
    final t = b.trim();
    return t.endsWith('/') ? t.substring(0, t.length - 1) : t;
  }
}

// ---- small pieces ----

class _Chip extends StatelessWidget {
  const _Chip({super.key, required this.label, required this.onTap, this.icon});
  final String label;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(10)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 12, color: C.text2), const SizedBox(width: 4)],
            Text(label, style: T.monoSmall.copyWith(fontSize: 10.5, color: C.text2)),
          ]),
        ),
      );
}

class _IconTap extends StatelessWidget {
  const _IconTap({super.key, required this.icon, required this.size, required this.onTap, this.color, this.tooltip});
  final IconData icon;
  final double size;
  final VoidCallback? onTap;
  final Color? color;
  final String? tooltip;

  @override
  Widget build(BuildContext context) => IconButton(
        onPressed: onTap,
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        constraints: BoxConstraints.tightFor(width: size + 8, height: size + 8),
        icon: Icon(icon, size: size, color: onTap == null ? C.text3 : (color ?? C.text)),
      );
}

/// The three small dots under the pill, one per mode.
class ConsoleModeDots extends StatelessWidget {
  const ConsoleModeDots({super.key, required this.mode, required this.color});
  final ConsoleMode mode;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (final m in ConsoleMode.values)
          Container(
            key: ValueKey('console-dot-${m.name}'),
            width: 5,
            height: 5,
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(shape: BoxShape.circle, color: m == mode ? color : C.border),
          ),
      ]);
}
