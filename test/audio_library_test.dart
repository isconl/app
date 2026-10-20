// BI26101807: library listing parse and order, stable media: uris, and the 200 MB least-recently-played cache cap.
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/data/audio_library.dart';

void main() {
  test('parseListing keeps playable audio and separates folders; images and other files are dropped', () {
    final r = parseListing({
      'path': 'Audio/audio-recordings',
      'entries': [
        {'name': '2026', 'path': 'Audio/audio-recordings/2026', 'type': 'dir'},
        {'name': 'a_song.mp3', 'path': 'Audio/audio-music/a_song.mp3', 'type': 'file', 'playable': true, 'image': false, 'bytes': 100, 'mtimeIso': '2026-10-01T10:00:00.000Z'},
        {'name': 'cover.jpg', 'path': 'Audio/audio-music/cover.jpg', 'type': 'file', 'playable': false, 'image': true, 'bytes': 5},
        {'name': 'notes.txt', 'path': 'Audio/audio-music/notes.txt', 'type': 'file', 'playable': false, 'bytes': 5},
      ],
    });
    expect(r.dirs, ['Audio/audio-recordings/2026']);
    expect(r.files.single.title, 'a song');
    expect(r.files.single.uri, 'media:Audio/audio-music/a_song.mp3');
  });

  test('music orders by title, recordings and voice notes newest first', () {
    LibraryTrack t(String n, int day) => LibraryTrack(path: n, title: n, bytes: 1, modified: DateTime(2026, 10, day));
    final tracks = [t('b', 1), t('a', 5), t('c', 3)];
    expect(orderTracks(LibraryFolderKind.music, tracks).map((e) => e.title), ['a', 'b', 'c']);
    expect(orderTracks(LibraryFolderKind.recordings, tracks).map((e) => e.title), ['a', 'c', 'b']);
    expect(orderTracks(LibraryFolderKind.voiceNotes, tracks).map((e) => e.title), ['a', 'c', 'b']);
  });

  test('three folders from the audio root', () {
    expect(libraryFolders().map((f) => f.label), ['Music', 'Recordings', 'Voice notes']);
    expect(libraryFolders(root: 'sconl/Crate/Media/Audio').first.path, 'sconl/Crate/Media/Audio/audio-music');
  });

  group('AudioCacheIndex', () {
    test('past the cap the least recently played go first, and the file just played stays', () {
      final c = AudioCacheIndex(capBytes: 100);
      expect(c.touch('a', 40), isEmpty);
      expect(c.touch('b', 40), isEmpty);
      expect(c.touch('a', 40), isEmpty, reason: 'a played again, so b is now the oldest');
      expect(c.touch('c', 40), ['b']);
      expect(c.totalBytes, 80);
      expect(c.has('b'), isFalse);
    });

    test('one file over the cap is kept alone rather than evicting itself', () {
      final c = AudioCacheIndex(capBytes: 10);
      c.touch('x', 5);
      expect(c.touch('big', 50), ['x']);
      expect(c.has('big'), isTrue);
    });

    test('survives a round trip through json', () {
      final c = AudioCacheIndex(capBytes: 100)..touch('a', 60)..touch('b', 30);
      final d = AudioCacheIndex.fromJson(c.toJson(), capBytes: 100);
      expect(d.touch('c', 30), ['a'], reason: 'a is oldest and the cap is 100');
    });
  });
}
