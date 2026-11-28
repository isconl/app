import 'package:flutter/foundation.dart';

import '../api/client.dart';
import '../data/db.dart';
import '../util/fmt.dart' as fmt;

/// BI26112307: one archetype the standard defines, as hub reads it from the standard's own §11.
class StandardArchetype {
  const StandardArchetype({required this.name, this.usedFor = '', this.explanation = '', this.exampleCourse = '', this.exampleModule = '', this.exampleTitle = ''});

  factory StandardArchetype.fromJson(Map<String, dynamic> j) {
    final ex = fmt.m(j['example']);
    return StandardArchetype(
      name: fmt.s(j['name']),
      usedFor: fmt.s(j['used_for']),
      explanation: fmt.s(j['explanation']),
      exampleCourse: fmt.s(ex['course_id']),
      exampleModule: fmt.s(ex['module_id']),
      exampleTitle: fmt.s(ex['title']),
    );
  }

  final String name;
  final String usedFor;
  final String explanation;
  final String exampleCourse;
  final String exampleModule;
  final String exampleTitle;

  bool get hasExample => exampleCourse.isNotEmpty && exampleModule.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'name': name,
        'used_for': usedFor,
        'explanation': explanation,
        'example': hasExample ? {'course_id': exampleCourse, 'module_id': exampleModule, 'title': exampleTitle} : null,
      };
}

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

  /// BI26112307: the archetypes of the current standard, in its own order. Empty until read.
  List<StandardArchetype> archetypes = const [];
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
        archetypes = _archetypesOf(v['archetypes']);
        final at = DateTime.fromMillisecondsSinceEpoch(fmt.i(v['at']));
        fresh = (now ?? DateTime.now)().difference(at) < maxAge;
      }
      final list = (await db.getSnapshot(_listKey))?.$1;
      if (list is Map) showOnList = list['on'] == true;
      notifyListeners();
    } catch (_) {
      // Nothing stored: the fetch below fills it.
    }
    if (fresh && archetypes.isNotEmpty) return;
    await refresh(api, db, now: now);
  }

  static List<StandardArchetype> _archetypesOf(dynamic raw) =>
      fmt.lm(raw).map(StandardArchetype.fromJson).where((a) => a.name.isNotEmpty).toList();

  /// Reads the standard from hub now. Returns null on success, or the reason in words; the cached value stays.
  Future<String?> refresh(ApiClient api, AppDb db, {DateTime Function()? now}) async {
    try {
      final res = fmt.m(await api.getJson('/api/learning/standard'));
      final v = fmt.s(res['version'] ?? res['current']);
      if (v.isEmpty) return fmt.s(res['error']).isEmpty ? 'The server did not say which standard is current.' : fmt.s(res['error']);
      current = v;
      archetypes = _archetypesOf(res['archetypes']);
      notifyListeners();
      await db.putSnapshot(_key, {
        'version': v,
        'archetypes': [for (final a in archetypes) a.toJson()],
        'at': (now ?? DateTime.now)().millisecondsSinceEpoch,
      });
      return null;
    } catch (e) {
      // Offline or unreachable: the cached value, if any, stays.
      return 'The server could not be reached, so this is the copy saved on the phone.';
    }
  }

  /// For tests of screens that merely contain the tag: marks the standard as already read, so the
  /// widget starts no database or network work of its own.
  @visibleForTesting
  void debugPreload({String? version, List<StandardArchetype> archetypes = const []}) {
    _loaded = true;
    current = version;
    this.archetypes = archetypes;
  }

  Future<void> setShowOnList(bool on, AppDb db) async {
    showOnList = on;
    notifyListeners();
    try {
      await db.putSnapshot(_listKey, {'on': on});
    } catch (_) {}
  }
}
