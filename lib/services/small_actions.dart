import '../api/client.dart';

/// BI26100512 (first slice): the console's small actions on journal entries, ideas and OneDrive files. Every one
/// needs the live hub (none is queued), a delete is always asked about first by the caller, and a OneDrive delete goes
/// to the recycle bin on the hub's side, never a hard delete.
abstract class SmallActionsApi {
  Future<void> journalUpdate(String id, String body);
  Future<void> journalDelete(String id);

  /// The model's read of one entry.
  Future<String> journalReflect(String id);

  /// The model's read across the journal: text plus the stats line.
  Future<({String review, String stats})> journalReview();
  Future<void> ideaDelete(String id);
  Future<String> ideaRefine(String id);
  Future<String> ideasReview();

  Future<void> mkdir(String parentPath, String name);

  /// Renames an item in place.
  Future<void> rename(String itemId, String newName);

  /// Moves an item to [toPath] ('' is the OneDrive root).
  Future<void> move(String itemId, String toPath);
  Future<void> deleteItem(String itemId);

  /// Uploads a text file. The hub's route takes text, so binary files are refused by the caller.
  Future<void> uploadText(String folderPath, String fileName, String content);
  Future<({String filename, List<int> bytes})> download(String itemId, String name);
}

class HubSmallActionsApi implements SmallActionsApi {
  HubSmallActionsApi(this.api);
  final ApiClient api;

  static Map<String, dynamic> _m(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  static String _s(Object? v) => v == null || v == '-' ? '' : '$v';

  static Map<String, dynamic> _ok(Object? res) {
    final m = _m(res);
    if (m['success'] == false || (m['success'] == null && m['error'] != null)) {
      throw ApiException(0, _s(m['error']).isEmpty ? 'Refused' : _s(m['error']));
    }
    return m;
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async => _ok(await api.postJson(path, body, cold: true));

  @override
  Future<void> journalUpdate(String id, String body) async => _post('/api/journal/update', {'id': id, 'body': body});

  @override
  Future<void> journalDelete(String id) async => _post('/api/journal/delete', {'id': id});

  @override
  Future<String> journalReflect(String id) async {
    final d = await _post('/api/journal/reflect', {'id': id});
    final note = _s(d['note']);
    if (note.isEmpty) throw ApiException(0, 'No reflection available yet.');
    return note;
  }

  @override
  Future<({String review, String stats})> journalReview() async {
    final d = await _post('/api/journal/review', {});
    final st = _m(d['stats']);
    return (review: _s(d['review']), stats: '${st['entries'] ?? 0} entries, mood ${st['mood'] ?? 'n/a'}, energy ${st['energy'] ?? 'n/a'}');
  }

  @override
  Future<void> ideaDelete(String id) async => _post('/api/ideas/delete', {'id': id});

  @override
  Future<String> ideaRefine(String id) async {
    final d = await _post('/api/ideas/refine', {'id': id});
    final note = _s(d['note']);
    if (note.isEmpty) throw ApiException(0, 'Nothing came back to sharpen it with.');
    return note;
  }

  @override
  Future<String> ideasReview() async => _s((await _post('/api/ideas/review', {}))['review']);

  @override
  Future<void> mkdir(String parentPath, String name) async => _post('/api/onedrive/mkdir', {'parentPath': parentPath == 'root' ? '' : parentPath, 'folderName': name});

  /// A name that OneDrive refuses; the same rule as the console's.
  static bool badName(String name) => name.trim().isEmpty || RegExp(r'[\\/:*?"<>|]').hasMatch(name);

  @override
  Future<void> rename(String itemId, String newName) async {
    if (badName(newName)) throw ApiException(0, 'A name cannot contain \\ / : * ? " < > |');
    await _post('/api/onedrive/move', {'itemId': itemId, 'newName': newName.trim()});
  }

  @override
  Future<void> move(String itemId, String toPath) async {
    final clean = toPath.trim().replaceAll(RegExp(r'^/+|/+$'), '');
    await _post('/api/onedrive/move', {'itemId': itemId, 'toPath': clean.toLowerCase() == 'root' ? '' : clean});
  }

  @override
  Future<void> deleteItem(String itemId) async => _post('/api/onedrive/delete', {'itemId': itemId});

  @override
  Future<void> uploadText(String folderPath, String fileName, String content) async =>
      _post('/api/onedrive/upload', {'folderPath': folderPath == 'root' ? '' : folderPath, 'fileName': fileName, 'content': content});

  @override
  Future<({String filename, List<int> bytes})> download(String itemId, String name) =>
      api.getBytes('/api/onedrive/download?id=${Uri.encodeQueryComponent(itemId)}&name=${Uri.encodeQueryComponent(name)}');
}
