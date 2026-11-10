/// The decision half of Wi-Fi prefetch (BI26100140): which modules to download, refresh and
/// evict in one pass. Pure, so every rule is testable without a phone. The background task
/// (`workmanager`, every six hours, unmetered and charging) gathers the inputs from
/// `ModuleLibrary` and the connectivity plugin, calls [planPrefetch], then runs the same
/// download path "Take offline" uses.
library;

/// Where a downloaded copy came from. Only [prefetch] copies may ever be evicted by policy.
enum CopySource { manual, prefetch }

class PrefetchModule {
  const PrefetchModule({
    required this.file,
    required this.bytes,
    this.downloaded = false,
    this.stale = false,
    this.source,
    this.opened = false,
    this.downloadedAt,
  });

  final String file;
  final int bytes;
  final bool downloaded;
  final bool stale;

  /// Null when not downloaded.
  final CopySource? source;

  /// Opened by the reader since it was downloaded.
  final bool opened;
  final DateTime? downloadedAt;
}

class PrefetchCourse {
  const PrefetchCourse({
    required this.course,
    required this.modules,
    this.inProgress = false,
    this.lastOpened,
    this.currentIndex = 0,
  });

  final String course;

  /// In reading order.
  final List<PrefetchModule> modules;
  final bool inProgress;
  final DateTime? lastOpened;

  /// Index of the module being read, or the next one to read.
  final int currentIndex;
}

class ModuleRef {
  const ModuleRef(this.course, this.file);
  final String course;
  final String file;

  @override
  bool operator ==(Object other) => other is ModuleRef && other.course == course && other.file == file;

  @override
  int get hashCode => Object.hash(course, file);

  @override
  String toString() => '$course/$file';
}

class PrefetchPlan {
  const PrefetchPlan({this.download = const [], this.refresh = const [], this.evict = const []});
  final List<ModuleRef> download;
  final List<ModuleRef> refresh;
  final List<ModuleRef> evict;

  bool get isEmpty => download.isEmpty && refresh.isEmpty && evict.isEmpty;
}

const int defaultCapBytes = 200 * 1024 * 1024;
const int recentDays = 14;
const int aheadCount = 2;

/// One pass. Nothing happens unless the toggle is on, the phone is on unmetered Wi-Fi and it is
/// charging; mobile data never prefetches.
PrefetchPlan planPrefetch({
  required List<PrefetchCourse> courses,
  required DateTime now,
  required bool enabled,
  required bool unmeteredWifi,
  required bool charging,
  int capBytes = defaultCapBytes,
}) {
  if (!enabled || !unmeteredWifi || !charging) return const PrefetchPlan();

  bool eligible(PrefetchCourse c) =>
      c.inProgress || (c.lastOpened != null && now.difference(c.lastOpened!).inDays < recentDays);

  final download = <ModuleRef>[];
  final refresh = <ModuleRef>[];
  final downloadBytes = <ModuleRef, int>{};

  for (final c in courses.where(eligible)) {
    var taken = 0;
    final start = c.currentIndex.clamp(0, c.modules.length);
    for (var i = start; i < c.modules.length && taken < aheadCount; i++) {
      final m = c.modules[i];
      if (m.downloaded) continue;
      final ref = ModuleRef(c.course, m.file);
      download.add(ref);
      downloadBytes[ref] = m.bytes;
      taken++;
    }
    for (final m in c.modules) {
      if (m.downloaded && m.stale) refresh.add(ModuleRef(c.course, m.file));
    }
  }

  // Prefetched copies already on the device count against the cap. Evict the oldest unopened
  // ones first; a module Sconl took offline himself, or one he has opened, is never touched.
  final prefetched = <({ModuleRef ref, PrefetchModule m})>[];
  for (final c in courses) {
    for (final m in c.modules) {
      if (m.downloaded && m.source == CopySource.prefetch) {
        prefetched.add((ref: ModuleRef(c.course, m.file), m: m));
      }
    }
  }
  var used = prefetched.fold<int>(0, (a, e) => a + e.m.bytes);
  final incoming = downloadBytes.values.fold<int>(0, (a, b) => a + b);

  final evict = <ModuleRef>[];
  if (used + incoming > capBytes) {
    final candidates = prefetched.where((e) => !e.m.opened).toList()
      ..sort((a, b) {
        final x = a.m.downloadedAt, y = b.m.downloadedAt;
        if (x == null && y == null) return 0;
        if (x == null) return -1;
        if (y == null) return 1;
        return x.compareTo(y);
      });
    for (final e in candidates) {
      if (used + incoming <= capBytes) break;
      evict.add(e.ref);
      used -= e.m.bytes;
    }
  }

  // If eviction cannot make room, drop downloads from the end until the pass fits.
  var total = used + incoming;
  final kept = [...download];
  while (total > capBytes && kept.isNotEmpty) {
    final dropped = kept.removeLast();
    total -= downloadBytes[dropped] ?? 0;
  }

  return PrefetchPlan(download: kept, refresh: refresh, evict: evict);
}
