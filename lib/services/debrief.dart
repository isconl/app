import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../api/client.dart';
import '../console/console_recorder.dart' show RecorderBackend;

/// BI26100529: the evening voice debrief. Hold to record up to two minutes, hub transcribes it, proposes what to
/// close, who to note and what to do tomorrow, and nothing is written until Confirm. The contract follows PI26100201:
/// `speech.transcribe`, `debrief.propose` and `debrief.apply`. Those hub routes are being built in parallel, so the
/// paths below are the capability names as routes and the shapes are read tolerantly.
///
/// Audio is personal data: it is deleted from this device as soon as it has been uploaded, never logged, and a
/// debrief never applies by itself.

enum DebriefGroup { close, notes, tomorrow }

extension DebriefGroupLabel on DebriefGroup {
  String get label => switch (this) {
        DebriefGroup.close => 'Close',
        DebriefGroup.notes => 'Circle notes',
        DebriefGroup.tomorrow => 'Tomorrow',
      };
}

class DebriefItem {
  DebriefItem({
    required this.id,
    required this.group,
    required this.title,
    this.evidence = '',
    this.candidates = const [],
    this.unknownName = false,
    bool? ticked,
  })  : ticked = ticked ?? (candidates.length <= 1 && !unknownName),
        chosen = candidates.length == 1 ? candidates.first : null;

  final String id;
  final DebriefGroup group;
  final String title;

  /// The phrase from the transcript this came from.
  final String evidence;

  /// More than one person or task matched: pick one before it can be ticked.
  final List<DebriefCandidate> candidates;

  /// A name that matched nobody. Offered as "Add person?", unticked, never created without a tick.
  final bool unknownName;
  bool ticked;
  DebriefCandidate? chosen;

  bool get ambiguous => candidates.length > 1;
  bool get needsChoice => ambiguous && chosen == null;

  Map<String, dynamic> toApply() => {
        'id': id,
        'group': group.name,
        'title': title,
        if (chosen != null) 'target': chosen!.id,
        if (unknownName) 'addPerson': true,
      };
}

class DebriefCandidate {
  const DebriefCandidate(this.id, this.label);
  final String id;
  final String label;
}

class DebriefProposal {
  const DebriefProposal(this.items);
  final List<DebriefItem> items;

  List<DebriefItem> of(DebriefGroup g) => [for (final i in items) if (i.group == g) i];
  List<DebriefItem> get ticked => [for (final i in items) if (i.ticked && !i.needsChoice) i];

  static DebriefGroup? _group(String k) => switch (k) {
        'close' => DebriefGroup.close,
        'notes' => DebriefGroup.notes,
        'tomorrow' => DebriefGroup.tomorrow,
        _ => null,
      };

  /// `{close:[], notes:[], tomorrow:[]}`, each entry with a title (or task, or person), an evidence phrase and
  /// optionally `candidates` or `unknown`. Tomorrow keeps at most three.
  factory DebriefProposal.parse(Object? json) {
    final m = json is Map ? json : const {};
    final out = <DebriefItem>[];
    for (final key in const ['close', 'notes', 'tomorrow']) {
      final g = _group(key)!;
      final list = m[key] is List ? m[key] as List : const [];
      var n = 0;
      for (final e in list) {
        if (e is! Map) continue;
        if (g == DebriefGroup.tomorrow && n >= 3) break;
        n++;
        final cands = [
          for (final c in (e['candidates'] is List ? e['candidates'] as List : const []))
            if (c is Map) DebriefCandidate('${c['id'] ?? ''}', '${c['label'] ?? c['name'] ?? c['title'] ?? ''}'),
        ];
        final title = '${e['title'] ?? e['task'] ?? e['person'] ?? e['name'] ?? e['text'] ?? ''}'.trim();
        if (title.isEmpty) continue;
        out.add(DebriefItem(
          id: '${e['id'] ?? '$key-$n'}',
          group: g,
          title: (g == DebriefGroup.notes && e['note'] != null) ? '$title: ${e['note']}' : title,
          evidence: '${e['evidence'] ?? e['phrase'] ?? ''}',
          candidates: cands,
          unknownName: e['unknown'] == true,
        ));
      }
    }
    return DebriefProposal(out);
  }
}

abstract class DebriefApi {
  /// Audio in, transcript out. [keepAudio] asks the hub to keep the file; the default is to delete it.
  Future<String> transcribe(Uint8List audio, {required bool keepAudio});
  Future<DebriefProposal> propose(String transcript);

  /// Applies the ticked items in one transaction; returns an id that [undo] takes.
  Future<String> apply(List<DebriefItem> items, String transcript);
  Future<void> undo(String applyId);
}

class HubDebriefApi implements DebriefApi {
  HubDebriefApi(this.api);
  final ApiClient api;

  static Map<String, dynamic> _m(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  static Map<String, dynamic> _ok(Object? res) {
    final m = _m(res);
    if (m['success'] == false || m['ok'] == false) throw ApiException(0, '${m['error'] ?? 'Refused'}');
    return m;
  }

  @override
  Future<String> transcribe(Uint8List audio, {required bool keepAudio}) async {
    final d = _ok(await api.postJson('/api/speech/transcribe', {'audio': base64Encode(audio), 'mime': 'audio/mp4', 'keepAudio': keepAudio}, cold: true));
    final t = '${d['text'] ?? d['transcript'] ?? ''}'.trim();
    if (t.isEmpty) throw ApiException(0, 'Nothing could be heard. Try again closer to the microphone.');
    return t;
  }

  @override
  Future<DebriefProposal> propose(String transcript) async => DebriefProposal.parse(_ok(await api.postJson('/api/debrief/propose', {'transcript': transcript}, cold: true)));

  @override
  Future<String> apply(List<DebriefItem> items, String transcript) async {
    final d = _ok(await api.postJson('/api/debrief/apply', {'items': [for (final i in items) i.toApply()], 'transcript': transcript}, cold: true));
    return '${d['applyId'] ?? d['id'] ?? ''}';
  }

  @override
  Future<void> undo(String applyId) async => _ok(await api.postJson('/api/debrief/undo', {'applyId': applyId}, cold: true));
}

enum DebriefPhase { idle, recording, transcribing, proposing, review, applying, applied, queued, failed }

class DebriefController extends ChangeNotifier {
  DebriefController({
    required this.recorder,
    required this.api,
    required this.newPath,
    required this.readBytes,
    required this.deleteFile,
    DateTime Function()? now,
    this.cap = const Duration(seconds: 120),
    this.amberAt = const Duration(seconds: 60),
    this.undoWindow = const Duration(seconds: 10),
  }) : _now = now ?? DateTime.now;

  final RecorderBackend recorder;
  final DebriefApi api;
  final Future<String> Function() newPath;
  final Future<Uint8List> Function(String path) readBytes;
  final Future<void> Function(String path) deleteFile;
  final DateTime Function() _now;
  final Duration cap;
  final Duration amberAt;
  final Duration undoWindow;

  DebriefPhase phase = DebriefPhase.idle;
  Duration elapsed = Duration.zero;
  String transcript = '';
  String? message;
  DebriefProposal? proposal;

  /// The reader's choice to keep the audio on the hub. Unticked by default.
  bool keepAudio = false;

  /// Seconds left to undo, while [phase] is applied.
  int undoLeft = 0;

  String? _queuedPath;
  String? _applyId;
  Timer? _tick;
  Timer? _undoTick;
  bool _disposed = false;

  void setKeepAudio(bool v) {
    keepAudio = v;
    notifyListeners();
  }

  bool get amber => phase == DebriefPhase.recording && elapsed >= amberAt;

  /// Debrief opens from 18:00 local.
  bool get isEvening => _now().hour >= 18;

  void _set(DebriefPhase p, {String? msg}) {
    phase = p;
    message = msg;
    if (!_disposed) notifyListeners();
  }

  Future<void> start() async {
    if (phase == DebriefPhase.recording) return;
    if (!await recorder.ensurePermission()) {
      _set(DebriefPhase.failed, msg: 'The microphone is needed to record a debrief. Allow it in Settings.');
      return;
    }
    try {
      await recorder.start(await newPath());
    } catch (_) {
      _set(DebriefPhase.failed, msg: 'Could not start recording.');
      return;
    }
    elapsed = Duration.zero;
    transcript = '';
    proposal = null;
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      elapsed += const Duration(seconds: 1);
      if (elapsed >= cap) {
        stop();
      } else if (!_disposed) {
        notifyListeners();
      }
    });
    _set(DebriefPhase.recording);
  }

  Future<void> stop() async {
    if (phase != DebriefPhase.recording) return;
    _tick?.cancel();
    String? path;
    try {
      path = await recorder.stop();
    } catch (_) {}
    if (path == null) {
      _set(DebriefPhase.failed, msg: 'Nothing was recorded.');
      return;
    }
    await _process(path);
  }

  /// A recording kept for later (no connection) goes again.
  Future<void> retry() async {
    final p = _queuedPath;
    if (p == null) return;
    await _process(p);
  }

  bool get hasQueued => _queuedPath != null;

  Future<void> _process(String path) async {
    _set(DebriefPhase.transcribing);
    try {
      final bytes = await readBytes(path);
      transcript = await api.transcribe(bytes, keepAudio: keepAudio);
    } on OfflineException {
      _queuedPath = path;
      _set(DebriefPhase.queued, msg: 'No connection. Your recording is kept on this phone and goes up when you are back online. Nothing is applied by itself.');
      return;
    } catch (e) {
      _queuedPath = path;
      _set(DebriefPhase.failed, msg: _plain(e));
      return;
    }
    // Uploaded: the audio no longer needs to be on the phone.
    try {
      await deleteFile(path);
    } catch (_) {}
    _queuedPath = null;
    _set(DebriefPhase.proposing);
    try {
      proposal = await api.propose(transcript);
      _set(DebriefPhase.review);
    } catch (e) {
      _set(DebriefPhase.failed, msg: '${_plain(e)} The transcript is kept; try again.');
    }
  }

  /// Retry the proposal step after a failure with the transcript in hand.
  Future<void> retryPropose() async {
    if (transcript.isEmpty) return retry();
    _set(DebriefPhase.proposing);
    try {
      proposal = await api.propose(transcript);
      _set(DebriefPhase.review);
    } catch (e) {
      _set(DebriefPhase.failed, msg: '${_plain(e)} The transcript is kept; try again.');
    }
  }

  void toggle(DebriefItem i) {
    if (i.needsChoice) return;
    i.ticked = !i.ticked;
    notifyListeners();
  }

  void choose(DebriefItem i, DebriefCandidate c) {
    i.chosen = c;
    i.ticked = true;
    notifyListeners();
  }

  /// Applies the ticked items. Nothing was written before this.
  Future<void> confirm() async {
    final p = proposal;
    if (p == null || phase != DebriefPhase.review) return;
    final items = p.ticked;
    if (items.isEmpty) {
      _set(DebriefPhase.review, msg: 'Nothing is ticked.');
      return;
    }
    _set(DebriefPhase.applying);
    try {
      _applyId = await api.apply(items, transcript);
    } catch (e) {
      _set(DebriefPhase.review, msg: _plain(e));
      return;
    }
    undoLeft = undoWindow.inSeconds;
    _set(DebriefPhase.applied, msg: 'Applied ${items.length} item${items.length == 1 ? '' : 's'}.');
    _undoTick?.cancel();
    _undoTick = Timer.periodic(const Duration(seconds: 1), (t) {
      undoLeft--;
      if (undoLeft <= 0) {
        t.cancel();
        _applyId = null;
        _set(DebriefPhase.idle, msg: null);
      } else if (!_disposed) {
        notifyListeners();
      }
    });
  }

  Future<void> undo() async {
    final id = _applyId;
    if (id == null || phase != DebriefPhase.applied) return;
    _undoTick?.cancel();
    try {
      await api.undo(id);
      _applyId = null;
      _set(DebriefPhase.review, msg: 'Undone. Nothing is applied now.');
    } catch (e) {
      _set(DebriefPhase.applied, msg: 'Could not undo: ${_plain(e)}');
    }
  }

  /// Drops the debrief without applying anything.
  void discard() {
    proposal = null;
    transcript = '';
    _applyId = null;
    _set(DebriefPhase.idle);
  }

  static String _plain(Object e) => '$e'.replaceFirst('ApiException(0): ', '').replaceFirst('Exception: ', '');

  @override
  void dispose() {
    _disposed = true;
    _tick?.cancel();
    _undoTick?.cancel();
    recorder.dispose();
    super.dispose();
  }
}
