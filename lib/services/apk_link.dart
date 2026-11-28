import '../api/client.dart';
import '../util/fmt.dart' as fmt;

/// BI26101514: a one-time download link for the APK, so another phone can be handed the build. Hub issues the ticket
/// (`POST /api/apk/ticket`, good for 15 minutes); it is shown once, never stored, never logged.
class ApkLink {
  const ApkLink({required this.url, required this.minutes});
  final String url;
  final int minutes;
}

Future<ApkLink> issueApkLink(ApiClient api) async {
  final m = fmt.m(await api.postJson('/api/apk/ticket', {}));
  final path = fmt.s(m['url']);
  if (path.isEmpty) throw ApiException(0, fmt.s(m['error']).isEmpty ? 'The agent issued no link.' : fmt.s(m['error']));
  final base = api.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  final ms = fmt.i(m['expiresInMs'], 15 * 60 * 1000);
  return ApkLink(url: path.startsWith('http') ? path : '$base$path', minutes: (ms / 60000).round());
}
