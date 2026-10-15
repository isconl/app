import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:isconl/api/client.dart';
import 'package:isconl/services/audio_downloads.dart';
import 'package:isconl/services/course_offline.dart';

void main() {
  group('assetFilesIn', () {
    test('finds markdown and html image references once, in order', () {
      const md = '''
Intro ![A diagram](_assets/fig1.png) and again ![same](_assets/fig1.png).

<img src="_assets/fig2.svg" alt="x"> and ![](./_assets/fig 3.png)

[a link](https://example.com/x.png) is not an asset.
''';
      expect(assetFilesIn(md), ['fig1.png', 'fig2.svg', 'fig']);
    });

    test('no assets, no results', () {
      expect(assetFilesIn('Just words.'), isEmpty);
      expect(assetFilesIn(''), isEmpty);
    });
  });

  test('the asset URL matches what the reading surface builds', () {
    // lib/util/markdown.dart _resolveImageUrl: base without trailing slash, then
    // /api/learning/asset?course=<cid>&file=<file>&token=<tok>, each URL-encoded.
    expect(
      assetUrl(baseUrl: 'https://hub.test/', token: 't k', course: 'c 1', file: 'fig 1.png'),
      'https://hub.test/api/learning/asset?course=c%201&file=fig%201.png&token=t%20k',
    );
  });

  test('deleteAll removes every downloaded narration', () async {
    final tmp = Directory.systemTemp.createTempSync('offline_all');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final body = utf8.encode('AUDIO');
    final dl = AudioDownloads(
      root: Directory('${tmp.path}/narration'),
      apiProvider: () => ApiClient(baseUrl: 'https://hub.test'),
      client: MockClient.streaming((req, _) async => http.StreamedResponse(Stream.value(body), 200, contentLength: body.length)),
    );
    await dl.download(course: 'c1', file: 'a.md', rev: '1');
    await dl.download(course: 'c2', file: 'b.md', rev: '1');
    expect((await dl.usage()).length, 2);
    await dl.deleteAll();
    expect(await dl.usage(), isEmpty);
    expect(await dl.local('c1', 'a.md', '1'), isNull);
  });
}
