import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Thin HTTP client for the iSconl agent.
///
/// Server behaviours this client encodes (see server.js):
///  - Auth is `Authorization: Bearer <static token | session token>`.
///  - EVERY auth failure is HTTP 404, never 401. A 404 on a known-good route
///    (like /api/state) means the session died.
///  - Render free tier sleeps: first request after idle can take ~60s.
class ApiException implements Exception {
  ApiException(this.status, this.message, {this.authSuspect = false});
  final int status;
  final String message;
  final bool authSuspect;
  @override
  String toString() => 'ApiException($status): $message';
}

class OfflineException implements Exception {
  OfflineException([this.cause]);
  final Object? cause;
  @override
  String toString() => 'offline';
}

class ApiClient {
  ApiClient({required this.baseUrl, this.token = ''});

  String baseUrl;
  String token;

  /// Called when a request to a core route 404s while a token is set -
  /// the shell uses it to force re-login.
  void Function()? onAuthFailure;

  final http.Client _http = http.Client();

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
  Future<dynamic> getJson(String path, {bool cold = false}) async {
    final res = await _send('GET', path, cold: cold);
    return _decode(res, path);
  }

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

  Future<dynamic> postJson(String path, Map<String, dynamic> body,
      {bool cold = false}) async {
    final res = await _send('POST', path, body: body, cold: cold);
    return _decode(res, path);
  }

  Future<http.Response> _send(String method, String path,
      {Map<String, dynamic>? body, bool cold = false}) async {
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
    if (body != null) req.body = jsonEncode(body);
    try {
      final streamed = await _http
          .send(req)
          .timeout(cold ? _coldTimeout : _shortTimeout);
      return await http.Response.fromStream(streamed);
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
      if (suspect && (path == '/api/state' || path == '/api/notifications')) {
        onAuthFailure?.call();
      }
      throw ApiException(404, 'Not found (or session expired)',
          authSuspect: suspect);
    }
    if (res.statusCode == 429) {
      throw ApiException(429, _errorFrom(res.body, 'Locked out, retry later'));
    }
    if (res.statusCode >= 500) {
      throw ApiException(res.statusCode, 'Server error ${res.statusCode}');
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
