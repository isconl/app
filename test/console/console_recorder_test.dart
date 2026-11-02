import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/console/console_recorder.dart';

import 'fakes.dart';

void main() {
  late FakeMic mic;
  late Clock clock;
  late MemoryKv kv;
  late List<Upload> uploads;
  late List<String> deleted;

  ConsoleRecorder make({Uint8List? bytes}) =>
      makeRecorder(mic: mic, clock: clock, kv: kv, uploads: uploads, bytes: bytes, deleted: deleted);

  setUp(() {
    mic = FakeMic();
    clock = Clock();
    kv = MemoryKv();
    uploads = [];
    deleted = [];
  });

  test('record, then stop: the take is on the device and waits for Keep or Discard', () async {
    final r = make();
    addTearDown(r.dispose);
    await r.toggleRecord();
    expect(r.state, RecorderState.recording);
    expect(mic.started, isTrue);
    clock.advance(const Duration(seconds: 192));
    expect(r.elapsed, const Duration(seconds: 192));
    await r.toggleRecord();
    expect(r.state, RecorderState.review);
    expect(r.hasTake, isTrue);
    expect(r.elapsed, const Duration(seconds: 192));
    expect(mic.disposed, isTrue);
    expect(uploads, isEmpty, reason: 'nothing is queued until Keep');
  });

  test('pause stops the clock and resume continues it', () async {
    final r = make();
    addTearDown(r.dispose);
    await r.toggleRecord();
    clock.advance(const Duration(seconds: 30));
    await r.togglePause();
    expect(r.state, RecorderState.paused);
    expect(mic.paused, isTrue);
    clock.advance(const Duration(minutes: 5));
    expect(r.elapsed, const Duration(seconds: 30), reason: 'time passing while paused is not recorded');
    await r.togglePause();
    expect(r.state, RecorderState.recording);
    clock.advance(const Duration(seconds: 12));
    expect(r.elapsed, const Duration(seconds: 42));
    await r.toggleRecord(); // stop from a running take
    expect(r.state, RecorderState.review);
    expect(r.elapsed, const Duration(seconds: 42));
  });

  test('one lap per ten minutes, and the lap count shows', () async {
    final r = make();
    addTearDown(r.dispose);
    await r.toggleRecord();
    clock.advance(const Duration(minutes: 25));
    expect(r.laps, 2);
    expect(r.lap, closeTo(0.5, 1e-9));
  });

  test('a refused microphone is a sentence, not a crash, and nothing starts', () async {
    mic.allowed = false;
    final r = make();
    addTearDown(r.dispose);
    expect(await r.start(), isFalse);
    expect(r.state, RecorderState.idle);
    expect(r.error, contains('microphone'));
    expect(mic.started, isFalse);
    expect(mic.disposed, isTrue);
  });

  test('Keep queues the file in chunks through the outbox and keeps a local copy', () async {
    final bytes = Uint8List.fromList(List.generate(ConsoleRecorder.chunkBytes * 2 + 100, (i) => i % 251));
    final r = make(bytes: bytes);
    addTearDown(r.dispose);
    await r.toggleRecord();
    clock.advance(const Duration(minutes: 5));
    await r.toggleRecord();
    final saved = await r.keep('Standup notes');
    expect(saved, isNotNull);
    expect(saved!.chunks, 3);
    expect(uploads, hasLength(3));
    expect(uploads.map((u) => u.path).toSet(), {ConsoleRecorder.uploadPath});
    expect(uploads.map((u) => u.body['index']), [0, 1, 2]);
    expect(uploads.every((u) => u.body['total'] == 3 && u.body['title'] == 'Standup notes'), isTrue);
    expect(uploads.every((u) => u.view == 'console'), isTrue);
    expect(uploads.first.body['durationMs'], const Duration(minutes: 5).inMilliseconds);
    // The chunks reassemble to exactly the recorded bytes.
    final joined = <int>[for (final u in uploads) ...base64Decode(u.body['data'] as String)];
    expect(joined, bytes);
    expect(deleted, isEmpty, reason: 'the local file stays');
    expect(r.state, RecorderState.idle);
    expect(r.status, contains('3 parts queued'));
    expect((await r.recordings()).single.title, 'Standup notes');
  });

  test('recording works with no connection: the take is saved and queued, nothing is sent', () async {
    // The outbox is the only network seam, and it only stores. No connectivity is consulted anywhere.
    final r = make(bytes: Uint8List.fromList([1, 2, 3]));
    addTearDown(r.dispose);
    await r.toggleRecord();
    await r.toggleRecord();
    await r.keep('');
    expect(uploads, hasLength(1));
    expect(uploads.single.body['total'], 1);
    expect((await r.recordings()), hasLength(1));
  });

  test('an empty title falls back to the suggestion, then to a dated name', () async {
    final r = make(bytes: Uint8List.fromList([1]));
    addTearDown(r.dispose);
    await r.toggleRecord();
    await r.toggleRecord();
    r.applySuggestion('Weekly planning');
    await r.keep('   ');
    expect(uploads.single.body['title'], 'Weekly planning');

    uploads.clear();
    await r.toggleRecord();
    await r.toggleRecord();
    await r.keep('');
    expect(uploads.single.body['title'], startsWith('Recording 2026-10-03'));
  });

  test('Discard deletes the file and queues nothing', () async {
    final r = make(bytes: Uint8List.fromList([1, 2]));
    addTearDown(r.dispose);
    await r.toggleRecord();
    await r.toggleRecord();
    await r.discard();
    expect(deleted, hasLength(1));
    expect(uploads, isEmpty);
    expect(r.state, RecorderState.idle);
    expect(r.hasTake, isFalse);
  });

  test('Discard while still recording stops first, then deletes', () async {
    final r = make();
    addTearDown(r.dispose);
    await r.toggleRecord();
    await r.discard();
    expect(mic.stopped, isTrue);
    expect(deleted, hasLength(1));
    expect(r.state, RecorderState.idle);
  });

  test('a take with nothing written is reported, not saved', () async {
    mic.stopResult = null;
    final r = make();
    addTearDown(r.dispose);
    await r.toggleRecord();
    await r.toggleRecord();
    expect(r.state, RecorderState.idle);
    expect(r.error, contains('Nothing was recorded'));
  });

  test('the saved list keeps newest first and survives damage', () async {
    final r = make(bytes: Uint8List.fromList([1]));
    addTearDown(r.dispose);
    for (final name in ['one', 'two']) {
      await r.toggleRecord();
      clock.advance(const Duration(seconds: 1));
      await r.toggleRecord();
      await r.keep(name);
      clock.advance(const Duration(seconds: 1));
    }
    expect((await r.recordings()).map((e) => e.title), ['two', 'one']);
    kv.data['console.recordings'] = 'garbage';
    expect(await r.recordings(), isEmpty);
  });

  test('a new take started while the last one is still closing keeps its own microphone', () async {
    final mics = <FakeMic>[];
    final r = ConsoleRecorder(
      makeBackend: () {
        final m = FakeMic();
        mics.add(m);
        return m;
      },
      newFilePath: (id) async => '/tmp/$id.m4a',
      readBytes: (_) async => Uint8List(0),
      deleteFile: (_) async {},
      enqueue: ({required path, required body, required label, required view}) async {},
      store: kv,
      now: clock.now,
    );
    addTearDown(r.dispose);
    await r.toggleRecord();
    clock.advance(const Duration(seconds: 1));
    final stopping = r.toggleRecord(); // stop; not awaited yet
    await Future<void>.delayed(Duration.zero);
    await r.discard();
    clock.advance(const Duration(milliseconds: 5));
    await r.toggleRecord(); // a second take straight away
    await stopping;
    expect(mics, hasLength(2));
    expect(r.state, RecorderState.recording);
    expect(mics[1].disposed, isFalse, reason: 'the first take\'s cleanup must not touch the second take\'s microphone');
    await r.discard();
  });
}
