// BI26112001: the console's music comes from hold through hub: listing walks sub-folders and drops duplicates, a file
// is opened (queued, then ready) before it streams, and the stream url and cache download carry the app's session.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:isconl/api/client.dart';
import 'package:isconl/data/audio_library.dart';

void main() {
  test('parseHoldListing keeps folders and playable files, drops the rest', () {
    final r = parseHoldListing({
      'items': [
        {'path': 'music/pull-1', 'name': 'pull-1', 'folder': true, 'size': 0, 'modified': 0},
        {'path': 'music/a_song.mp3', 'name': 'a_song.mp3', 'folder': false, 'size': 100, 'modified': 1700000000},
        {'path': 'music/clip.MP4', 'name': 'clip.MP4', 'folder': false, 'size': 50, 'modified': 0},
        {'path': 'music/cover.jpg', 'name': 'cover.jpg', 'folder': false, 'size': 5, 'modified': 0},
      ]
    });
    expect(r.dirs, ['music/pull-1']);
    expect(r.files.map((f) => f.title), ['a song', 'clip']);
    expect(r.files.first.uri, 'media:music/a_song.mp3');
    expect(r.files.first.modified, DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000, isUtc: true));
  });

  test('files walks sub-folders, dedupes the same song from two pulls, and orders music by title', () async {
    final listings = {
      holdMusicRoot: [
        {'path': 'music/b', 'name': 'b', 'folder': true},
        {'path': 'music/zeta.mp3', 'name': 'zeta.mp3', 'folder': false, 'size': 9},
      ],
      'music/b': [
        {'path': 'music/b/alpha.mp3', 'name': 'alpha.mp3', 'folder': false, 'size': 7},
        {'path': 'music/b/zeta.mp3', 'name': 'zeta.mp3', 'folder': false, 'size': 9},
      ],
    };
    final api = ApiClient(
        baseUrl: 'https://hub.test',
        token: 't0k',
        httpClient: MockClient((req) async {
          final path = req.url.queryParameters['path']!;
          return http.Response(jsonEncode({'items': listings[path] ?? []}), 200);
        }));
    final tracks = await HoldLibrarySource(api).files(libraryFolders().first);
    expect(tracks.map((t) => t.path), ['music/b/alpha.mp3', 'music/zeta.mp3']);
  });

  test('streamFor opens the file, waits until ready, then hands back the file url with the session header', () async {
    var asks = 0;
    final api = ApiClient(
        baseUrl: 'https://hub.test',
        token: 't0k',
        httpClient: MockClient((req) async {
          expect(req.url.path, '/api/hold/open');
          expect(req.headers['Authorization'], 'Bearer t0k');
          asks++;
          return http.Response(jsonEncode({'status': asks < 3 ? 'queued' : 'ready', 'size': 10}), 200);
        }));
    final s = await HoldLibrarySource(api, pollEvery: Duration.zero).streamFor('music/a b.mp3');
    expect(asks, 3);
    expect(s.url, 'https://hub.test/api/hold/file?path=music%2Fa+b.mp3');
    expect(s.headers, {'Authorization': 'Bearer t0k'});
  });

  test('a file the archive machine never opens fails with a message, not silently', () async {
    final api = ApiClient(
        baseUrl: 'https://hub.test',
        httpClient: MockClient((req) async => http.Response(jsonEncode({'status': 'queued'}), 200)));
    final src = HoldLibrarySource(api, pollEvery: Duration.zero, waitFor: Duration.zero);
    await expectLater(src.streamFor('music/x.mp3'),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('still fetching'))));
  });

  test('SplitLibrarySource sends music to hold and the rest to the other source', () async {
    final hold = FakeLibrarySource({holdMusicRoot: [const LibraryTrack(path: 'music/s.mp3', title: 's', bytes: 1)]});
    final media = FakeLibrarySource({'Audio/audio-recordings': [const LibraryTrack(path: 'Audio/audio-recordings/r.m4a', title: 'r', bytes: 1)]});
    final split = SplitLibrarySource(music: hold, other: media);
    final folders = libraryFolders();
    expect((await split.files(folders[0])).single.path, 'music/s.mp3');
    expect((await split.files(folders[1])).single.path, 'Audio/audio-recordings/r.m4a');
    await split.streamFor('music/s.mp3');
    await split.streamFor('Audio/audio-recordings/r.m4a');
    expect(hold.tickets, 1);
    expect(media.tickets, 1);
  });
}
