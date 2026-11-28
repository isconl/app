import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/services/small_actions.dart';
import 'package:isconl/ui/widgets/entry_actions.dart';
import 'package:isconl/ui/widgets/file_actions.dart';

class FakeSmall implements SmallActionsApi {
  final calls = <String>[];
  Object? failWith;
  void _t() {
    if (failWith != null) throw failWith!;
  }

  @override
  Future<void> journalUpdate(String id, String body) async {
    _t();
    calls.add('j-update:$id:$body');
  }

  @override
  Future<void> journalDelete(String id) async => calls.add('j-del:$id');
  @override
  Future<String> journalReflect(String id) async => 'A calm day.';
  @override
  Future<({String review, String stats})> journalReview() async => (review: 'A good month.', stats: '12 entries, mood 7, energy 6');
  @override
  Future<void> ideaDelete(String id) async => calls.add('i-del:$id');
  @override
  Future<String> ideaRefine(String id) async => 'Sharper.';
  @override
  Future<String> ideasReview() async => 'The pipeline reads well.';
  @override
  Future<void> mkdir(String parentPath, String name) async => calls.add('mkdir:$parentPath:$name');
  @override
  Future<void> rename(String itemId, String newName) async => calls.add('rename:$itemId:$newName');
  @override
  Future<void> move(String itemId, String toPath) async => calls.add('move:$itemId:$toPath');
  @override
  Future<void> deleteItem(String itemId) async => calls.add('del:$itemId');
  @override
  Future<void> uploadText(String folderPath, String fileName, String content) async => calls.add('upload:$folderPath:$fileName');
  @override
  Future<({String filename, List<int> bytes})> download(String itemId, String name) async => (filename: name, bytes: Uint8List(1));
}

Widget host(Widget w) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: w)));

void main() {
  test('names OneDrive refuses', () {
    expect(HubSmallActionsApi.badName('a/b'), true);
    expect(HubSmallActionsApi.badName('what?'), true);
    expect(HubSmallActionsApi.badName('  '), true);
    expect(HubSmallActionsApi.badName('Plan 2026.md'), false);
  });

  testWidgets('journal entry: delete asks first; reflect shows the note; edit saves', (t) async {
    final api = FakeSmall();
    var deleted = 0, changed = 0;
    await t.pumpWidget(host(EntryActions(kind: 'journal', id: 'j1', body: 'old', api: api, onDeleted: () => deleted++, onChanged: () => changed++)));
    await t.tap(find.byKey(const Key('entry-delete')));
    await t.pumpAndSettle();
    expect(find.text('Delete this entry?'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(api.calls, isEmpty);
    await t.tap(find.byKey(const Key('entry-reflect')));
    await t.pumpAndSettle();
    expect(find.text('A calm day.'), findsOneWidget);
    await t.tap(find.byKey(const Key('entry-edit')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('entry-edit-text')), 'new words');
    await t.tap(find.byKey(const Key('entry-edit-save')));
    await t.pumpAndSettle();
    expect(api.calls, ['j-update:j1:new words']);
    expect(changed, 1);
    await t.tap(find.byKey(const Key('entry-delete')));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Delete'));
    await t.pumpAndSettle();
    expect(api.calls.last, 'j-del:j1');
    expect(deleted, 1);
  });

  testWidgets('idea: sharpen, and no Edit button; failure shows a sentence', (t) async {
    final api = FakeSmall();
    await t.pumpWidget(host(EntryActions(kind: 'idea', id: 'i1', body: 'x', api: api)));
    expect(find.byKey(const Key('entry-edit')), findsNothing);
    await t.tap(find.byKey(const Key('entry-reflect')));
    await t.pumpAndSettle();
    expect(find.text('Sharper.'), findsOneWidget);
    await t.tap(find.byKey(const Key('entry-delete')));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Delete'));
    await t.pumpAndSettle();
    expect(api.calls, ['i-del:i1']);
  });

  testWidgets('review sheet shows the read and the stats', (t) async {
    await t.pumpWidget(host(SizedBox(height: 400, child: ReviewSheet(kind: 'journal', api: FakeSmall()))));
    await t.pumpAndSettle();
    expect(find.text('12 entries, mood 7, energy 6'), findsOneWidget);
    expect(find.textContaining('A good month.'), findsOneWidget);
  });

  testWidgets('file: delete says recycle bin and needs the tap; rename and move go through', (t) async {
    final api = FakeSmall();
    var changed = 0;
    await t.pumpWidget(host(FileActions(itemId: 'f1', name: 'plan.md', api: api, onChanged: () => changed++)));
    await t.tap(find.byKey(const Key('file-delete')));
    await t.pumpAndSettle();
    expect(find.textContaining('recycle bin'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(api.calls, isEmpty);
    await t.tap(find.byKey(const Key('file-rename')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('ask-text')), 'plan2.md');
    await t.tap(find.byKey(const Key('ask-ok')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('file-move')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('ask-text')), 'Work/Plans');
    await t.tap(find.byKey(const Key('ask-ok')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('file-delete')));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Delete'));
    await t.pumpAndSettle();
    expect(api.calls, ['rename:f1:plan2.md', 'move:f1:Work/Plans', 'del:f1']);
    expect(changed, 3);
  });

  testWidgets('folder toolbar: a bad folder name is refused before anything is sent', (t) async {
    final api = FakeSmall();
    await t.pumpWidget(host(FolderToolbar(path: 'root', api: api)));
    await t.tap(find.byKey(const Key('new-folder')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('ask-text')), 'a/b');
    await t.tap(find.byKey(const Key('ask-ok')));
    await t.pumpAndSettle();
    expect(api.calls, isEmpty);
    expect(find.byKey(const Key('toolbar-message')), findsOneWidget);
    await t.tap(find.byKey(const Key('new-folder')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('ask-text')), 'Receipts');
    await t.tap(find.byKey(const Key('ask-ok')));
    await t.pumpAndSettle();
    expect(api.calls, ['mkdir:root:Receipts']);
  });
}
