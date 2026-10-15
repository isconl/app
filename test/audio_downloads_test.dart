import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:isconl/api/client.dart';
import 'package:isconl/services/audio_downloads.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('narr_dl'));
  tearDown(() => tmp.deleteSync(recursive: true));

  AudioDownloads make(http.Client c, {bool wifi = true}) => AudioDownloads(
        root: Directory('${tmp.path}/narration'),
        apiProvider: () => ApiClient(baseUrl: 'https://hub.test', token: 't0k'),
        client: c,
        isOnWifi: () async => wifi,
      );

  final body = utf8.encode('AUDIO-BYTES-0123456789');

  test('downloads a module, finds it again by revision, and sends the bearer token', () async {
    String? auth;
    Uri? seen;
    final dl = make(MockClient.streaming((req, _) async {
      auth = req.headers['Authorization'];
      seen = req.url;
      return http.StreamedResponse(Stream.value(body), 200, contentLength: body.length);
    }));
    final got = await dl.download(course: 'c1', file: 'm1.md', rev: 'r1');
    expect(got.bytes, body.length);
    expect(auth, 'Bearer t0k');
    expect(seen!.path, '/api/learning/audio');
    expect(seen!.queryParameters, {'course': 'c1', 'file': 'm1.md'});
    expect((await dl.local('c1', 'm1.md', 'r1'))!.path, got.path);
    expect(await dl.local('c1', 'm1.md', 'r2'), isNull); // a changed module misses the old recording
    expect(await dl.local('c1', 'm1.md', ''), isNull);
  });

  test('a new revision replaces and prunes the old file', () async {
    final dl = make(MockClient.streaming((req, _) async => http.StreamedResponse(Stream.value(body), 200, contentLength: body.length)));
    await dl.download(course: 'c1', file: 'm1.md', rev: 'r1');
    await dl.download(course: 'c1', file: 'm1.md', rev: 'r2');
    expect(await dl.local('c1', 'm1.md', 'r1'), isNull);
    expect(await dl.local('c1', 'm1.md', 'r2'), isNotNull);
    expect(await dl.bytesUsed('c1'), body.length);
  });

  test('resumes a partial file with a Range header and appends', () async {
    final dl = make(MockClient.streaming((req, _) async {
      expect(req.headers['Range'], 'bytes=5-');
      return http.StreamedResponse(Stream.value(body.sublist(5)), 206, contentLength: body.length - 5);
    }));
    final dir = Directory('${tmp.path}/narration/c1')..createSync(recursive: true);
    File('${dir.path}/m1.md__r1.audio.part').writeAsBytesSync(body.sublist(0, 5));
    final got = await dl.download(course: 'c1', file: 'm1.md', rev: 'r1');
    expect(File(got.path).readAsBytesSync(), body);
  });

  test('a server that ignores Range sends the whole file and it is not doubled', () async {
    final dl = make(MockClient.streaming((req, _) async =>
        http.StreamedResponse(Stream.value(body), 200, contentLength: body.length)));
    final dir = Directory('${tmp.path}/narration/c1')..createSync(recursive: true);
    File('${dir.path}/m1.md__r1.audio.part').writeAsBytesSync(body.sublist(0, 5));
    final got = await dl.download(course: 'c1', file: 'm1.md', rev: 'r1');
    expect(File(got.path).readAsBytesSync(), body);
  });

  test('Wi-Fi only refuses on mobile data unless forced', () async {
    var hits = 0;
    final dl = make(MockClient.streaming((req, _) async {
      hits++;
      return http.StreamedResponse(Stream.value(body), 200, contentLength: body.length);
    }), wifi: false);
    await expectLater(dl.download(course: 'c', file: 'f', rev: 'r'), throwsA(isA<AudioDownloadException>()));
    expect(hits, 0);
    await dl.download(course: 'c', file: 'f', rev: 'r', force: true);
    expect(hits, 1);
  });

  test('a missing narration and a dropped connection give plain sentences', () async {
    final nf = make(MockClient.streaming((req, _) async => http.StreamedResponse(const Stream.empty(), 404)));
    await expectLater(nf.download(course: 'c', file: 'f', rev: 'r'),
        throwsA(predicate((e) => e is AudioDownloadException && e.message.contains('not available'))));
    final off = make(MockClient.streaming((req, _) async => throw const SocketException('down')));
    await expectLater(off.download(course: 'c', file: 'f', rev: 'r'),
        throwsA(predicate((e) => e is AudioDownloadException && e.message.contains('No connection'))));
    expect(off.progress, isEmpty);
  });

  test('usage lists courses, and deleting one frees it', () async {
    final dl = make(MockClient.streaming((req, _) async => http.StreamedResponse(Stream.value(body), 200, contentLength: body.length)));
    await dl.downloadCourse('c1', [(file: 'a.md', rev: '1'), (file: 'b.md', rev: '1')]);
    await dl.download(course: 'c2', file: 'x.md', rev: '1');
    expect(await dl.usage(), {'c1': body.length * 2, 'c2': body.length});
    await dl.deleteCourse('c1');
    expect(await dl.usage(), {'c2': body.length});
  });

  test('prettyBytes', () {
    expect(prettyBytes(900), '900 B');
    expect(prettyBytes(2048), '2 KB');
    expect(prettyBytes(5 * 1024 * 1024), '5.0 MB');
  });
}
