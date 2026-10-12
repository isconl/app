import 'dart:convert';

/// BI26101204: which modules have a retire or restore still waiting in the outbox, or refused by the server. Read from
/// the outbox rows (`id`, `path`, `body` as JSON text, `status`, `error`), newest first. Pure, so the badge rules are
/// testable without a phone.
class ModuleOp {
  const ModuleOp({required this.op, required this.failed, this.reason = ''});

  /// `retire` or `restore`.
  final String op;

  /// True when the server refused it; [reason] is the server's own words.
  final bool failed;
  final String reason;

  @override
  String toString() => '$op ${failed ? 'refused' : 'pending'}';
}

const moduleManifestPath = '/api/learning/module/manifest';

/// The newest queued, pending or refused lifecycle action for each module id. A sent action is done and not listed;
/// a dry-run preview is never queued but is ignored if one is found.
Map<String, ModuleOp> moduleOpsFromOutbox(List<Map<String, dynamic>> rows) {
  final out = <String, ModuleOp>{};
  for (final r in rows) {
    if ('${r['path']}' != moduleManifestPath) continue;
    final status = '${r['status']}';
    if (status != 'pending' && status != 'failed') continue;
    Map<String, dynamic> body;
    try {
      final raw = r['body'];
      body = raw is Map ? raw.cast<String, dynamic>() : (jsonDecode('$raw') as Map).cast<String, dynamic>();
    } catch (_) {
      continue;
    }
    if (body['dryRun'] == true) continue;
    final mods = body['modules'];
    final id = mods is List && mods.isNotEmpty ? '${mods.first}' : '';
    final op = '${body['op'] ?? ''}';
    if (id.isEmpty || (op != 'retire' && op != 'restore')) continue;
    // Rows arrive newest first, so the first one seen for a module is the one that counts.
    out.putIfAbsent(id, () => ModuleOp(op: op, failed: status == 'failed', reason: status == 'failed' ? '${r['error'] ?? ''}'.trim() : ''));
  }
  return out;
}
