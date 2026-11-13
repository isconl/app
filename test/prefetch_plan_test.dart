import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/data/prefetch_plan.dart';

PrefetchModule m(String f, {int bytes = 1000, bool down = false, bool stale = false, CopySource? src, bool opened = false, DateTime? at}) =>
    PrefetchModule(file: f, bytes: bytes, downloaded: down, stale: stale, source: src, opened: opened, downloadedAt: at);

final now = DateTime(2026, 10, 12, 22);

PrefetchPlan plan(List<PrefetchCourse> cs, {bool enabled = true, bool wifi = true, bool charging = true, int cap = defaultCapBytes}) =>
    planPrefetch(courses: cs, now: now, enabled: enabled, unmeteredWifi: wifi, charging: charging, capBytes: cap);

PrefetchCourse course({int current = 0, List<PrefetchModule>? mods, bool inProgress = true, DateTime? last}) => PrefetchCourse(
      course: 'hr',
      inProgress: inProgress,
      lastOpened: last,
      currentIndex: current,
      modules: mods ?? [m('00'), m('01'), m('02'), m('03'), m('04')],
    );

void main() {
  test('on Wi-Fi and charging the next two not-yet-downloaded modules are fetched', () {
    final p = plan([course(current: 1)]);
    expect(p.download.map((r) => r.file), ['01', '02']);
  });

  test('already downloaded modules are skipped, so the two come from further on', () {
    final c = course(mods: [m('00', down: true), m('01', down: true, src: CopySource.manual), m('02'), m('03'), m('04')]);
    expect(plan([c]).download.map((r) => r.file), ['02', '03']);
  });

  test('mobile data, no charger or the toggle off downloads nothing', () {
    for (final p in [plan([course()], wifi: false), plan([course()], charging: false), plan([course()], enabled: false)]) {
      expect(p.isEmpty, isTrue);
    }
  });

  test('only courses in progress or opened in the last 14 days are included', () {
    final idle = course(inProgress: false, last: now.subtract(const Duration(days: 20)));
    final recent = course(inProgress: false, last: now.subtract(const Duration(days: 13)));
    final never = course(inProgress: false);
    expect(plan([idle]).download, isEmpty);
    expect(plan([never]).download, isEmpty);
    expect(plan([recent]).download.length, 2);
  });

  test('stale downloaded modules are refreshed in the same pass', () {
    final c = course(mods: [m('00', down: true, stale: true, src: CopySource.manual), m('01'), m('02')]);
    final p = plan([c]);
    expect(p.refresh.map((r) => r.file), ['00']);
    expect(p.download.map((r) => r.file), ['01', '02']);
  });

  test('over the cap, the oldest unopened prefetched copies go first', () {
    final c = course(mods: [
      m('00', bytes: 400, down: true, src: CopySource.prefetch, at: DateTime(2026, 10, 1)),
      m('01', bytes: 400, down: true, src: CopySource.prefetch, at: DateTime(2026, 10, 5)),
      m('02', bytes: 400),
      m('03', bytes: 400),
    ], current: 2);
    final p = plan([c], cap: 1000);
    expect(p.evict.map((r) => r.file), ['00', '01'], reason: '800 incoming plus 800 held is over 1000, so both go, oldest first');
    expect(p.download.map((r) => r.file), ['02', '03']);
  });

  test('manual copies and opened prefetched copies are never evicted, even over the cap', () {
    final c = course(mods: [
      m('00', bytes: 900, down: true, src: CopySource.manual, at: DateTime(2026, 9, 1)),
      m('01', bytes: 900, down: true, src: CopySource.prefetch, opened: true, at: DateTime(2026, 9, 2)),
      m('02', bytes: 500),
      m('03', bytes: 500),
    ], current: 2);
    final p = plan([c], cap: 1000);
    expect(p.evict, isEmpty);
    expect(p.download, isEmpty, reason: 'the pass drops what cannot fit rather than evicting protected copies');
  });

  test('when eviction cannot free enough, downloads are dropped from the end', () {
    final c = course(mods: [m('00', bytes: 600), m('01', bytes: 600), m('02', bytes: 600)]);
    final p = plan([c], cap: 700);
    expect(p.download.map((r) => r.file), ['00']);
  });

  test('a current index past the end plans nothing', () {
    expect(plan([course(current: 99)]).download, isEmpty);
  });
}
