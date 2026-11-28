import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/study/pick/index_cache.dart';
import 'package:isconl/study/pick/models.dart';
import 'package:isconl/study/pick/profile.dart';
import 'package:isconl/study/pick/scorer.dart';

// Golden vectors: test/study/golden/*.json hold inputs and the expected order and reasons (the same files are loaded
// into abacus as profile isconl.study@1). Run with UPDATE_GOLDEN=1 to rewrite `expect` after a reviewed change.
Map<String, dynamic> _brief(StudyPick p) => {
      'top': _one(p.top),
      'lighter': _one(p.lighter),
      'deeper': _one(p.deeper),
      'candidates': p.candidates,
    };
Map<String, dynamic>? _one(Recommendation? r) => r == null ? null : {'id': r.card.id, 'reason': r.reason};

class _MemStore implements StudyIndexStore {
  final m = <String, String>{};
  @override
  Future<String?> read(String key) async => m[key];
  @override
  Future<void> write(String key, String value) async => m[key] = value;
  @override
  Future<void> delete(String key) async => m.remove(key);
}

class _Fetcher implements StudyIndexFetcher {
  final IndexFetch? answer;
  String? sawEtag;
  _Fetcher(this.answer);
  @override
  Future<IndexFetch> fetch(String? etag) async {
    sawEtag = etag;
    if (answer == null) throw const SocketException('offline');
    return answer!;
  }
}

String _hash(String s) => '${s.length}:${s.hashCode}';

void main() {
  final prof = StudyProfile.parse(null);

  group('golden vectors', () {
    final files = Directory('test/study/golden').listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    test('there are at least 8 vectors', () => expect(files.length, greaterThanOrEqualTo(8)));
    for (final f in files) {
      final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      test(j['name'] as String, () {
        final got = _brief(pickStudy(StudyInputs.fromJson(j['inputs'] as Map<String, dynamic>), prof));
        if (Platform.environment['UPDATE_GOLDEN'] == '1') {
          j['expect'] = got;
          f.writeAsStringSync(const JsonEncoder.withIndent(' ').convert(j));
          return;
        }
        expect(j['expect'], isNotNull, reason: 'no expected result recorded; run with UPDATE_GOLDEN=1 and review');
        expect(got, j['expect']);
      });
    }
  });

  test('every pick has a reason built from its two largest parts, in plain words', () {
    final j = jsonDecode(File('test/study/golden/01_fit_leads.json').readAsStringSync()) as Map<String, dynamic>;
    final p = pickStudy(StudyInputs.fromJson(j['inputs'] as Map<String, dynamic>), prof);
    expect(p.top!.reason, contains('before your 15:00 block'));
    expect(p.top!.reason.split('; ').length, lessThanOrEqualTo(2));
    expect(p.top!.reason, isNot(contains('—')));
    expect(p.top!.parts.map((e) => e.name), containsAll(['fit', 'coverage', 'momentum', 'relevance', 'review', 'announcement']));
  });

  test('a replacement profile that cannot be read falls back to the shipped one', () {
    expect(StudyProfile.parse('{not json').fit, 1.5);
    expect(StudyProfile.parse('{"weights":{"fit":2.5}}').fit, 2.5);
    expect(StudyProfile.parse('{"weights":{"fit":2.5}}').coverage, 1.0);
  });

  test('nothing eligible gives an empty pick, not an error', () {
    final p = pickStudy(StudyInputs(now: DateTime(2026, 10, 19), cards: const [ModuleCard(id: 'x', track: 't', minutes: 10, archived: true)]), prof);
    expect(p.top, isNull);
  });

  test('600 modules rank in under 100 ms', () {
    final cards = [
      for (var i = 0; i < 600; i++)
        ModuleCard(id: 'm${i.toString().padLeft(3, '0')}', track: 't${i % 6}', subjects: ['s${i % 20}'], minutes: 10 + (i % 50), difficulty: 1 + i % 5, prerequisites: i % 7 == 0 && i > 0 ? ['m${(i - 1).toString().padLeft(3, '0')}'] : const [])
    ];
    final inp = StudyInputs(
      now: DateTime(2026, 10, 19, 14, 20),
      cards: cards,
      minutesUntilNextBlock: 40,
      energy: 6,
      tracks: {for (var t = 0; t < 6; t++) 't$t': TrackState(unreadMinutes: 4000, targetDate: DateTime(2027, 4, 19), cyclesBehind: t / 2)},
      events: const [SubjectMention(['s3'])],
      sessions: [for (var i = 0; i < 80; i++) StudySession(DateTime(2026, 10, 1 + i % 18, 14), i % 3 != 0)],
    );
    pickStudy(inp, prof); // warm up
    final sw = Stopwatch()..start();
    final p = pickStudy(inp, prof);
    sw.stop();
    expect(p.top, isNotNull);
    expect(sw.elapsedMilliseconds, lessThan(100));
  });

  group('index cache self-heal', () {
    const body = '{"modules":[{"id":"a","track":"t","minutes":20}]}';
    Future<List<ModuleCard>> thin() async => const [ModuleCard(id: 'thin', track: 't', minutes: 15)];

    test('a missing cache gives a degraded thin index and a notice', () async {
      final c = StudyIndexCache(store: _MemStore(), hash: _hash, thinIndex: thin);
      final l = await c.load();
      expect(l.degraded, isTrue);
      expect(l.cards.single.id, 'thin');
      expect(l.notice, isNotNull);
    });

    test('a good fetch is stored with its etag and read back without the network', () async {
      final s = _MemStore();
      final c = StudyIndexCache(store: s, hash: _hash, thinIndex: thin);
      expect(await c.refresh(_Fetcher(const IndexFetch(200, body: body, etag: 'e1'))), isTrue);
      final l = await c.load();
      expect(l.degraded, isFalse);
      expect(l.cards.single.id, 'a');
      final f = _Fetcher(const IndexFetch(304));
      expect(await c.refresh(f), isTrue);
      expect(f.sawEtag, 'e1');
    });

    test('a hash failure or unreadable cache degrades, and the next online refresh heals it', () async {
      final s = _MemStore();
      final c = StudyIndexCache(store: s, hash: _hash, thinIndex: thin);
      await c.refresh(_Fetcher(const IndexFetch(200, body: body, etag: 'e1')));
      s.m[StudyIndexCache.bodyKey] = '{"modules":[]}'; // damaged: hash no longer matches
      expect((await c.load()).degraded, isTrue);
      expect(await c.refresh(_Fetcher(const IndexFetch(200, body: body, etag: 'e2'))), isTrue);
      expect((await c.load()).degraded, isFalse);
    });

    test('offline or a bad body keeps the previous copy and never throws', () async {
      final s = _MemStore();
      final c = StudyIndexCache(store: s, hash: _hash, thinIndex: thin);
      await c.refresh(_Fetcher(const IndexFetch(200, body: body, etag: 'e1')));
      expect(await c.refresh(_Fetcher(null)), isTrue);
      expect(await c.refresh(_Fetcher(const IndexFetch(200, body: 'garbage'))), isTrue);
      expect((await c.load()).cards.single.id, 'a');
      expect(await StudyIndexCache(store: _MemStore(), hash: _hash, thinIndex: thin).refresh(_Fetcher(null)), isFalse);
    });
  });
}
