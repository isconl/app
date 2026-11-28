import 'dart:async';

import '../data/db.dart';
import '../data/modules.dart';
import '../util/fmt.dart' as fmt;
import 'course_offline.dart';

/// BI26100140: quietly download the next lessons of the courses being studied, so
/// they open instantly offline. It only runs on an unmetered connection while the
/// phone is charging, and it only ever evicts what it fetched itself.

/// The reader's choices.
class PrefetchSettings {
  const PrefetchSettings({this.enabled = true, this.capBytes = defaultCapBytes});

  /// On by default.
  final bool enabled;

  /// How much prefetched content may be kept: 200 MB.
  final int capBytes;

  static const defaultCapBytes = 200 * 1024 * 1024;

  Map<String, Object> toJson() => {'enabled': enabled, 'capBytes': capBytes};

  static PrefetchSettings fromJson(Object? v) {
    if (v is! Map) return const PrefetchSettings();
    final cap = v['capBytes'];
    return PrefetchSettings(
      enabled: v['enabled'] != false,
      capBytes: cap is num && cap > 0 ? cap.toInt() : defaultCapBytes,
    );
  }
}

/// What the prefetcher fetched itself, so eviction can tell it apart from a module
/// the reader took offline on purpose, and from one they have since opened.
class PrefetchLedger {
  PrefetchLedger([Map<String, ({DateTime at, int bytes})>? entries]) : entries = entries ?? {};

  /// module key (`course/file`) -> when it was prefetched and how big it was.
  final Map<String, ({DateTime at, int bytes})> entries;

  int get totalBytes => entries.values.fold(0, (a, e) => a + e.bytes);

  void add(String key, int bytes, DateTime at) => entries[key] = (at: at, bytes: bytes);

  /// Opening a module makes it the reader's own: it is no longer evictable.
  void markOpened(String key) => entries.remove(key);

  /// The keys to drop, oldest first, until the ledger fits under [capBytes].
  List<String> evictionOrder(int capBytes) {
    var total = totalBytes;
    if (total <= capBytes) return const [];
    final byAge = entries.entries.toList()..sort((a, b) => a.value.at.compareTo(b.value.at));
    final out = <String>[];
    for (final e in byAge) {
      if (total <= capBytes) break;
      out.add(e.key);
      total -= e.value.bytes;
    }
    return out;
  }

  Map<String, Object> toJson() => {
        for (final e in entries.entries) e.key: {'at': e.value.at.toUtc().toIso8601String(), 'bytes': e.value.bytes},
      };

  static PrefetchLedger fromJson(Object? v) {
    final l = PrefetchLedger();
    if (v is! Map) return l;
    v.forEach((k, e) {
      if (e is! Map) return;
      final at = DateTime.tryParse('${e['at']}');
      final bytes = e['bytes'];
      if (at != null && bytes is num) l.entries['$k'] = (at: at, bytes: bytes.toInt());
    });
    return l;
  }
}

/// A course is in progress when a lesson has been opened or is being learned, or
/// some lessons are done and some are not.
bool courseInProgress(Map<String, dynamic> course) {
  final lessons = fmt.lm(course['lessons']);
  if (lessons.isEmpty) return false;
  final st = [for (final l in lessons) fmt.s(l['status']).toLowerCase()];
  final done = st.where((s) => s == 'done').length;
  if (done == st.length) return false;
  return st.any((s) => s == 'opened' || s == 'learning') || done > 0;
}

/// The next [perCourse] modules of every in-progress course that are not on the
/// phone yet, in reading order.
List<({String course, String file})> planPrefetch(
  List<Map<String, dynamic>> courses,
  bool Function(String course, String file) isHere, {
  int perCourse = 2,
}) {
  int order(Map<String, dynamic> l) {
    for (final k in ['position', 'SEQ', 'seq', 'order']) {
      if (l[k] != null) return fmt.i(l[k]);
    }
    return 999999;
  }

  final out = <({String course, String file})>[];
  for (final c in courses) {
    if (!courseInProgress(c)) continue;
    final id = fmt.s(c['ID']).isEmpty ? fmt.s(c['id']) : fmt.s(c['ID']);
    if (id.isEmpty) continue;
    final lessons = fmt.lm(c['lessons'])..sort((a, b) => order(a).compareTo(order(b)));
    var taken = 0;
    for (final l in lessons) {
      if (taken >= perCourse) break;
      if (fmt.s(l['status']).toLowerCase() == 'done') continue;
      final file = fmt.s(l['file']);
      if (file.isEmpty || isHere(id, file)) continue;
      out.add((course: id, file: file));
      taken++;
    }
  }
  return out;
}

/// Where prefetch state is kept (the app database).
abstract class PrefetchStore {
  Future<PrefetchSettings> settings();
  Future<void> saveSettings(PrefetchSettings s);
  Future<PrefetchLedger> ledger();
  Future<void> saveLedger(PrefetchLedger l);
}

class DbPrefetchStore implements PrefetchStore {
  DbPrefetchStore(this._db);
  final AppDb _db;
  static const _settingsKey = 'prefetch.settings.v1';
  static const _ledgerKey = 'prefetch.ledger.v1';

  @override
  Future<PrefetchSettings> settings() async => PrefetchSettings.fromJson((await _db.getSnapshot(_settingsKey))?.$1);
  @override
  Future<void> saveSettings(PrefetchSettings s) => _db.putSnapshot(_settingsKey, s.toJson());
  @override
  Future<PrefetchLedger> ledger() async => PrefetchLedger.fromJson((await _db.getSnapshot(_ledgerKey))?.$1);
  @override
  Future<void> saveLedger(PrefetchLedger l) => _db.putSnapshot(_ledgerKey, l.toJson());
}

/// The module library as the prefetcher needs it, so a pass can be tested without a database.
abstract class PrefetchModules {
  Future<void> check();
  Future<int> refreshStale();
  bool isDownloaded(String course, String file);
  Future<bool> download(String course, String file);
  Future<String> markdownOf(String course, String file);
  Future<void> forget(String course, String file);
}

class LibraryPrefetchModules implements PrefetchModules {
  LibraryPrefetchModules(this._lib);
  final ModuleLibrary _lib;
  @override
  Future<void> check() => _lib.check();
  @override
  Future<int> refreshStale() => _lib.refreshStale();
  @override
  bool isDownloaded(String course, String file) => _lib.status(course, file).downloaded;
  @override
  Future<bool> download(String course, String file) => _lib.download(course, file);
  @override
  Future<String> markdownOf(String course, String file) => _lib.markdownOf(course, file);
  @override
  Future<void> forget(String course, String file) => _lib.forget(course, file);
}

/// A module the reader opened is theirs now: it leaves the ledger and can no longer be evicted.
Future<void> markPrefetchOpened(PrefetchStore store, String course, String file) async {
  final l = await store.ledger();
  if (l.entries.remove('$course/$file') != null) await store.saveLedger(l);
}

class PrefetchResult {
  const PrefetchResult({required this.skipped, this.fetched = 0, this.refreshed = 0, this.evicted = 0, this.images = 0});
  final String? skipped;
  final int fetched;
  final int refreshed;
  final int evicted;
  final int images;
}

/// One prefetch pass. Never blocks the UI (it is plain async work) and never runs
/// unless [onUnmeteredAndCharging] says the phone is on Wi-Fi and plugged in.
class Prefetcher {
  Prefetcher({
    required this.modules,
    required this.courses,
    required this.store,
    required this.onUnmeteredAndCharging,
    required this.baseUrl,
    required this.token,
    required this.warmImage,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final PrefetchModules modules;

  /// The learning snapshot's courses, as the reader shows them.
  final Future<List<Map<String, dynamic>>> Function() courses;
  final PrefetchStore store;
  final Future<bool> Function() onUnmeteredAndCharging;
  final String Function() baseUrl;
  final String Function() token;
  final WarmImage warmImage;
  final DateTime Function() _now;

  Future<PrefetchResult> run() async {
    final settings = await store.settings();
    if (!settings.enabled) return const PrefetchResult(skipped: 'switched off');
    if (!await onUnmeteredAndCharging()) return const PrefetchResult(skipped: 'not on Wi-Fi and charging');

    await modules.check();
    final ledger = await store.ledger();
    var fetched = 0;
    var refreshed = 0;
    var images = 0;

    // Modules already on the phone that moved on the agent: refresh them in the same pass.
    refreshed = await modules.refreshStale();

    final plan = planPrefetch(await courses(), (c, f) => modules.isDownloaded(c, f));
    for (final p in plan) {
      // Re-check the gate between modules: unplugging or leaving Wi-Fi stops the run.
      if (!await onUnmeteredAndCharging()) break;
      if (!await modules.download(p.course, p.file)) break; // offline: stop, the next pass resumes
      fetched++;
      final md = await modules.markdownOf(p.course, p.file);
      for (final a in assetFilesIn(md)) {
        if (await warmImage(assetUrl(baseUrl: baseUrl(), token: token(), course: p.course, file: a))) images++;
      }
      // The image cache does not report sizes, so the cap counts the module text.
      final bytes = md.length;
      ledger.add('${p.course}/${p.file}', bytes, _now());
    }

    // Evict only what this pass family fetched itself and the reader never opened.
    var evicted = 0;
    for (final key in ledger.evictionOrder(settings.capBytes)) {
      final i = key.indexOf('/');
      await modules.forget(key.substring(0, i), key.substring(i + 1));
      ledger.entries.remove(key);
      evicted++;
    }
    await store.saveLedger(ledger);
    return PrefetchResult(skipped: null, fetched: fetched, refreshed: refreshed, evicted: evicted, images: images);
  }
}
