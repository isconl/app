// BH26101801: the hold file manager space against the fake server. Three tabs under the shared search, browse three
// levels, rename / delete with undo, upload with a name conflict kept both, search by name, and the unsorted tidy.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/data/hold_data.dart';
import 'package:isconl/data/hold_device.dart';
import 'package:isconl/data/hold_uploads.dart';
import 'package:isconl/theme.dart';
import 'package:isconl/ui/views/hold_space.dart';

import 'support/test_services.dart';

Uint8List _b(int n) => Uint8List.fromList(List.filled(n, 7));

void main() {
  late FakeHoldApi api;
  late UploadQueue queue;
  late FakeDevicePicker picker;

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 150));
    }
  }

  Future<void> pump(WidgetTester t, {List<PickedFile> device = const []}) async {
    t.view.physicalSize = const Size(900, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    api = FakeHoldApi();
    await api.mkdir('sconl/Crate');
    await api.mkdir('sconl/Crate/Media');
    await api.mkdir('sconl/Crate/Media/Audio');
    await api.mkdir('sconl/Crate/_unsorted');
    for (final e in {'sconl/Crate/Media/Audio/memo.m4a': 30, 'sconl/Crate/notes.txt': 12, 'sconl/Crate/_unsorted/IMG 7.JPG': 50}.entries) {
      final s = await api.beginUpload(e.key, e.value, '');
      await api.sendChunk(s.id, 0, _b(e.value));
      await api.finishUpload(s.id);
    }
    queue = UploadQueue(api, MemoryUploadStore(), chunkSize: 16, backoff: Duration.zero, sleep: (_) async {});
    picker = FakeDevicePicker(device);
    final services = (await t.runAsync(() => buildTestServices(ScriptedApi({}))))!;
    await t.pumpWidget(AppScope(services: services, child: MaterialApp(theme: buildTheme(), home: Scaffold(body: HoldSpace(api: api, queue: queue, picker: picker)))));
    await settle(t);
  }

  Future<void> end(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 11));
  }

  testWidgets('a search entry above exactly three tabs: Browse, Recent, Device', (t) async {
    await pump(t);
    expect(find.text('Search files in hold'), findsOneWidget);
    for (final l in ['Browse', 'Recent', 'Device']) {
      expect(find.text(l), findsOneWidget, reason: l);
    }
    expect(find.byKey(const Key('hold-archive')), findsOneWidget, reason: 'OneDrive is a read-only archive link, no longer the browsing surface');
    await end(t);
  });

  testWidgets('browse three levels down by tapping, breadcrumbs jump back to the top', (t) async {
    await pump(t);
    await t.tap(find.byKey(const Key('entry-sconl')));
    await settle(t);
    await t.tap(find.byKey(const Key('entry-Crate')));
    await settle(t);
    await t.tap(find.byKey(const Key('entry-Media')));
    await settle(t);
    expect(find.byKey(const Key('entry-Audio')), findsOneWidget);
    await t.tap(find.byKey(const Key('crumb-root')));
    await settle(t);
    expect(find.byKey(const Key('entry-sconl')), findsOneWidget);
    await end(t);
  });

  testWidgets('rename from the actions sheet, delete goes to trash and Undo restores it', (t) async {
    await pump(t);
    for (final n in ['sconl', 'Crate']) {
      await t.tap(find.byKey(Key('entry-$n')));
      await settle(t);
    }
    await t.tap(find.byKey(const Key('more-notes.txt')));
    await settle(t);
    await t.tap(find.byKey(const Key('act-rename')));
    await settle(t);
    await t.enterText(find.byKey(const Key('hold-name-field')), 'todo.txt');
    await t.tap(find.byKey(const Key('hold-name-ok')));
    await settle(t);
    expect(find.byKey(const Key('entry-todo.txt')), findsOneWidget);
    expect(api.exists('sconl/Crate/notes.txt'), isFalse);

    await t.tap(find.byKey(const Key('more-todo.txt')));
    await settle(t);
    await t.tap(find.byKey(const Key('act-delete')));
    await settle(t);
    expect(api.isTrashed('sconl/Crate/todo.txt'), isTrue);
    expect(find.byKey(const Key('entry-todo.txt')), findsNothing);
    await t.tap(find.text('Undo'));
    await settle(t);
    expect(api.isTrashed('sconl/Crate/todo.txt'), isFalse);
    expect(find.byKey(const Key('entry-todo.txt')), findsOneWidget);
    await end(t);
  });

  testWidgets('long-press selects, bulk delete takes everything selected to the trash', (t) async {
    await pump(t);
    for (final n in ['sconl', 'Crate']) {
      await t.tap(find.byKey(Key('entry-$n')));
      await settle(t);
    }
    await t.longPress(find.byKey(const Key('entry-notes.txt')));
    await settle(t);
    await t.tap(find.byKey(const Key('entry-Media')));
    await settle(t);
    expect(find.text('2 selected'), findsOneWidget);
    await t.tap(find.byKey(const Key('bulk-delete')));
    await settle(t);
    expect(api.isTrashed('sconl/Crate/notes.txt'), isTrue);
    expect(api.isTrashed('sconl/Crate/Media'), isTrue);
    await end(t);
  });

  testWidgets('upload from the device: the same name is kept as "name (2)", never overwritten', (t) async {
    await pump(t, device: [PickedFile('notes.txt', BytesSource(_b(40)))]);
    for (final n in ['sconl', 'Crate']) {
      await t.tap(find.byKey(Key('entry-$n')));
      await settle(t);
    }
    await t.tap(find.byTooltip('Upload from this device'));
    await t.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await queue.idle();
    });
    await settle(t);
    expect(api.bytesOf('sconl/Crate/notes.txt')!.length, 12, reason: 'the original is untouched');
    expect(api.bytesOf('sconl/Crate/notes (2).txt')!.length, 40);
    await end(t);
  });

  testWidgets('Recent shows the newest files; Device offers upload and download', (t) async {
    await pump(t);
    await t.tap(find.text('Recent'));
    await settle(t);
    expect(find.byKey(const Key('recent-notes.txt')), findsOneWidget);
    await t.tap(find.text('Device'));
    await settle(t);
    expect(find.byKey(const Key('device-upload')), findsOneWidget);
    expect(find.byKey(const Key('device-download')), findsOneWidget);
    await end(t);
  });

  testWidgets('search finds a file by name', (t) async {
    await pump(t);
    await t.tap(find.text('Search files in hold'));
    await settle(t);
    await t.enterText(find.byKey(const Key('space-search-field')), 'memo');
    await t.pump(const Duration(milliseconds: 400));
    await settle(t);
    expect(find.text('memo.m4a'), findsOneWidget);
    await end(t);
  });

  testWidgets('an _unsorted folder offers a tidy: the suggestion is shown, nothing moves until it is accepted', (t) async {
    await pump(t);
    for (final n in ['sconl', 'Crate', '_unsorted']) {
      await t.tap(find.byKey(Key('entry-$n')));
      await settle(t);
    }
    expect(find.byKey(const Key('hold-tidy')), findsOneWidget);
    await t.tap(find.byKey(const Key('hold-tidy')));
    await settle(t);
    expect(find.byKey(const Key('tidy-IMG 7.JPG')), findsOneWidget);
    expect(api.exists('sconl/Crate/_unsorted/IMG 7.JPG'), isTrue, reason: 'not moved yet');
    await t.tap(find.byKey(const Key('tidy-accept-IMG 7.JPG')));
    await settle(t);
    expect(api.exists('sconl/Crate/_unsorted/IMG 7.JPG'), isFalse);
    expect(api.search('img_7').then((r) => r.single.path), completion(contains('Media/Photos/')));
    await end(t);
  });
}
