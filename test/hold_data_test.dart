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
}
