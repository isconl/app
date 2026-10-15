import 'dart:convert';
import 'dart:typed_data';

import '../api/client.dart';

/// BI26100507: the console's Circle routes the app lacked, through hub. This is
/// other people's personal data: it goes only to the reader's own hub, nothing is
/// sent to anyone from here, and a drafted message is only ever copied.

/// The message written for a person, in their register.
class Reachout {
  const Reachout({
    this.urgency = '',
    this.why = '',
    this.channel = '',
    this.intent = '',
    this.body = '',
    this.generatedAt = '',
  });
  final String urgency;
  final String why;
  final String channel;

  /// The angle: what the message is meant to achieve.
  final String intent;
  final String body;
  final String generatedAt;
}

class ReachoutState {
  const ReachoutState({this.reachout, this.stale = false, this.error = ''});
  final Reachout? reachout;

  /// A stale draft is served at once and rewritten behind it.
  final bool stale;
  final String error;
}

class TagCount {
  const TagCount(this.tag, this.count);
  final String tag;
  final int count;
}

class WhoCanPerson {
  const WhoCanPerson({required this.id, required this.name, this.role = '', this.circle = '', this.why = const [], this.note = ''});
  final String id;
  final String name;
  final String role;
  final String circle;
  final List<String> why;
  final String note;
}

class WhoCan {
  const WhoCan({this.direct = const [], this.adjacent = const []});
  final List<WhoCanPerson> direct;

  /// Warm paths: not able themselves, but close to someone who is.
  final List<WhoCanPerson> adjacent;
  bool get isEmpty => direct.isEmpty && adjacent.isEmpty;
}

class GalleryPerson {
  const GalleryPerson(this.id, this.name, this.tags);
  final String id;
  final String name;
  final List<String> tags;
}

class GalleryFilters {
  const GalleryFilters({this.people = const [], this.tags = const [], this.events = const []});
  final List<GalleryPerson> people;
  final List<String> tags;
  final List<String> events;

  /// People narrowed by a tag (empty tag means everyone).
  List<GalleryPerson> peopleWith(String tag) => tag.isEmpty ? people : [for (final p in people) if (p.tags.contains(tag)) p];
}

class GalleryItem {
  const GalleryItem({required this.id, required this.name, this.path = '', this.downloadUrl = ''});
  final String id;
  final String name;
  final String path;
  final String downloadUrl;

  bool get isVideo => RegExp(r'\.(mp4|mov|m4v|avi|mkv|webm)$', caseSensitive: false).hasMatch(name);
}

class ChatUnmatched {
  const ChatUnmatched(this.speaker, this.count);
  final String speaker;
  final int count;
}

class ChatUpdated {
  const ChatUpdated({required this.id, required this.name, this.note = '', this.messages = 0});
  final String id;
  final String name;
  final String note;
  final int messages;
}

class ChatImportResult {
  const ChatImportResult({
    required this.importId,
    required this.messages,
    this.channel = '',
    this.filed = false,
    this.updated = const [],
    this.unmatched = const [],
  });
  final String importId;
  final int messages;
  final String channel;
  final bool filed;
  final List<ChatUpdated> updated;
  final List<ChatUnmatched> unmatched;
}

abstract class CircleDepthApi {
  Future<ReachoutState> reachout(String personId);

  /// "Different words" or, with an [intent], a new angle. Never sends anything.
  Future<Reachout> rewriteReachout(String personId, {String intent = ''});

  /// Logs that the reader sent a message themselves (a touch).
  Future<void> logSent(String personId, {required String channel, required String summary});

  /// The circle-wide read, or null while it is still being written.
  Future<String?> analysis();

  Future<WhoCan> whoCan(String query);

  Future<List<TagCount>> tags();
  Future<void> addTag(String personId, String tag);
  Future<void> removeTag(String personId, String tag);
  Future<void> renameTag(String from, String to);
  Future<void> mergeTags(List<String> sources, String into);
  Future<void> deleteTag(String tag);

  Future<GalleryFilters> galleryFilters();
  Future<List<GalleryItem>> galleryItems({required String scope, required String id});
  Future<void> galleryUpload({required String scope, required String id, required String kind, required String fileName, required Uint8List bytes, String contentType = ''});

  Future<ChatImportResult> importChat(String fileName, Uint8List bytes);
  Future<({String name, int messages})> addSender({
    required String importId,
    required String speaker,
    required String name,
    required String circle,
    String role = '',
    String cadence = '',
  });

  /// Creates a person's folder in the reader's own vault.
  Future<void> createFolder(String personId, String folder);
}

class HubCircleDepthApi implements CircleDepthApi {
  HubCircleDepthApi(this.api);
  final ApiClient api;

  static Map<String, dynamic> _m(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  static List<dynamic> _l(Object? v) => v is List ? v : const [];
  static String _s(Object? v) => v == null || v == '-' ? '' : '$v';
  static int _i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

  static Map<String, dynamic> _ok(Object? res) {
    final m = _m(res);
    if (m['success'] == false || (m['success'] == null && m['ok'] == false)) throw ApiException(0, _s(m['error']).isEmpty ? 'Refused' : _s(m['error']));
    return m;
  }

  static Reachout parseReachout(Object? v) {
    final r = _m(v);
    return Reachout(
      urgency: _s(r['urgency']),
      why: _s(r['why']),
      channel: _s(r['channel']),
      intent: _s(r['intent']),
      body: _s(r['body']),
      generatedAt: _s(r['generatedAt']),
    );
  }

  @override
  Future<ReachoutState> reachout(String personId) async {
    final d = _m(await api.getJson('/api/circle/reachout?id=${Uri.encodeQueryComponent(personId)}'));
    if (d['error'] != null) return ReachoutState(error: _s(d['error']));
    if (d['reachout'] == null) return const ReachoutState(error: 'No message yet. It is being written in the background.');
    return ReachoutState(reachout: parseReachout(d['reachout']), stale: d['stale'] == true);
  }

  @override
  Future<Reachout> rewriteReachout(String personId, {String intent = ''}) async {
    final d = _ok(await api.postJson('/api/circle/reachout', {'id': personId, 'intent': intent}, cold: true));
    return parseReachout(d['reachout']);
  }

  @override
  Future<void> logSent(String personId, {required String channel, required String summary}) async =>
      _ok(await api.postJson('/api/circle/touch', {'personId': personId, 'channel': channel, 'summary': summary}));

  @override
  Future<String?> analysis() async {
    final c = _s(_m(await api.getJson('/api/circle/analysis'))['content']);
    return c.isEmpty ? null : c;
  }

  static WhoCanPerson _person(Object? v) {
    final x = _m(v);
    return WhoCanPerson(
      id: _s(x['id']),
      name: _s(x['name']),
      role: _s(x['role']),
      circle: _s(x['circle']),
      why: [for (final w in _l(x['why'])) '$w'],
      note: _s(x['note']),
    );
  }

  @override
  Future<WhoCan> whoCan(String query) async {
    final d = _m(await api.getJson('/api/circle/whocan?q=${Uri.encodeQueryComponent(query)}'));
    return WhoCan(direct: [for (final x in _l(d['direct'])) _person(x)], adjacent: [for (final x in _l(d['adjacent'])) _person(x)]);
  }

  @override
  Future<List<TagCount>> tags() async => [
        for (final t in _l(_m(await api.getJson('/api/circle/tags'))['tags']))
          if (t is Map) TagCount(_s(t['tag']), _i(t['count'])),
      ];

  @override
  Future<void> addTag(String personId, String tag) async => _ok(await api.postJson('/api/circle/tags/add', {'personId': personId, 'tag': tag}));
  @override
  Future<void> removeTag(String personId, String tag) async => _ok(await api.postJson('/api/circle/tags/remove', {'personId': personId, 'tag': tag}));
  @override
  Future<void> renameTag(String from, String to) async => _ok(await api.postJson('/api/circle/tags/rename', {'from': from, 'to': to}));
  @override
  Future<void> mergeTags(List<String> sources, String into) async => _ok(await api.postJson('/api/circle/tags/merge', {'sources': sources, 'into': into}));
  @override
  Future<void> deleteTag(String tag) async => _ok(await api.postJson('/api/circle/tags/delete', {'tag': tag}));

  @override
  Future<GalleryFilters> galleryFilters() async {
    final d = _m(await api.getJson('/api/circle/gallery/filters'));
    return GalleryFilters(
      people: [
        for (final p in _l(d['people']))
          if (p is Map) GalleryPerson(_s(p['id']), _s(p['name']), [for (final t in _l(p['tags'])) '$t']),
      ],
      tags: [for (final t in _l(d['tags'])) '$t'],
      events: [for (final e in _l(d['events'])) '$e'],
    );
  }

  @override
  Future<List<GalleryItem>> galleryItems({required String scope, required String id}) async {
    final d = _m(await api.getJson('/api/circle/gallery/items?scope=$scope&id=${Uri.encodeQueryComponent(id)}'));
    if (d['error'] != null && d['items'] == null) throw ApiException(0, _s(d['error']));
    return [
      for (final i in _l(d['items']))
        if (i is Map) GalleryItem(id: _s(i['id']), name: _s(i['name']), path: _s(i['path']), downloadUrl: _s(i['downloadUrl'])),
    ];
  }

  @override
  Future<void> galleryUpload({
    required String scope,
    required String id,
    required String kind,
    required String fileName,
    required Uint8List bytes,
    String contentType = '',
  }) async =>
      _ok(await api.postJson(
        '/api/circle/gallery/upload',
        {'scope': scope, 'id': id, 'kind': kind, 'fileName': fileName, 'contentBase64': base64Encode(bytes), 'contentType': contentType},
        cold: true,
      ));

  @override
  Future<ChatImportResult> importChat(String fileName, Uint8List bytes) async {
    final d = _ok(await api.postJson('/api/circle/import-chat', {'fileName': fileName, 'content': base64Encode(bytes)}, cold: true));
    return ChatImportResult(
      importId: _s(d['importId']),
      messages: _i(d['messages']),
      channel: _s(d['channel']),
      filed: d['filed'] == true,
      updated: [
        for (final u in _l(d['updated']))
          if (u is Map) ChatUpdated(id: _s(u['id']), name: _s(u['name']), note: _s(u['note']), messages: _i(u['messages'])),
      ],
      unmatched: [
        for (final u in _l(d['unmatched']))
          if (u is Map) ChatUnmatched(_s(u['speaker']), _i(u['count'])),
      ],
    );
  }

  @override
  Future<({String name, int messages})> addSender({
    required String importId,
    required String speaker,
    required String name,
    required String circle,
    String role = '',
    String cadence = '',
  }) async {
    final d = _ok(await api.postJson('/api/circle/import-chat/add-sender', {
      'importId': importId,
      'speaker': speaker,
      'name': name,
      'circle': circle,
      'role': role,
      'cadence': cadence,
    }));
    return (name: _s(d['name']).isEmpty ? speaker : _s(d['name']), messages: _i(d['messages']));
  }

  @override
  Future<void> createFolder(String personId, String folder) async => _ok(await api.postJson('/api/circle/folder', {'personId': personId, 'folder': folder}));
}

/// The folder the console creates for a person: `Sconl/Circle/<Ring>/<year>-<slug>`, with
/// social ring people under `Friends`. Pure, so it can be shown before it is made.
String circleFolderFor({required String name, required String circle, String met = ''}) {
  final ring = circle.isEmpty ? 'social' : circle.toLowerCase();
  final cap = '${ring[0].toUpperCase()}${ring.substring(1)}';
  final year = (met.length >= 4 && met != '-') ? met.substring(0, 4) : '2026';
  final slug = name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
      .trim()
      .replaceAll(RegExp(r'[\s_]+'), '-');
  final folder = '$year-${slug.isEmpty ? 'contact' : slug}';
  return ring == 'social' ? 'Sconl/Circle/Social/Friends/$folder' : 'Sconl/Circle/$cap/$folder';
}

/// The summary line logged when a drafted message was sent: what was actually sent, so the
/// next draft reads it.
String sentSummary(String body) {
  final first = body.split('\n').map((l) => l.trim()).firstWhere((l) => l.isNotEmpty, orElse: () => 'the drafted message');
  return 'Sent: ${first.length > 90 ? first.substring(0, 90) : first}';
}
