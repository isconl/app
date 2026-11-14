// BH26101801: hold client contract, upload queue (resume, retry, restart) and conflict handling. No network.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/data/hold_data.dart';
import 'package:isconl/data/hold_uploads.dart';

Uint8List _bytes(int n) => Uint8List.fromList(List.generate(n, (i) => i % 251));

void main() {
  group('conflictFreeName', () {
    test('keeps both with a suffix, before the extension', () {
      expect(conflictFreeName('a.jpg', {}), 'a.jpg');
      expect(conflictFreeName('a.jpg', {'a.jpg'}), 'a (2).jpg');
      expect(conflictFreeName('a.jpg', {'a.jpg', 'a (2).jpg'}), 'a (3).jpg');
      expect(conflictFreeName('notes', {'notes'}), 'notes (2)');
      expect(conflictFreeName('.env', {'.env'}), '.env (2)');
    });
  });

  group('FakeHoldApi', () {
    late FakeHoldApi api;
    setUp(() async {
      api = FakeHoldApi();
      await api.mkdir('sconl/Crate');
      await api.mkdir('sconl/Crate/Media');
    });

    test('browse pages and sorts folders first', () async {
      for (var i = 0; i < 5; i++) {
        await api.mkdir('sconl/Crate/f$i');
      }
      final p1 = await api.list('sconl/Crate', limit: 3);
      expect(p1.items.length, 3);
      expect(p1.next, isNotNull);
      final p2 = await api.list('sconl/Crate', limit: 3, cursor: p1.next);
      expect(p2.items.length, 3);
      expect(p2.next, isNull);
      expect(p1.items.every((e) => e.isFolder), isTrue);
    });

    test('delete goes to trash and restores; rename and move refuse to overwrite', () async {
      final s = await api.beginUpload('sconl/Crate/a.txt', 3, '');
      await api.sendChunk(s.id, 0, Uint8List.fromList([1, 2, 3]));
      await api.finishUpload(s.id);
      await api.delete('sconl/Crate/a.txt');
      expect((await api.list('sconl/Crate')).items.where((e) => e.name == 'a.txt'), isEmpty);
      await api.restore('sconl/Crate/a.txt');
      expect((await api.list('sconl/Crate')).items.where((e) => e.name == 'a.txt'), hasLength(1));
      await api.copy('sconl/Crate/a.txt', 'sconl/Crate/b.txt');
      expect(() => api.rename('sconl/Crate/a.txt', 'b.txt'), throwsA(isA<HoldException>()));
    });

    test('search finds by name, share expires', () async {
      await api.mkdir('sconl/Crate/Media/holiday photos');
      expect((await api.search('holiday')).single.name, 'holiday photos');
      final sh = await api.share('sconl/Crate/Media', ttlHours: 2);
      expect(sh.expires.isAfter(DateTime.now().add(const Duration(hours: 1))), isTrue);
    });
  });

  group('UploadQueue', () {
    late FakeHoldApi api;
    late MemoryUploadStore store;
    setUp(() async {
      api = FakeHoldApi();
      await api.mkdir('sconl/Crate');
      store = MemoryUploadStore();
    });

    UploadQueue queue({int chunk = 100}) => UploadQueue(api, store, chunkSize: chunk, backoff: Duration.zero, sleep: (_) async {});

    test('uploads in chunks and the bytes match', () async {
      final q = queue();
      final data = _bytes(450);
      q.add('sconl/Crate', 'x.bin', BytesSource(data));
      await q.idle();
      expect(q.jobs.single.state, UploadState.done);
      expect(api.bytesOf('sconl/Crate/x.bin'), data);
      expect(api.chunkCalls, 5);
    });

    test('a flaky connection resumes and still finishes', () async {
      final q = queue();
      api.failNextChunks = 3;
      final data = _bytes(300);
      q.add('sconl/Crate', 'flaky.bin', BytesSource(data));
      await q.idle();
      expect(q.jobs.single.state, UploadState.done);
      expect(api.bytesOf('sconl/Crate/flaky.bin'), data);
    });

    test('gives up after maxAttempts and can be retried', () async {
      final q = queue();
      api.failNextChunks = 100;
      q.add('sconl/Crate', 'dead.bin', BytesSource(_bytes(50)));
      await q.idle();
      expect(q.jobs.single.state, UploadState.failed);
      api.failNextChunks = 0;
      q.retry(q.jobs.single);
      await q.idle();
      expect(q.jobs.single.state, UploadState.done);
    });

    test('an existing name is never overwritten', () async {
      final q = queue();
      q.add('sconl/Crate', 'a.txt', BytesSource(_bytes(10)));
      await q.idle();
      q.add('sconl/Crate', 'a.txt', BytesSource(_bytes(20)), taken: {'a.txt'});
      await q.idle();
      expect(api.bytesOf('sconl/Crate/a.txt')!.length, 10);
      expect(api.bytesOf('sconl/Crate/a (2).txt')!.length, 20);
    });

    test('the queue survives a restart: a job saved mid-flight resumes from the server offset once its source is back', () async {
      final data = _bytes(250);
      // The app died after the server took 100 bytes; the saved job says "running".
      final s = await api.beginUpload('sconl/Crate/big.bin', 250, 'sconl/Crate/big.bin:250');
      await api.sendChunk(s.id, 0, Uint8List.sublistView(data, 0, 100));
      await store.write('[{"id":"j1","dest":"sconl/Crate/big.bin","size":250,"session":"${s.id}","offset":100,"state":"running","attempts":0,"error":""}]');
      final q = queue();
      await q.restore();
      expect(q.jobs.single.state, UploadState.queued);
      await q.idle();
      expect(q.jobs.single.state, UploadState.queued, reason: 'no source yet, so it waits');
      q.attach('j1', BytesSource(data));
      await q.idle();
      expect(q.jobs.single.state, UploadState.done);
      expect(api.bytesOf('sconl/Crate/big.bin'), data);
      expect(api.chunkCalls, 1 + 2);
    });
  });

  group('suggestSort', () {
    test('names and files unsorted media by date and kind, folders get nothing', () {
      final d = DateTime(2025, 7, 3);
      final pic = suggestSort(HoldEntry(path: '_unsorted/IMG 1.JPG', name: 'IMG 1.JPG', isFolder: false, modified: d, mime: 'image/jpeg'))!;
      expect(pic.name, '20250703_img_1.jpg');
      expect(pic.folder, 'sconl/Crate/Media/Photos/2025/07');
      expect(suggestSort(HoldEntry(path: '_unsorted/x', name: 'x', isFolder: true)), isNull);
      final doc = suggestSort(HoldEntry(path: '_unsorted/cv.pdf', name: 'cv.pdf', isFolder: false, modified: d))!;
      expect(doc.folder, 'sconl/Crate/Documents/2025');
    });
  });

  group('HoldUsage and storage methods', () {
    late FakeHoldApi api;
    setUp(() async {
      api = FakeHoldApi();
      await api.mkdir('sconl/audio-recordings');
      await api.mkdir('sconl/voice-notes');
      await api.mkdir('sconl/Media/Photos');
      await api.mkdir('sconl/Documents');

      final r1 = await api.beginUpload('sconl/audio-recordings/session1.m4a', 500, '');
      await api.sendChunk(r1.id, 0, _bytes(500));
      await api.finishUpload(r1.id);
      api.setSource('sconl/audio-recordings/session1.m4a', 'isconl');

      final r2 = await api.beginUpload('sconl/audio-recordings/session2.m4a', 300, '');
      await api.sendChunk(r2.id, 0, _bytes(300));
      await api.finishUpload(r2.id);
      api.setSource('sconl/audio-recordings/session2.m4a', 'isconl');

      final v1 = await api.beginUpload('sconl/voice-notes/memo.m4a', 200, '');
      await api.sendChunk(v1.id, 0, _bytes(200));
      await api.finishUpload(v1.id);
      api.setSource('sconl/voice-notes/memo.m4a', 'deck');

      final p1 = await api.beginUpload('sconl/Media/Photos/pic.png', 400, '');
      await api.sendChunk(p1.id, 0, _bytes(400));
      await api.finishUpload(p1.id);

      final d1 = await api.beginUpload('sconl/Documents/report.pdf', 600, '');
      await api.sendChunk(d1.id, 0, _bytes(600));
      await api.finishUpload(d1.id);

      final t1 = await api.beginUpload('sconl/old.tmp', 150, '');
      await api.sendChunk(t1.id, 0, _bytes(150));
      await api.finishUpload(t1.id);
      await api.delete('sconl/old.tmp');
    });

    test('usage computes totals and folder/source/type breakdowns', () async {
      final u = await api.usage();
      expect(u.usedBytes, 500 + 300 + 200 + 400 + 600);
      expect(u.trashBytes, 150);
      expect(u.byFolder.map((s) => s.label), containsAll(['Recordings', 'Documents', 'Photos', 'Voice notes']));
      final rec = u.byFolder.firstWhere((s) => s.label == 'Recordings');
      expect(rec.bytes, 800);
      expect(rec.files, 2);

      expect(u.bySource.map((s) => s.key), containsAll(['isconl', 'deck', 'uploads']));
      expect(u.byType.map((s) => s.key), containsAll(['audio', 'pdf', 'image']));
    });

    test('largestFiles filters and sorts descending', () async {
      final allLargest = await api.largestFiles(limit: 3);
      expect(allLargest.length, 3);
      expect(allLargest[0].name, 'report.pdf');
      expect(allLargest[0].size, 600);
      expect(allLargest[1].name, 'session1.m4a');
      expect(allLargest[1].size, 500);

      final recOnly = await api.largestFiles(folder: 'audio-recordings');
      expect(recOnly.length, 2);
      expect(recOnly.every((e) => e.path.contains('audio-recordings')), isTrue);
      expect(recOnly[0].size, 500);
      expect(recOnly[1].size, 300);
    });

    test('suggestions and emptyTrash free space', () async {
      final s = await api.suggestions();
      expect(s.any((x) => x.kind == 'trash'), isTrue);
      final trashSugg = s.firstWhere((x) => x.kind == 'trash');
      expect(trashSugg.bytes, 150);
      expect(trashSugg.count, 1);

      final freed = await api.emptyTrash();
      expect(freed, 150);
      expect(api.isTrashed('sconl/old.tmp'), isFalse);
      expect(api.exists('sconl/old.tmp'), isFalse);
      final uAfter = await api.usage();
      expect(uAfter.trashBytes, 0);
    });
  });
}
