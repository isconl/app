import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../api/client.dart';

/// One module's narration on the phone.
class DownloadedAudio {
  const DownloadedAudio({required this.course, required this.file, required this.rev, required this.path, required this.bytes});
  final String course;
  final String file;
  final String rev;
  final String path;
  final int bytes;
}

class AudioDownloadException implements Exception {
  AudioDownloadException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Narration files kept in app storage so a course plays with no signal.
///
/// A file is named for the module and its revision, so a changed module (a new
/// `rev` in the manifest) never plays an old recording: the lookup simply misses
/// and the stream, then the device voice, take over. A download writes to a
/// `.part` file and resumes from its length with a Range header, so a dropped
/// connection costs only what was not yet received.
class AudioDownloads extends ChangeNotifier {
  AudioDownloads({
    required this.root,
    required this.apiProvider,
    http.Client? client,
    this.isOnWifi,
  }) : _http = client ?? http.Client();

  /// `<app documents>/narration`.
  final Directory root;
  final ApiClient Function() apiProvider;
  final http.Client _http;

  /// Null means "assume yes" (tests, desktop). On the phone this asks
  /// connectivity_plus.
  final Future<bool> Function()? isOnWifi;

  /// Wi-Fi only by default; the reader can allow mobile data.
  bool wifiOnly = true;

  /// module key -> progress 0..1 while a download runs.
  final Map<String, double> progress = {};

  static String keyOf(String course, String file) => '$course/$file';

  static String _safe(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  Directory _courseDir(String course) => Directory('${root.path}${Platform.pathSeparator}${_safe(course)}');

  File _fileFor(String course, String file, String rev) =>
      File('${_courseDir(course).path}${Platform.pathSeparator}${_safe(file)}__${_safe(rev)}.audio');

  /// The local copy for exactly this revision, or null.
  Future<DownloadedAudio?> local(String course, String file, String rev) async {
    if (rev.isEmpty) return null;
    final f = _fileFor(course, file, rev);
    if (!await f.exists()) return null;
    final n = await f.length();
    if (n == 0) return null;
    return DownloadedAudio(course: course, file: file, rev: rev, path: f.path, bytes: n);
  }

  bool isDownloading(String course, String file) => progress.containsKey(keyOf(course, file));

  /// Downloads one module's narration. Returns the local copy. Throws
  /// [AudioDownloadException] with a sentence the UI can show.
  Future<DownloadedAudio> download({
    required String course,
    required String file,
    required String rev,
    bool force = false,
  }) async {
    final k = keyOf(course, file);
    if (progress.containsKey(k)) throw AudioDownloadException('That module is already downloading.');
    final have = await local(course, file, rev);
    if (have != null) return have;
    if (wifiOnly && !force && isOnWifi != null && !await isOnWifi!()) {
      throw AudioDownloadException('Waiting for Wi-Fi. Allow mobile data in Settings to download now.');
    }
    final api = apiProvider();
    var base = api.baseUrl.trim();
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);
    final uri = Uri.parse('$base/api/learning/audio'
        '?course=${Uri.encodeQueryComponent(course)}&file=${Uri.encodeQueryComponent(file)}');

    final dir = _courseDir(course);
    await dir.create(recursive: true);
    final target = _fileFor(course, file, rev);
    final part = File('${target.path}.part');
    var have0 = await part.exists() ? await part.length() : 0;

    progress[k] = 0;
    notifyListeners();
    try {
      final req = http.Request('GET', uri);
      if (api.token.isNotEmpty) req.headers['Authorization'] = 'Bearer ${api.token}';
      if (have0 > 0) req.headers['Range'] = 'bytes=$have0-';
      final res = await _http.send(req).timeout(const Duration(seconds: 60));
      if (res.statusCode == 404 || res.statusCode == 403) {
        throw AudioDownloadException('That narration is not available from the agent yet.');
      }
      if (res.statusCode != 200 && res.statusCode != 206) {
        throw AudioDownloadException('The agent answered ${res.statusCode}. Try again later.');
      }
      // A server that ignores Range sends the whole file with 200: start over.
      final resumed = res.statusCode == 206 && have0 > 0;
      if (!resumed && have0 > 0) {
        await part.writeAsBytes(const [], flush: true);
        have0 = 0;
      }
      final total = (res.contentLength ?? 0) + (resumed ? have0 : 0);
      final sink = part.openWrite(mode: resumed ? FileMode.append : FileMode.write);
      var got = resumed ? have0 : 0;
      try {
        await for (final chunk in res.stream) {
          sink.add(chunk);
          got += chunk.length;
          if (total > 0) {
            progress[k] = (got / total).clamp(0.0, 1.0);
            notifyListeners();
          }
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (await part.length() == 0) throw AudioDownloadException('The agent sent an empty file.');
      if (await target.exists()) await target.delete();
      await part.rename(target.path);
      // Older revisions of the same module are now dead weight.
      await _prune(course, file, rev);
      return (await local(course, file, rev))!;
    } on SocketException {
      throw AudioDownloadException('No connection. The download will carry on from where it stopped.');
    } on TimeoutException {
      throw AudioDownloadException('The agent did not answer in time. Try again.');
    } on http.ClientException {
      throw AudioDownloadException('No connection. The download will carry on from where it stopped.');
    } finally {
      progress.remove(k);
      notifyListeners();
    }
  }

  Future<void> _prune(String course, String file, String keepRev) async {
    final dir = _courseDir(course);
    if (!await dir.exists()) return;
    final prefix = '${_safe(file)}__';
    final keep = '${_safe(file)}__${_safe(keepRev)}.audio';
    await for (final e in dir.list()) {
      final name = e.uri.pathSegments.last;
      if (e is File && name.startsWith(prefix) && name.endsWith('.audio') && name != keep) {
        try {
          await e.delete();
        } catch (_) {}
      }
    }
  }

  /// Downloads every module in [modules] one after another, skipping what is
  /// already on the phone. A failure stops the run and says why; what was done
  /// stays.
  Future<int> downloadCourse(String course, List<({String file, String rev})> modules, {bool force = false}) async {
    var done = 0;
    for (final m in modules) {
      await download(course: course, file: m.file, rev: m.rev, force: force);
      done++;
    }
    return done;
  }

  /// Bytes of narration kept for [course].
  Future<int> bytesUsed(String course) async {
    final dir = _courseDir(course);
    if (!await dir.exists()) return 0;
    var n = 0;
    await for (final e in dir.list()) {
      if (e is File && e.path.endsWith('.audio')) n += await e.length();
    }
    return n;
  }

  /// Every course with narration on the phone and what it takes up.
  Future<Map<String, int>> usage() async {
    final out = <String, int>{};
    if (!await root.exists()) return out;
    await for (final e in root.list()) {
      if (e is Directory) {
        final course = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
        final n = await bytesUsed(course);
        if (n > 0) out[course] = n;
      }
    }
    return out;
  }

  Future<void> deleteCourse(String course) async {
    final dir = _courseDir(course);
    if (await dir.exists()) await dir.delete(recursive: true);
    notifyListeners();
  }

  /// Everything: used on sign-out, so downloaded narration never outlives the session.
  Future<void> deleteAll() async {
    if (await root.exists()) await root.delete(recursive: true);
    progress.clear();
    notifyListeners();
  }

  Future<void> deleteModule(String course, String file, String rev) async {
    final f = _fileFor(course, file, rev);
    if (await f.exists()) await f.delete();
    notifyListeners();
  }
}

/// "12.4 MB" and friends, for the storage manager.
String prettyBytes(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
  if (b < 1024 * 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
