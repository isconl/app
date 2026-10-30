import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../util/server_clock.dart';

/// Thin HTTP client for the iSconl agent.
///
/// Server behaviours this client encodes (see server.js):
///  - Auth is `Authorization: Bearer <static token | session token>`.
///  - EVERY auth failure is HTTP 404, never 401. A 404 on a known-good route
///    (like /api/state) means the session died.
///  - The first request after a long idle can be slow (cold start), so cold
///    calls get a longer timeout.
///
/// The contract this client implements is written down in canon:
/// work/_arc/iSconl/20261005_canon_client_api_contract_isconl_v1_0_0.md
/// (hub as the one entry point, auth order, /api/nav, errors, offline outbox).
/// A change to how this client talks to hub changes that document first.
class ApiException implements Exception {
  ApiException(this.status, this.message, {this.authSuspect = false, this.answered = false});
  final int status;
  final String message;
  final bool authSuspect;
  /// BI26103095: hub itself answered (a JSON error body), so the server is reachable even though this one request
  /// failed, for instance an engine that is not running on the light fleet. Only a missing answer means unreachable.
  final bool answered;
  @override
  String toString() => 'ApiException($status): $message';
}

class OfflineException implements Exception {
  OfflineException([this.cause]);
  final Object? cause;
  @override
  String toString() => 'offline';
}

/// Where the client keeps the last good answer to each GET, so a screen reads
/// what it last saw when the server cannot be reached (Sconl, 27 Oct 2026: once
/// pulled, data stays readable on the phone until the server sends an update).
abstract class ResponseCache {
  Future<void> put(String path, dynamic value);
  Future<(dynamic, DateTime)?> get(String path);
}

class ApiClient {
  ApiClient({required this.baseUrl, this.token = '', http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  String baseUrl;
  String token;

  /// Called when a request to a core route 404s while a token is set -
  /// the shell uses it to force re-login.
  void Function()? onAuthFailure;

  /// The phone's copy of every GET answer. Null (tests, the background
  /// prefetch worker) means no fallback: errors surface exactly as before.
  ResponseCache? cache;

  /// True from the first GET that could not reach the server until the next one
  /// that did. The phone can be online while the server is not (the tunnel is
  /// down, the VM is off), so this is not the same as the device's connectivity.
  bool serverUnreachable = false;

  /// When the copy most recently served in place of the server was fetched.
  DateTime? servedFromCacheAt;

  /// Called whenever [serverUnreachable] changes, so the shell can say so.
  void Function()? onReachabilityChanged;

  void _reachable(bool ok) {
    if (serverUnreachable == !ok) return;
    serverUnreachable = !ok;
    if (ok) servedFromCacheAt = null;
    onReachabilityChanged?.call();
  }

  /// A failure that means "the server did not answer", as opposed to "the
  /// server answered no". Timeouts, no network, and 5xx (Cloudflare's 502/530
  /// when the tunnel has no connector, hub's 502 when an engine is down) all
  /// count. A 4xx is an answer and is never papered over with a stored copy.
  static bool isUnreachable(Object e) =>
      e is OfflineException ||
      (e is ApiException &&
          ((e.status >= 500 && !e.answered) ||
              (e.status == 0 && e.message == 'Request timed out') ||
              (e.status == 400 && e.message.toLowerCase().contains('refused to parse'))));

  final http.Client _http;

  static const _shortTimeout = Duration(seconds: 20);
  static const _coldTimeout = Duration(seconds: 75);

  Uri _uri(String path) {
    var base = baseUrl.trim();
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);
    return Uri.parse('$base$path');
  }

  Map<String, String> _headers({bool json = true}) => {
        if (json) 'Content-Type': 'application/json',
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

  /// GET returning decoded JSON (object or array).
  ///
  /// Every good answer is stored on the phone; when the server cannot be
  /// reached, the stored answer comes back instead of the error. Stored data is
  /// only ever replaced by a later good answer, never cleared by a failure.
  /// [stored] false skips both, for callers that keep their own copy
  /// ([Snapshot] does, with its own fetched-at time).
  Future<dynamic> getJson(String path, {bool cold = false, bool stored = true}) async {
    final c = stored ? cache : null;
    try {
      final res = await _send('GET', path, cold: cold);
      final value = _decode(res, path);
      _reachable(true);
      if (c != null) {
        try {
          await c.put(path, value);
        } catch (_) {
          // A full or locked database must not turn a good answer into an error.
        }
      }
      return value;
    } catch (e) {
      final isLessonParseFailure = path.contains('/api/learning/lesson') &&
          e is ApiException &&
          (e.status == 400 || e.message.toLowerCase().contains('refused to parse'));
      if ((!isUnreachable(e) && !isLessonParseFailure) || baseUrl.trim().isEmpty) rethrow;
      _reachable(false);
      (dynamic, DateTime)? hit;
      if (c != null) {
        try {
          hit = await c.get(path);
        } catch (_) {}
      }
      if (hit == null) rethrow;
      servedFromCacheAt = hit.$2;
      onReachabilityChanged?.call();
      return hit.$1;
    }
  }

  /// GET /api/signals returning the signals payload.
  Future<dynamic> signals({bool cold = false}) =>
      getJson('/api/signals', cold: cold);

  /// GET returning raw bytes, for routes that answer with a file rather than
  /// JSON - the PDF export, for one. `_decode` cannot be used here: it parses
  /// every body as JSON and would reject a perfectly good PDF as a bad
  /// response. The error path still reads a JSON `error` when the server sends
  /// one, so a failure is still a sentence rather than a status code.
  Future<({List<int> bytes, String filename})> getBytes(String path,
      {bool cold = true}) async {
    final res = await _send('GET', path, cold: cold);
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode,
          _errorFrom(res.body, 'Could not fetch the file'),
          authSuspect: res.statusCode == 404 && token.isNotEmpty);
    }
    // The server names the file, and the name carries the date and the course.
    var name = '';
    final cd = res.headers['content-disposition'] ?? '';
    final m = RegExp(r'filename="([^"]+)"').firstMatch(cd);
    if (m != null) name = m.group(1)!;
    return (bytes: res.bodyBytes, filename: name);
  }

  /// GET that revalidates with an ETag. A 304 comes back as `status: 304` with an
  /// empty body, so a caller can tell "nothing changed" from a failure. Any other
  /// non-2xx status throws, as the other getters do.
  Future<({int status, String body, String? etag})> getConditional(String path,
      {String? etag, bool cold = false}) async {
    final res = await _send('GET', path,
        cold: cold, extraHeaders: {if (etag != null && etag.isNotEmpty) 'If-None-Match': etag});
    if (res.statusCode == 304) return (status: 304, body: '', etag: etag);
    _decode(res, path); // throws the usual ApiException for 404/429/5xx and error bodies
    return (status: res.statusCode, body: res.body, etag: res.headers['etag']);
  }

  Future<dynamic> postJson(String path, Map<String, dynamic> body,
      {bool cold = false}) async {
    final res = await _send('POST', path, body: body, cold: cold);
    return _decode(res, path);
  }

  Future<http.Response> _send(String method, String path,
      {Map<String, dynamic>? body, bool cold = false, Map<String, String>? extraHeaders}) async {
    // No base URL is a CONFIGURATION state, not a network failure. Without this
    // guard an empty base produces a relative URI, http throws a ClientException,
    // and the app reports "offline" - which sends him looking at his signal
    // instead of at the empty field that is actually the problem. There is no
    // default server any more, so this path is reachable on every fresh install.
    if (baseUrl.trim().isEmpty) {
      throw ApiException(0,
          'No agent address set. Open Settings and enter the address of your iSconl agent.');
    }
    final req = http.Request(method, _uri(path));
    req.headers.addAll(_headers());
    if (extraHeaders != null) req.headers.addAll(extraHeaders);
    if (body != null) req.body = jsonEncode(body);
    try {
      final sent = DateTime.now();
      final streamed = await _http
          .send(req)
          .timeout(cold ? _coldTimeout : _shortTimeout);
      final res = await http.Response.fromStream(streamed);
      // BI26101801: the Date header on a regular response tells the Hub clock whether the phone has drifted.
      ServerClock.instance.observe(sent, DateTime.now(), res.headers['date']);
      return res;
    } on TimeoutException {
      throw ApiException(0, 'Request timed out');
    } on http.ClientException catch (e) {
      throw OfflineException(e);
    }
  }

  dynamic _decode(http.Response res, String path) {
    if (res.statusCode == 404) {
      // The server 404s on bad auth. Distinguish "session dead" (core route)
      // from a genuinely unknown path by the route prefix.
      final suspect = token.isNotEmpty && path.startsWith('/api');
      // BI26103095: only /api/state, which hub itself owns, can prove a dead session. /api/notifications belongs to an
      // engine, and on a fleet without it a 404 signed Sconl out on every open (30 Oct 2026).
      if (suspect && path == '/api/state') {
        onAuthFailure?.call();
      }
      throw ApiException(404, 'Not found (or session expired)',
          authSuspect: suspect);
    }
    if (res.statusCode == 429) {
      throw ApiException(429, _errorFrom(res.body, 'Locked out, retry later'));
    }
    if (res.statusCode >= 500) {
      // BI26103095: a JSON body is hub's own answer (an engine down or not deployed): the server is there. Cloudflare's
      // 502/530 pages and a dead tunnel are not JSON, so they still read as unreachable.
      final hubAnswered = (() {
        try {
          return jsonDecode(res.body) is Map;
        } catch (_) {
          return false;
        }
      })();
      throw ApiException(res.statusCode, hubAnswered ? _errorFrom(res.body, 'Server error ${res.statusCode}') : 'Server error ${res.statusCode}',
          answered: hubAnswered);
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(res.body);
    } catch (_) {
      throw ApiException(res.statusCode, 'Bad response from server');
    }
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, _errorFrom(res.body, 'Request failed'));
    }
    return decoded;
  }

  String _errorFrom(String body, String fallback) {
    try {
      final map = jsonDecode(body);
      if (map is Map && map['error'] is String) return map['error'] as String;
    } catch (_) {}
    return fallback;
  }

  /// Health probe - unauthenticated; used to wake the Render instance.
  Future<Map<String, dynamic>?> health({bool cold = true}) async {
    try {
      final res = await _send('GET', '/health', cold: cold);
      final decoded = jsonDecode(res.body);
      return decoded is Map ? decoded.cast<String, dynamic>() : null;
    } catch (_) {
      return null;
    }
  }

  /// POST /api/chat/stream - hand-rolled SSE over a streamed request.
  /// Frames are `event: <name>\ndata: <json>\n\n`.
  /// Cloud providers deliver the reply in one `done` frame (no `token` events);
  /// only the local model streams tokens.
  Stream<(String event, Map<String, dynamic> data)> chatStream(
      String message) async* {
    final req = http.Request('POST', _uri('/api/chat/stream'));
    req.headers.addAll(_headers());
    req.headers['Accept'] = 'text/event-stream';
    req.body = jsonEncode({'message': message});

    http.StreamedResponse streamed;
    try {
      streamed = await _http.send(req).timeout(_coldTimeout);
    } on http.ClientException catch (e) {
      throw OfflineException(e);
    }
    if (streamed.statusCode == 404) {
      throw ApiException(404, 'Session expired', authSuspect: true);
    }
    if (streamed.statusCode >= 400) {
      throw ApiException(streamed.statusCode, 'Chat unavailable');
    }

    var buffer = '';
    await for (final chunk in streamed.stream.transform(utf8.decoder)) {
      buffer += chunk;
      while (true) {
        final sep = buffer.indexOf('\n\n');
        if (sep < 0) break;
        final frame = buffer.substring(0, sep);
        buffer = buffer.substring(sep + 2);
        String event = 'message';
        final dataLines = <String>[];
        for (final line in frame.split('\n')) {
          if (line.startsWith('event:')) event = line.substring(6).trim();
          if (line.startsWith('data:')) dataLines.add(line.substring(5).trim());
        }
        if (dataLines.isEmpty) continue;
        Map<String, dynamic> data;
        try {
          final decoded = jsonDecode(dataLines.join('\n'));
          data = decoded is Map ? decoded.cast<String, dynamic>() : {};
        } catch (_) {
          data = {};
        }
        yield (event, data);
      }
    }
  }

  void close() => _http.close();
}
