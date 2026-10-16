import 'package:flutter/foundation.dart';

import '../api/client.dart';
import '../data/db.dart';
import '../util/fmt.dart' as fmt;

/// BI26101601: the current course standard, served by hub (`GET /api/learning/standard`, `{version, ...}`),
/// kept for a day on the device so a module's tag can say "older standard" with no network. Also the
/// Settings switch that puts the same small tag on every row of a module list.
class CourseStandard extends ChangeNotifier {
  CourseStandard._();
  static final CourseStandard instance = CourseStandard._();

  @visibleForTesting
  CourseStandard.forTesting();

  static const _key = 'course.standard.v1';
  static const _listKey = 'course.standard.show_list.v1';
  static const maxAge = Duration(days: 1);

  /// The current standard as served, like `4.5.0`, or null until one has been read.
  String? current;
  bool showOnList = false;
  bool _loaded = false;

  /// Reads the cached value and the list switch, then refreshes the standard when the cache is a day old.
  Future<void> ensureLoaded(ApiClient api, AppDb db, {DateTime Function()? now}) async {
    if (_loaded) return;
    _loaded = true;
    var fresh = false;
    try {
      final snap = await db.getSnapshot(_key);
      final v = snap?.$1;
      if (v is Map && fmt.s(v['version']).isNotEmpty) {
        current = fmt.s(v['version']);
        final at = DateTime.fromMillisecondsSinceEpoch(fmt.i(v['at']));
        fresh = (now ?? DateTime.now)().difference(at) < maxAge;
      }
      final list = (await db.getSnapshot(_listKey))?.$1;
      if (list is Map) showOnList = list['on'] == true;
      notifyListeners();
    } catch (_) {
      // Nothing stored: the fetch below fills it.
    }
    if (fresh) return;
    try {
      final res = fmt.m(await api.getJson('/api/learning/standard'));
      final v = fmt.s(res['version'] ?? res['current']);
      if (v.isEmpty) return;
      current = v;
      notifyListeners();
      await db.putSnapshot(_key, {'version': v, 'at': (now ?? DateTime.now)().millisecondsSinceEpoch});
    } catch (_) {
      // Offline or unreachable: the cached value, if any, stays.
    }
  }

  /// For tests of screens that merely contain the tag: marks the standard as already read, so the
  /// widget starts no database or network work of its own.
  @visibleForTesting
  void debugPreload({String? version}) {
    _loaded = true;
    current = version;
  }

  Future<void> setShowOnList(bool on, AppDb db) async {
    showOnList = on;
    notifyListeners();
    try {
      await db.putSnapshot(_listKey, {'on': on});
    } catch (_) {}
  }
}
