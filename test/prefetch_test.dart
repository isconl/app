import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/services/prefetch.dart';
import 'package:isconl/ui/widgets/prefetch_card.dart';

Map<String, dynamic> lesson(String file, String status, [int pos = 0]) => {'file': file, 'status': status, 'position': pos};
Map<String, dynamic> course(String id, List<Map<String, dynamic>> lessons) => {'ID': id, 'lessons': lessons};

class MemPrefetchStore implements PrefetchStore {
  PrefetchSettings s = const PrefetchSettings();
  PrefetchLedger l = PrefetchLedger();
  @override
  Future<PrefetchSettings> settings() async => s;
  @override
  Future<void> saveSettings(PrefetchSettings v) async => s = v;
  @override
  Future<PrefetchLedger> ledger() async => l;
  @override
  Future<void> saveLedger(PrefetchLedger v) async => l = v;
}

class FakeModules implements PrefetchModules {
  final here = <String>{};
  final stale = <String>{};
  final md = <String, String>{};
  final calls = <String>[];
  bool offline = false;

  @override
  Future<void> check() async => calls.add('check');
  @override
  Future<int> refreshStale() async {
    calls.add('refreshStale');
    final n = stale.length;
    stale.clear();
    return n;
  }

  @override
  bool isDownloaded(String course, String file) => here.contains('$course/$file');
  @override
  Future<bool> download(String course, String file) async {
    if (offline) return false;
    calls.add('download:$course/$file');
    here.add('$course/$file');
    return true;
  }

  @override
  Future<String> markdownOf(String course, String file) async => md['$course/$file'] ?? 'text of $file';
  @override
  Future<void> forget(String course, String file) async {
    calls.add('forget:$course/$file');
    here.remove('$course/$file');
  }
}

final _t0 = DateTime.utc(2026, 10, 15, 8);

Prefetcher make(FakeModules m, MemPrefetchStore st, List<Map<String, dynamic>> courses,
        {bool Function()? gate, List<String>? warmed}) =>
    Prefetcher(
      modules: m,
      courses: () async => courses,
      store: st,
      onUnmeteredAndCharging: () async => gate?.call() ?? true,
      baseUrl: () => 'https://hub.test',
      token: () => 'tok',
      warmImage: (u) async {
        warmed?.add(u);
        return true;
      },
      now: () => _t0,
    );

void main() {
  group('which courses and which modules', () {
    test('a course is in progress when something is opened or learning, or some but not all are done', () {
      expect(courseInProgress(course('a', [lesson('1', 'new'), lesson('2', 'new')])), isFalse);
      expect(courseInProgress(course('a', [lesson('1', 'opened'), lesson('2', 'new')])), isTrue);
      expect(courseInProgress(course('a', [lesson('1', 'learning')])), isTrue);
      expect(courseInProgress(course('a', [lesson('1', 'done'), lesson('2', 'new')])), isTrue);
      expect(courseInProgress(course('a', [lesson('1', 'done'), lesson('2', 'done')])), isFalse);
      expect(courseInProgress(course('a', [])), isFalse);
    });

    test('plans the next two not-yet-downloaded lessons, skipping done and downloaded ones, in order', () {
      final c = course('c1', [
        lesson('m4', 'new', 4), lesson('m1', 'done', 1), lesson('m2', 'opened', 2), lesson('m3', 'new', 3),
      ]);
      expect(planPrefetch([c], (_, __) => false).map((p) => p.file), ['m2', 'm3']);
      expect(planPrefetch([c], (cc, f) => f == 'm2').map((p) => p.file), ['m3', 'm4']);
    });

    test('courses nobody is studying are left alone', () {
      final idle = course('idle', [lesson('a', 'new', 1), lesson('b', 'new', 2)]);
      final live = course('live', [lesson('a', 'done', 1), lesson('b', 'new', 2)]);
      expect(planPrefetch([idle, live], (_, __) => false).map((p) => '${p.course}/${p.file}'), ['live/b']);
    });
  });

  group('ledger and eviction', () {
    test('evicts oldest first, only until it fits, and never an opened module', () {
      final l = PrefetchLedger();
      l.add('a/1', 100, DateTime.utc(2026, 10, 1));
      l.add('a/2', 100, DateTime.utc(2026, 10, 2));
      l.add('a/3', 100, DateTime.utc(2026, 10, 3));
      expect(l.evictionOrder(300), isEmpty);
      expect(l.evictionOrder(250), ['a/1']);
      expect(l.evictionOrder(100), ['a/1', 'a/2']);
      l.markOpened('a/1');
      // a/1 is the reader's now: the two that remain total 200, so one goes.
      expect(l.evictionOrder(100), ['a/2']);
      expect(l.evictionOrder(0), ['a/2', 'a/3']);
    });

    test('settings and ledger survive JSON', () {
      expect(PrefetchSettings.fromJson(const PrefetchSettings(enabled: false, capBytes: 5).toJson()).enabled, isFalse);
      expect(PrefetchSettings.fromJson(null).enabled, isTrue);
      expect(PrefetchSettings.fromJson(null).capBytes, 200 * 1024 * 1024);
      final l = PrefetchLedger()..add('a/1', 7, DateTime.utc(2026, 10, 1));
      expect(PrefetchLedger.fromJson(l.toJson()).entries['a/1']!.bytes, 7);
    });
  });

  group('a prefetch pass', () {
    final courses = [
      course('c1', [lesson('m1', 'done', 1), lesson('m2', 'new', 2), lesson('m3', 'new', 3), lesson('m4', 'new', 4)]),
    ];

    test('on Wi-Fi and charging it fetches the next two modules and warms their images', () async {
      final m = FakeModules()..md['c1/m2'] = 'See ![x](_assets/a.png)';
      final warmed = <String>[];
      final st = MemPrefetchStore();
      final r = await make(m, st, courses, warmed: warmed).run();
      expect(r.skipped, isNull);
      expect(r.fetched, 2);
      expect(m.here, {'c1/m2', 'c1/m3'});
      expect(warmed.single, 'https://hub.test/api/learning/asset?course=c1&file=a.png&token=tok');
      expect(st.l.entries.keys, containsAll(['c1/m2', 'c1/m3']));
    });

    test('on mobile data or unplugged, nothing downloads', () async {
      final m = FakeModules();
      final r = await make(m, MemPrefetchStore(), courses, gate: () => false).run();
      expect(r.skipped, contains('Wi-Fi'));
      expect(m.calls, isEmpty);
    });

    test('the toggle off stops it', () async {
      final m = FakeModules();
      final st = MemPrefetchStore()..s = const PrefetchSettings(enabled: false);
      final r = await make(m, st, courses).run();
      expect(r.skipped, 'switched off');
      expect(m.calls, isEmpty);
    });

    test('unplugging mid-run stops after the current module', () async {
      final m = FakeModules();
      var n = 0;
      final r = await make(m, MemPrefetchStore(), courses, gate: () => n++ < 2).run();
      expect(r.fetched, 1);
      expect(m.here.length, 1);
    });

    test('going offline stops the pass without error', () async {
      final m = FakeModules()..offline = true;
      final r = await make(m, MemPrefetchStore(), courses).run();
      expect(r.fetched, 0);
      expect(r.skipped, isNull);
    });

    test('stale downloaded modules are refreshed in the same pass', () async {
      final m = FakeModules()..stale.add('c1/m9');
      final r = await make(m, MemPrefetchStore(), courses).run();
      expect(r.refreshed, 1);
    });

    test('the cap evicts only prefetched modules, oldest first, and leaves manual downloads', () async {
      final m = FakeModules()
        ..here.addAll({'c9/manual', 'c1/old'})
        ..md['c1/m2'] = 'x' * 600
        ..md['c1/m3'] = 'y' * 600;
      final st = MemPrefetchStore()
        ..s = const PrefetchSettings(capBytes: 1000)
        ..l = (PrefetchLedger()..add('c1/old', 500, DateTime.utc(2026, 9, 1)));
      final r = await make(m, st, courses).run();
      expect(r.evicted, greaterThanOrEqualTo(1));
      expect(m.calls, contains('forget:c1/old'));
      expect(m.here, contains('c9/manual'));
      expect(st.l.entries.containsKey('c1/old'), isFalse);
    });

    test('opening a prefetched module takes it out of the ledger', () async {
      final st = MemPrefetchStore()..l = (PrefetchLedger()..add('c1/m2', 10, _t0));
      await markPrefetchOpened(st, 'c1', 'm2');
      expect(st.l.entries, isEmpty);
    });
  });

  group('settings card', () {
    testWidgets('the switch saves and reschedules; the cap changes', (t) async {
      final st = MemPrefetchStore();
      final seen = <PrefetchSettings>[];
      await t.pumpWidget(MaterialApp(home: Scaffold(body: PrefetchCard(store: st, onChanged: (s) async => seen.add(s)))));
      await t.pumpAndSettle();
      expect(t.widget<SwitchListTile>(find.byKey(const Key('prefetch-switch'))).value, isTrue);
      await t.tap(find.byKey(const Key('prefetch-switch')));
      await t.pumpAndSettle();
      expect(st.s.enabled, isFalse);
      expect(seen.last.enabled, isFalse);
      expect(find.byKey(const Key('prefetch-cap')), findsNothing);
      await t.tap(find.byKey(const Key('prefetch-switch')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('prefetch-cap')));
      await t.pumpAndSettle();
      await t.tap(find.text('500 MB').last);
      await t.pumpAndSettle();
      expect(st.s.capBytes, 500 * 1024 * 1024);
    });
  });
}
