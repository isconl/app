import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../app_scope.dart';
import '../../console/audio_backends.dart' show RecordBackend;
import '../../services/debrief.dart';
import '../../theme.dart';
import 'common.dart';

/// BI26100529: the Debrief card on Today, from 18:00. One button: hold to record, or tap to start and tap to stop.
/// The timer turns amber at 60 s and the take stops at 120 s. After the transcript the proposal sheet opens; nothing
/// is written until Confirm, and Confirm shows Undo for 10 s.
class DebriefCard extends StatefulWidget {
  const DebriefCard({super.key, this.controller, this.alwaysShow = false});

  /// Tests pass their own; the app builds one on first use.
  final DebriefController? controller;

  /// Tests show it at any hour.
  final bool alwaysShow;

  /// The hour the evening rule reads. Tests pin it, so a suite run after 18:00 does not build a real recorder.
  static int Function() hourNow = () => DateTime.now().hour;

  @override
  State<DebriefCard> createState() => _DebriefCardState();
}

class _DebriefCardState extends State<DebriefCard> {
  DebriefController? _c;
  bool _ownsController = false;

  DebriefController _make() {
    final services = AppScope.of(context);
    return DebriefController(
      recorder: RecordBackend(),
      api: HubDebriefApi(services.api),
      newPath: () async {
        final dir = Directory(p.join((await getTemporaryDirectory()).path, 'debrief'));
        if (!await dir.exists()) await dir.create(recursive: true);
        return p.join(dir.path, 'debrief_${DateTime.now().millisecondsSinceEpoch}.m4a');
      },
      readBytes: (path) async => Uint8List.fromList(await File(path).readAsBytes()),
      deleteFile: (path) async {
        final f = File(path);
        if (await f.exists()) await f.delete();
      },
    );
  }

  DebriefController get c {
    final existing = _c;
    if (existing != null) return existing;
    _ownsController = widget.controller == null;
    return _c = widget.controller ?? _make();
  }

  @override
  void dispose() {
    if (_ownsController) _c?.dispose();
    super.dispose();
  }

  String _clock(Duration d) => '${d.inMinutes.toString().padLeft(1, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    // Nothing is built, and no microphone plugin touched, outside the evening.
    if (_c == null && widget.controller == null && !widget.alwaysShow && DebriefCard.hourNow() < 18) return const SizedBox.shrink();
    final ctl = c;
    return ListenableBuilder(
      listenable: ctl,
      builder: (context, _) {
        if (!widget.alwaysShow && !ctl.isEvening && ctl.phase == DebriefPhase.idle && !ctl.hasQueued) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Panel(
            key: const Key('debrief-card'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Debrief', style: T.title),
              const SizedBox(height: 4),
              Text('Say how the day went. You confirm before anything changes.', style: T.tiny),
              const SizedBox(height: 10),
              ..._body(ctl),
              if (ctl.message != null && ctl.phase != DebriefPhase.review)
                Padding(padding: const EdgeInsets.only(top: 8), child: Text(ctl.message!, key: const Key('debrief-message'), style: T.small)),
            ]),
          ),
        );
      },
    );
  }

  List<Widget> _body(DebriefController ctl) {
    switch (ctl.phase) {
      case DebriefPhase.idle:
      case DebriefPhase.failed:
      case DebriefPhase.queued:
        return [
          Row(children: [
            _RecordButton(controller: ctl),
            const SizedBox(width: 12),
            Expanded(child: Text(ctl.phase == DebriefPhase.queued ? 'Waiting for a connection' : 'Hold to record, or tap to start and tap to stop.', style: T.small)),
          ]),
          if (ctl.hasQueued) TextButton(key: const Key('debrief-retry'), onPressed: ctl.retry, child: const Text('Try again now')),
          if (ctl.phase == DebriefPhase.failed && ctl.transcript.isNotEmpty) TextButton(key: const Key('debrief-retry-propose'), onPressed: ctl.retryPropose, child: const Text('Try the proposal again')),
        ];
      case DebriefPhase.recording:
        return [
          Row(children: [
            _RecordButton(controller: ctl),
            const SizedBox(width: 12),
            Text(_clock(ctl.elapsed), key: const Key('debrief-timer'), style: T.title.copyWith(color: ctl.amber ? C.amber : C.text)),
            const SizedBox(width: 8),
            Text('of ${_clock(ctl.cap)}', style: T.tiny),
          ]),
        ];
      case DebriefPhase.transcribing:
        return [Row(children: [const MiniSpinner(size: 16), const SizedBox(width: 10), Text('Transcribing...', key: const Key('debrief-working'), style: T.small)])];
      case DebriefPhase.proposing:
        return [
          if (ctl.transcript.isNotEmpty) Text(ctl.transcript, key: const Key('debrief-transcript'), style: T.small),
          const SizedBox(height: 8),
          Row(children: [const MiniSpinner(size: 16), const SizedBox(width: 10), Text('Working out what to propose...', style: T.small)]),
        ];
      case DebriefPhase.review:
      case DebriefPhase.applying:
        return [
          if (ctl.transcript.isNotEmpty) Text(ctl.transcript, key: const Key('debrief-transcript'), style: T.small),
          const SizedBox(height: 8),
          ProposalSheet(controller: ctl),
        ];
      case DebriefPhase.applied:
        return [
          Row(children: [
            Expanded(child: Text(ctl.message ?? 'Applied.', key: const Key('debrief-applied'), style: T.small)),
            TextButton(key: const Key('debrief-undo'), onPressed: ctl.undo, child: Text('Undo (${ctl.undoLeft})')),
          ]),
        ];
    }
  }
}

class _RecordButton extends StatelessWidget {
  const _RecordButton({required this.controller});
  final DebriefController controller;

  @override
  Widget build(BuildContext context) {
    final rec = controller.phase == DebriefPhase.recording;
    return Semantics(
      button: true,
      label: rec ? 'Stop recording the debrief' : 'Record a debrief. Hold, or tap to start and tap to stop',
      child: GestureDetector(
        key: const Key('debrief-record'),
        // Hold: record while pressed. A short tap toggles instead, so the button also works without holding.
        onTap: () => rec ? controller.stop() : controller.start(),
        onLongPressStart: (_) => controller.start(),
        onLongPressEnd: (_) => controller.stop(),
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(shape: BoxShape.circle, color: rec ? C.red : C.green),
          child: Icon(rec ? Icons.stop_rounded : Icons.mic_rounded, color: Colors.white),
        ),
      ),
    );
  }
}

/// The proposal: three groups, every matched item ticked, each with the phrase it came from.
class ProposalSheet extends StatelessWidget {
  const ProposalSheet({super.key, required this.controller});
  final DebriefController controller;

  @override
  Widget build(BuildContext context) {
    final prop = controller.proposal;
    if (prop == null) return const SizedBox.shrink();
    final busy = controller.phase == DebriefPhase.applying;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (prop.items.isEmpty) Text('Nothing to propose from that.', key: const Key('proposal-empty'), style: T.small),
      for (final g in DebriefGroup.values)
        if (prop.of(g).isNotEmpty) ...[
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(g.label, style: T.label)),
          for (final i in prop.of(g)) _row(context, i),
        ],
      Row(children: [
        Checkbox(key: const Key('keep-audio'), value: controller.keepAudio, onChanged: busy ? null : (v) => controller.setKeepAudio(v ?? false)),
        Expanded(child: Text('Keep the audio', style: T.small)),
      ]),
      if (controller.message != null) Text(controller.message!, key: const Key('proposal-message'), style: T.small),
      const SizedBox(height: 6),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        TextButton(key: const Key('proposal-discard'), onPressed: busy ? null : controller.discard, child: const Text('Discard')),
        const SizedBox(width: 8),
        FilledButton(key: const Key('proposal-confirm'), onPressed: busy || prop.items.isEmpty ? null : controller.confirm, child: Text(busy ? 'Applying...' : 'Confirm')),
      ]),
    ]);
  }

  Widget _row(BuildContext context, DebriefItem i) {
    return Container(
      key: Key('item-${i.id}'),
      margin: const EdgeInsets.only(top: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Checkbox(key: Key('tick-${i.id}'), value: i.ticked && !i.needsChoice, onChanged: i.needsChoice ? null : (_) => controller.toggle(i)),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(i.unknownName ? 'Add person? ${i.title}' : i.title, style: T.body2),
            if (i.evidence.isNotEmpty) Text('"${i.evidence}"', style: T.tiny.copyWith(fontStyle: FontStyle.italic)),
            if (i.ambiguous)
              DropdownButton<String>(
                key: Key('pick-${i.id}'),
                isExpanded: true,
                hint: const Text('Which one?'),
                value: i.chosen?.id,
                items: [for (final c in i.candidates) DropdownMenuItem(value: c.id, child: Text(c.label))],
                onChanged: (v) => controller.choose(i, i.candidates.firstWhere((c) => c.id == v)),
              ),
          ]),
        ),
      ]),
    );
  }
}
