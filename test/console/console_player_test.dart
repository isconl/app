import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/console/console_player.dart';

import 'fakes.dart';

ConsoleTrack t(String id) => ConsoleTrack(id: id, title: 'Track $id', uri: 'https://x/$id.mp3');

void main() {
  late FakeAudio audio;
  late MemoryKv kv;
  late ConsolePlayer player;

  setUp(() {
    audio = FakeAudio();
    kv = MemoryKv();
    player = ConsolePlayer(() => audio, kv);
  });
  tearDown(() => player.dispose());

  test('the first queued track is loaded but not started; playNow starts it', () async {
    await player.addToQueue(t('a'));
    expect(audio.loaded, ['a']);
    expect(audio.isPlaying, isFalse);
    expect(player.duration, const Duration(minutes: 10));
    await player.addToQueue(t('b'), playNow: true);
    expect(audio.loaded, ['a', 'b']);
    expect(audio.isPlaying, isTrue);
    expect(player.current!.id, 'b');
  });

  test('play and pause toggle, and the state follows the engine', () async {
    await player.addToQueue(t('a'));
    await player.togglePlay();
    await Future<void>.delayed(Duration.zero);
    expect(player.playing, isTrue);
    await player.togglePlay();
    await Future<void>.delayed(Duration.zero);
    expect(player.playing, isFalse);
  });

  test('skip back 15 s and forward 30 s, clamped to the track', () async {
    await player.addToQueue(t('a'), playNow: true);
    audio.pos.add(const Duration(minutes: 1));
    await Future<void>.delayed(Duration.zero);
    await player.skipBackward();
    expect(audio.seeks.last, const Duration(seconds: 45));
    await player.skipForwardNow();
    expect(audio.seeks.last, const Duration(minutes: 1, seconds: 15));
    audio.pos.add(const Duration(minutes: 9, seconds: 50));
    await Future<void>.delayed(Duration.zero);
    await player.skipForwardNow();
    expect(audio.seeks.last, const Duration(minutes: 10), reason: 'never past the end');
    audio.pos.add(const Duration(seconds: 5));
    await Future<void>.delayed(Duration.zero);
    await player.skipBackward();
    expect(audio.seeks.last, Duration.zero, reason: 'never before the start');
  });

  test('a drag on the ring seeks proportionally', () async {
    await player.addToQueue(t('a'), playNow: true);
    await player.seekFraction(0.25);
    expect(audio.seeks.last, const Duration(minutes: 2, seconds: 30));
    await player.seekFraction(1.7);
    expect(audio.seeks.last, const Duration(minutes: 10));
    expect(player.fraction, 1.0);
  });

  test('speed cycles 1, 1.25, 1.5, 2 and wraps', () async {
    await player.addToQueue(t('a'));
    final seen = <double>[];
    for (var i = 0; i < 5; i++) {
      await player.cycleSpeed();
      seen.add(player.speed);
    }
    expect(seen, [1.25, 1.5, 2.0, 1.0, 1.25]);
    expect(audio.speed, 1.25);
  });

  test('a finished track moves on to the next one in the queue', () async {
    await player.addToQueue(t('a'), playNow: true);
    await player.addToQueue(t('b'));
    audio.done.add(null);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(player.current!.id, 'b');
    expect(audio.loaded.last, 'b');
  });

  test('removing and reordering keep the playing track selected', () async {
    await player.addToQueue(t('a'), playNow: true);
    await player.addToQueue(t('b'));
    await player.addToQueue(t('c'));
    await player.reorder(0, 2); // a moves to the end
    expect(player.queue.map((q) => q.id), ['b', 'c', 'a']);
    expect(player.current!.id, 'a', reason: 'the playing track follows the move');
    await player.removeAt(0); // b, before the playing track
    expect(player.queue.map((q) => q.id), ['c', 'a']);
    expect(player.current!.id, 'a');
  });

  test('a track that cannot load shows an error and does not throw', () async {
    audio.failLoad = true;
    await player.addToQueue(t('a'), playNow: true);
    expect(player.error, contains('Track a'));
    expect(player.playing, isFalse);
  });

  test('the queue, position and speed are remembered, restored paused, and resume where they were', () async {
    await player.addToQueue(t('a'));
    await player.addToQueue(t('b'), playNow: true);
    audio.pos.add(const Duration(minutes: 3));
    await Future<void>.delayed(Duration.zero);
    await player.cycleSpeed();
    await player.savePosition();

    final audio2 = FakeAudio();
    final p2 = ConsolePlayer(() => audio2, kv);
    addTearDown(p2.dispose);
    await p2.restore();
    expect(p2.queue.map((q) => q.id), ['a', 'b']);
    expect(p2.current!.id, 'b');
    expect(p2.position, const Duration(minutes: 3));
    expect(p2.speed, 1.25);
    expect(audio2.isPlaying, isFalse, reason: 'a launch must not start sound');
    expect(audio2.loaded, isEmpty, reason: 'nothing is loaded until Play');

    await p2.togglePlay();
    expect(audio2.loaded, ['b']);
    expect(audio2.seeks.last, const Duration(minutes: 3), reason: 'continues where it left off');
    expect(audio2.isPlaying, isTrue);
  });

  test('request headers are never written to the snapshot', () async {
    await player.addToQueue(ConsoleTrack(id: 'n', title: 'N', uri: 'https://x/n', headers: const {'Authorization': 'Bearer SECRET'}));
    expect(kv.data['console.player'], isNot(contains('SECRET')));
  });

  test('a damaged snapshot restores to an empty queue instead of failing', () async {
    kv.data['console.player'] = '{not json';
    await player.restore();
    expect(player.queue, isEmpty);
  });

  test('BI26101807: a long-press plays a library track next, right after the current one', () async {
    await player.addToQueue(t('a'));
    await player.addToQueue(t('b'));
    await player.addToQueue(t('c'));
    await player.playNext(t('z'));
    expect([for (final q in player.queue) q.id], ['a', 'z', 'b', 'c']);
    await player.playNext(t('c'));
    expect([for (final q in player.queue) q.id], ['a', 'c', 'z', 'b'], reason: 'a queued track moves rather than doubling');
    expect(player.current!.id, 'a');
  });

  test('BI26101807: a media: uri is resolved to a fresh url at play time, not at queue time', () async {
    final urls = <String>[];
    player.resolver = (tr) async {
      urls.add(tr.id);
      return ConsoleTrack(id: tr.id, title: tr.title, uri: 'https://media.test/stream?t=${urls.length}');
    };
    await player.addToQueue(const ConsoleTrack(id: 'm1', title: 'Song', uri: 'media:Audio/audio-music/song.mp3'));
    await player.addToQueue(const ConsoleTrack(id: 'm2', title: 'Song 2', uri: 'media:Audio/audio-music/song2.mp3'));
    expect(urls, ['m1'], reason: 'only the track that is loading is resolved');
    await player.next();
    expect(urls, ['m1', 'm2']);
    expect(player.queue.first.uri, startsWith('media:'), reason: 'the queue keeps the stable uri, so a restored queue never holds an expired ticket');
  });
}
