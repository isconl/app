/// BI26100138: the captures the home-screen widget and the app shortcuts open.
///
/// Text goes straight into the inbox through the outbox, so it works offline. A voice note is recorded to a
/// file on the phone first; the inbox gets an entry saying it exists and how long it is. Hub has no
/// transcription route yet (it is the voice debrief's `speech.transcribe`), so the words follow once it does.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../app_scope.dart';
import '../console/audio_backends.dart';
import '../console/console_recorder.dart' show RecorderBackend;
import '../theme.dart';
import 'widgets/common.dart';

/// The longest voice note, as the debrief card caps it.
const Duration kVoiceNoteCap = Duration(seconds: 120);

/// Text capture into the inbox. Returns true when something was saved.
Future<bool> showQuickCapture(BuildContext context, AppServices services) async {
  final body = TextEditingController();
  final saved = await showFormSheet<bool>(
    context,
    title: 'Capture',
    builder: (ctx) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Field(
            label: 'Note',
            controller: body,
            maxLines: 5,
            autofocus: true,
            hint: 'Anything. The agent will annotate and file it.'),
        FilledButton(
          onPressed: () {
            if (body.text.trim().isEmpty) return;
            Navigator.pop(ctx, true);
          },
          child: const Text('Capture'),
        ),
      ],
    ),
  );
  if (saved != true) return false;
  final res = await services.mutations.addInbox(body: body.text.trim(), channel: 'mobile', sender: 'widget');
  if (context.mounted) {
    toast(context, res.ok ? (res.queued ? 'Captured, queued for sync' : 'Captured to inbox') : 'Capture failed: ${res.error}',
        error: !res.ok);
  }
  return res.ok;
}

/// Voice-note capture. Returns true when a note was saved.
Future<bool> showVoiceCapture(BuildContext context, AppServices services, {RecorderBackend Function()? backend}) async {
  final note = await showModalBottomSheet<_VoiceNote>(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.panel,
    builder: (_) => VoiceCaptureSheet(makeBackend: backend ?? RecordBackend.new),
  );
  if (note == null) return false;
  final res = await services.mutations.addInbox(
    title: 'Voice note',
    body: voiceNoteInboxText(note.length, note.recordedAt, note.fileName),
    channel: 'mobile',
    sender: 'widget-voice',
  );
  if (context.mounted) {
    toast(context, res.ok ? 'Voice note saved' : 'Saved on the phone, the inbox entry failed: ${res.error}', error: !res.ok);
  }
  return res.ok;
}

/// What the inbox entry for a voice note says.
String voiceNoteInboxText(Duration length, DateTime at, String fileName) {
  final mm = length.inMinutes, ss = (length.inSeconds % 60).toString().padLeft(2, '0');
  final hh = at.hour.toString().padLeft(2, '0'), mi = at.minute.toString().padLeft(2, '0');
  return 'Voice note, $mm:$ss, recorded at $hh:$mi. The audio is on the phone ($fileName) '
      'and is transcribed once the server takes audio.';
}

class _VoiceNote {
  const _VoiceNote(this.fileName, this.length, this.recordedAt);
  final String fileName;
  final Duration length;
  final DateTime recordedAt;
}

/// Tap to start, tap to stop (no hold needed), with the time shown and a two-minute cap.
class VoiceCaptureSheet extends StatefulWidget {
  const VoiceCaptureSheet({super.key, required this.makeBackend});
  final RecorderBackend Function() makeBackend;

  @override
  State<VoiceCaptureSheet> createState() => _VoiceCaptureSheetState();
}

class _VoiceCaptureSheetState extends State<VoiceCaptureSheet> {
  RecorderBackend? _rec;
  String? _path;
  DateTime? _started;
  Duration _length = Duration.zero;
  Timer? _tick;
  bool _done = false;
  String? _error;

  bool get _recording => _started != null && !_done;

  Future<void> _start() async {
    final rec = widget.makeBackend();
    if (!await rec.ensurePermission()) {
      await rec.dispose();
      setState(() => _error = 'The microphone is off for iSconl. Turn it on in Android settings to record.');
      return;
    }
    final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'voice-notes'));
    if (!await dir.exists()) await dir.create(recursive: true);
    final path = p.join(dir.path, 'voice-${DateTime.now().millisecondsSinceEpoch}.m4a');
    try {
      await rec.start(path);
    } catch (_) {
      await rec.dispose();
      setState(() => _error = 'Could not start recording.');
      return;
    }
    _rec = rec;
    _path = path;
    setState(() {
      _started = DateTime.now();
      _error = null;
    });
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      final len = DateTime.now().difference(_started!);
      if (len >= kVoiceNoteCap) {
        _stop();
      } else {
        setState(() => _length = len);
      }
    });
  }

  Future<void> _stop() async {
    _tick?.cancel();
    final rec = _rec;
    if (rec == null) return;
    _rec = null;
    final len = DateTime.now().difference(_started!);
    final out = await rec.stop();
    await rec.dispose();
    if (!mounted) return;
    setState(() {
      _done = true;
      _length = len > kVoiceNoteCap ? kVoiceNoteCap : len;
      if (out != null) _path = out;
      if (out == null) _error = 'Nothing was recorded.';
    });
  }

  Future<void> _discard() async {
    _tick?.cancel();
    final rec = _rec;
    _rec = null;
    if (rec != null) {
      await rec.stop();
      await rec.dispose();
    }
    final path = _path;
    if (path != null) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _tick?.cancel();
    final rec = _rec;
    if (rec != null) unawaited(rec.stop().then((_) => rec.dispose()));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final secs = _length.inSeconds;
    final amber = secs >= 60;
    final time = '${_length.inMinutes}:${(secs % 60).toString().padLeft(2, '0')}';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Voice note', style: T.title),
            const SizedBox(height: 4),
            Text('Up to two minutes, saved to your inbox.', style: T.small),
            const SizedBox(height: 22),
            Center(
              child: Text(time,
                  key: const Key('voice-time'),
                  style: T.headline.copyWith(fontSize: 32, color: amber ? C.amber : C.text)),
            ),
            const SizedBox(height: 18),
            if (!_done)
              Center(
                child: FilledButton.icon(
                  key: const Key('voice-toggle'),
                  onPressed: _recording ? _stop : _start,
                  icon: Icon(_recording ? Icons.stop_rounded : Icons.mic_rounded),
                  label: Text(_recording ? 'Stop' : 'Record'),
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: T.small.copyWith(color: C.red)),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(onPressed: _discard, child: Text(_done ? 'Discard' : 'Cancel')),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    key: const Key('voice-save'),
                    onPressed: _done && _error == null && _path != null
                        ? () => Navigator.pop(context, _VoiceNote(p.basename(_path!), _length, _started!))
                        : null,
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
