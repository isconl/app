/// BH26101801: the upload queue. Chunked, resumable, with retry and backoff, and its state written to a store after
/// every step so a restart picks the queue up where it stopped (the "background queue that survives app restarts").
///
/// The bytes come from a [UploadSource] (a picked file on the phone, a dropped file in the web console) so the queue
/// never holds a whole file in memory and tests feed it plain bytes.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'hold_data.dart';

enum UploadState { queued, running, waiting, done, failed }

/// Reads a range of the file being uploaded.
abstract class UploadSource {
  int get size;
  Future<Uint8List> read(int start, int length);
}

class BytesSource implements UploadSource {
  BytesSource(this.bytes);
  final Uint8List bytes;
  @override
  int get size => bytes.length;
  @override
  Future<Uint8List> read(int start, int length) async => Uint8List.sublistView(bytes, start, (start + length).clamp(0, bytes.length));
}

class UploadJob {
  UploadJob({required this.id, required this.destination, required this.size, this.sessionId = '', this.offset = 0, this.state = UploadState.queued, this.attempts = 0, this.error = ''});
  final String id;

  /// Full hold path the file ends up at, after conflict handling.
  final String destination;
  final int size;
  String sessionId, error;
  int offset, attempts;
  UploadState state;

  double get progress => size == 0 ? 1 : offset / size;
  String get name => destination.split('/').last;

  Map<String, dynamic> toJson() => {'id': id, 'dest': destination, 'size': size, 'session': sessionId, 'offset': offset, 'state': state.name, 'attempts': attempts, 'error': error};

  static UploadJob fromJson(Map<String, dynamic> m) => UploadJob(
        id: '${m['id']}',
        destination: '${m['dest']}',
        size: (m['size'] as num).toInt(),
        sessionId: '${m['session'] ?? ''}',
        offset: (m['offset'] as num? ?? 0).toInt(),
        // A job that was mid-flight when the app died is queued again, not running.
        state: switch ('${m['state']}') { 'done' => UploadState.done, 'failed' => UploadState.failed, _ => UploadState.queued },
        attempts: (m['attempts'] as num? ?? 0).toInt(),
        error: '${m['error'] ?? ''}',
      );
}

/// Where the queue keeps its state. The app wires this to its local database; tests use [MemoryUploadStore].
abstract class UploadStore {
  Future<String?> read();
  Future<void> write(String json);
}

class MemoryUploadStore implements UploadStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String json) async => value = json;
}

class UploadQueue extends ChangeNotifier {
  UploadQueue(this.api, this.store, {this.chunkSize = 1024 * 1024, this.maxAttempts = 6, this.backoff = const Duration(seconds: 2), Future<void> Function(Duration)? sleep})
      : _sleep = sleep ?? Future.delayed;

  final HoldApi api;
  final UploadStore store;
  final int chunkSize, maxAttempts;
  final Duration backoff;
  final Future<void> Function(Duration) _sleep;

  final List<UploadJob> jobs = [];
  final Map<String, UploadSource> _sources = {};
  bool _pumping = false;
  int _seq = 0;

  List<UploadJob> get active => [for (final j in jobs) if (j.state != UploadState.done) j];

  /// Reads the saved queue. Jobs whose source is gone (the app restarted) wait until [attach] gives it back.
  Future<void> restore() async {
    final raw = await store.read();
    if (raw == null || raw.isEmpty) return;
    jobs
      ..clear()
      ..addAll([for (final m in (jsonDecode(raw) as List)) UploadJob.fromJson((m as Map).cast<String, dynamic>())]);
    _seq = jobs.length;
    notifyListeners();
  }

  /// Gives a restored job its bytes again (the picker's persisted URI, the dropped file handle).
  void attach(String jobId, UploadSource source) {
    _sources[jobId] = source;
    _pump();
  }

  /// Queues [source] to upload into folder [dir] as [name]. If [taken] already holds the name, the file is kept as
  /// "name (2).ext" so nothing is silently overwritten.
  UploadJob add(String dir, String name, UploadSource source, {Set<String> taken = const {}}) {
    final safe = conflictFreeName(name, taken);
    final job = UploadJob(id: 'j${++_seq}-${DateTime.now().microsecondsSinceEpoch}', destination: dir.isEmpty ? safe : '$dir/$safe', size: source.size);
    jobs.add(job);
    _sources[job.id] = source;
    _save();
    notifyListeners();
    _pump();
    return job;
  }

  void retry(UploadJob j) {
    if (j.state != UploadState.failed) return;
    j.state = UploadState.queued;
    j.attempts = 0;
    j.error = '';
    _save();
    notifyListeners();
    _pump();
  }

  void clearDone() {
    jobs.removeWhere((j) => j.state == UploadState.done);
    _save();
    notifyListeners();
  }

  /// Resolves when the queue has nothing left to run (done or failed). Tests await this.
  Future<void> idle() async {
    while (_pumping) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }

  void _pump() {
    if (_pumping) return;
    _pumping = true;
    () async {
      try {
        while (true) {
          final next = jobs.where((j) => j.state == UploadState.queued && _sources.containsKey(j.id)).firstOrNull;
          if (next == null) break;
          await _run(next);
        }
      } finally {
        _pumping = false;
      }
    }();
  }

  Future<void> _run(UploadJob j) async {
    final src = _sources[j.id]!;
    j.state = UploadState.running;
    notifyListeners();
    while (true) {
      try {
        if (j.sessionId.isEmpty) {
          final s = await api.beginUpload(j.destination, j.size, _fingerprint(j));
          j.sessionId = s.id;
          j.offset = s.offset;
        }
        while (j.offset < j.size) {
          final data = await src.read(j.offset, chunkSize);
          // The server's offset is the truth: after a dropped connection it may hold more or less than we sent.
          j.offset = await api.sendChunk(j.sessionId, j.offset, data);
          j.attempts = 0;
          await _save();
          notifyListeners();
        }
        await api.finishUpload(j.sessionId);
        j.state = UploadState.done;
        j.error = '';
        break;
      } on HoldException catch (e) {
        j.attempts++;
        j.error = e.message;
        if (!e.retryable || j.attempts >= maxAttempts) {
          j.state = UploadState.failed;
          break;
        }
        j.state = UploadState.waiting;
        await _save();
        notifyListeners();
        await _sleep(backoff * (1 << (j.attempts - 1).clamp(0, 6)));
        // Ask the server where it is, in case the dropped chunk landed after all.
        j.sessionId = '';
        j.state = UploadState.running;
      }
    }
    await _save();
    notifyListeners();
  }

  // A resume key, not an integrity check: path and size identify an upload that was started before.
  String _fingerprint(UploadJob j) => '${j.destination}:${j.size}';

  Future<void> _save() => store.write(jsonEncode([for (final j in jobs) j.toJson()]));
}
