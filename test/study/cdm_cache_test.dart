import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/study/cdm/cdm_cache.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// BI26092620: the version-keyed offline cache, against a real (ffi) sqlite.
String docJson(String headline) => jsonEncode({
      'ddm': '1',
      'headline': headline,
      'sections': [
        {'type': 'paragraph', 'text': headline}
      ]
    });

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late CdmCache cache;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath, options: OpenDatabaseOptions(singleInstance: false));
    await CdmCache.createTables(db);
    cache = CdmCache(db);
  });
  tearDown(() => db.close());

  test('the second open of a version makes zero network calls', () async {
    var calls = 0;
    Future<String?> fetch(String id, String v) async {
      calls++;
      return docJson('$id@$v');
    }

    final first = await cache.open('mod-1', '3', fetch);
    expect(first!.headline, 'mod-1@3');
    expect(calls, 1);
    final second = await cache.open('mod-1', '3', fetch);
    expect(second!.headline, 'mod-1@3');
    expect(calls, 1, reason: 'a cached doc@version is read locally');
  });

  test('offline with nothing cached is null, offline with a cached version still opens', () async {
    expect(await cache.open('mod-1', '1', (_, _) async => null), isNull);
    await cache.write('mod-1', '1', docJson('cached'));
    expect((await cache.open('mod-1', '1', (_, _) async => null))!.headline, 'cached');
  });

  test('a payload that is not a document is never cached', () async {
    expect(await cache.open('mod-1', '1', (_, _) async => 'not json'), isNull);
    expect(await cache.has('mod-1', '1'), isFalse);
  });

  test('a corrupt cached row is dropped so the next open refetches', () async {
    await db.insert('cdm_cache',
        {'doc_id': 'mod-1', 'version': '1', 'content_hash': '', 'json': '{{{', 'fetched_at': 1});
    expect(await cache.open('mod-1', '1', (_, _) async => null), isNull);
    expect(await cache.has('mod-1', '1'), isFalse);
    expect((await cache.open('mod-1', '1', (_, _) async => docJson('fresh')))!.headline, 'fresh');
  });

  test('only the newest two versions of a document are kept', () async {
    for (final v in ['1', '2', '3']) {
      await cache.write('mod-1', v, docJson('v$v'));
      await Future<void>.delayed(const Duration(milliseconds: 3));
    }
    expect(await cache.has('mod-1', '1'), isFalse);
    expect(await cache.has('mod-1', '2'), isTrue);
    expect(await cache.has('mod-1', '3'), isTrue);
    expect(await cache.latestVersion('mod-1'), '3');
  });

  test('sync fetches only what the manifest says moved, then answers 304', () async {
    await cache.write('a', '1', docJson('a1'));
    final fetched = <String>[];
    Future<String?> fetch(String id, String v) async {
      fetched.add('$id@$v');
      return docJson('$id@$v');
    }

    CdmManifest manifest(String? etag) => const CdmManifest([
          CdmManifestEntry(docId: 'a', version: '1'),
          CdmManifestEntry(docId: 'b', version: '1'),
          CdmManifestEntry(docId: 'c', version: '4'),
        ], etag: 'W/"m1"');

    String? sentEtag = 'unset';
    var r = await cache.sync((etag) async {
      sentEtag = etag;
      return manifest(etag);
    }, fetch);
    expect(sentEtag, isNull, reason: 'the first sync has no ETag to revalidate with');
    expect(r.fetched, ['b', 'c']);
    expect(fetched, ['b@1', 'c@4'], reason: 'a@1 was already on the device');

    fetched.clear();
    r = await cache.sync((etag) async {
      sentEtag = etag;
      return etag == 'W/"m1"' ? null : manifest(etag); // the server answers 304 to the stored ETag
    }, fetch);
    expect(sentEtag, 'W/"m1"');
    expect(r.notModified, isTrue);
    expect(fetched, isEmpty);
  });

  test('a half-finished sync does not store the ETag, so it is retried in full', () async {
    CdmManifest manifest() =>
        const CdmManifest([CdmManifestEntry(docId: 'a', version: '1'), CdmManifestEntry(docId: 'b', version: '1')], etag: 'e1');
    var r = await cache.sync((_) async => manifest(), (id, v) async => id == 'b' ? null : docJson(id));
    expect(r.failed, ['b']);
    expect(r.fetched, ['a']);
    String? sent = 'unset';
    r = await cache.sync((etag) async {
      sent = etag;
      return manifest();
    }, (id, v) async => docJson(id));
    expect(sent, isNull, reason: 'the failed sync left no ETag behind');
    expect(r.fetched, ['b']);
  });

  test('a manifest body parses, skipping entries with no id or version', () {
    final m = CdmCache.parseManifest(
        jsonEncode({
          'docs': [
            {'id': 'a', 'version': '2', 'contentHash': 'h'},
            {'id': '', 'version': '1'},
            {'id': 'c'},
            {'doc_id': 'd', 'version': 5},
          ]
        }),
        etag: 'x');
    expect(m.entries.map((e) => '${e.docId}@${e.version}'), ['a@2', 'd@5']);
    expect(m.etag, 'x');
  });

  test('images are fetched once and then served from the cache', () async {
    var calls = 0;
    Future<Uint8List?> fetch(String url) async {
      calls++;
      return Uint8List.fromList([1, 2, 3]);
    }

    expect(await cache.image('https://x/y.png', fetch), [1, 2, 3]);
    expect(await cache.image('https://x/y.png', fetch), [1, 2, 3]);
    expect(calls, 1);
    expect(await cache.image('https://x/missing.png', (_) async => null), isNull);
  });
}
