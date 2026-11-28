import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/services/platform.dart' show SharedFile;
import 'package:isconl/services/share_intake.dart';
import 'package:isconl/ui/widgets/share_sheet.dart';

class FakeSink implements ShareSink {
  final calls = <String>[];
  bool ok = true;
  @override
  Future<bool> addInbox({required String body, String title = ''}) async {
    calls.add('inbox:$title|$body');
    return ok;
  }

  @override
  Future<bool> addTask({required String title}) async {
    calls.add('task:$title');
    return ok;
  }

  @override
  Future<bool> addJournal({required String body}) async {
    calls.add('journal:$body');
    return ok;
  }

  @override
  Future<String> keepFile(SharedFile f) async {
    calls.add('keep:${f.name}');
    return '/kept/${f.name}';
  }
}

const photo = SharedFile(name: 'IMG_1.jpg', mime: 'image/jpeg', size: 2 * 1024 * 1024, path: '/cache/IMG_1.jpg');
const pdf = SharedFile(name: 'plan.pdf', mime: 'application/pdf', size: 90 * 1024, path: '/cache/plan.pdf');
const huge = SharedFile(name: 'film.mp4', mime: 'video/mp4', size: 90 * 1024 * 1024);

void main() {
  test('a link is recognised, text is not, and the preview is the host', () {
    expect(const ShareItem.text('https://www.example.com/a/b?x=1').link, isNotNull);
    expect(const ShareItem.text('https://www.example.com/a/b').preview, 'example.com');
    expect(const ShareItem.text('see https://x.com now').link, isNull);
    expect(const ShareItem.text('hello there').preview, 'hello there');
    expect(const ShareItem.files([photo, pdf]).preview, '2 files, 2.1 MB');
  });

  test('Files is offered for files only', () {
    expect(destinationsFor(const ShareItem.text('hi')), [ShareDestination.inbox, ShareDestination.task, ShareDestination.journal]);
    expect(destinationsFor(const ShareItem.files([photo])), ShareDestination.values);
  });

  test('the body is the note first, then what was shared', () {
    expect(composeBody(const ShareItem.text('https://a.io'), 'read this'), 'read this\n\nhttps://a.io');
    expect(composeBody(const ShareItem.files([pdf]), ''), 'Shared file: plan.pdf (application/pdf, 90 KB)');
    expect(composeTaskTitle(const ShareItem.text('https://a.io'), ''), 'Read a.io');
    expect(composeTaskTitle(const ShareItem.files([photo, pdf]), ''), 'Look at IMG_1.jpg and 1 more');
    expect(composeTaskTitle(const ShareItem.text('x'), 'a' * 120).length, 90);
  });

  test('a text share saves to the chosen place and keeps no file', () async {
    final s = FakeSink();
    final r = await saveShare(s, const ShareItem.text('https://a.io'), ShareDestination.task, 'later');
    expect(r.ok, true);
    expect(s.calls, ['task:later']);
  });

  test('files are kept on the phone and the message says the hub cannot take them yet', () async {
    final s = FakeSink();
    final r = await saveShare(s, const ShareItem.files([photo, huge]), ShareDestination.files, 'receipt');
    expect(r.ok, true);
    expect(s.calls.first, 'keep:IMG_1.jpg');
    expect(s.calls.where((c) => c.startsWith('keep:')).length, 1, reason: 'the 90 MB file is not copied');
    expect(s.calls.last, contains('too big to keep'));
    expect(r.message, contains('kept on this phone'));
  });

  test('only oversize files: nothing is saved', () async {
    final s = FakeSink();
    final r = await saveShare(s, const ShareItem.files([huge]), ShareDestination.inbox, '');
    expect(r.ok, false);
    expect(s.calls, isEmpty);
  });

  test('a failed save reports it', () async {
    final s = FakeSink()..ok = false;
    final r = await saveShare(s, const ShareItem.text('x'), ShareDestination.inbox, '');
    expect(r.ok, false);
  });

  testWidgets('the sheet saves only on Save, to the chosen destination, with the note', (t) async {
    final s = FakeSink();
    var done = 0;
    await t.pumpWidget(MaterialApp(home: Scaffold(body: ShareSheet(item: const ShareItem.text('https://a.io'), sink: s, onDone: () => done++))));
    expect(s.calls, isEmpty);
    expect(find.byKey(const Key('dest-files')), findsNothing);
    await t.tap(find.byKey(const Key('dest-journal')));
    await t.enterText(find.byKey(const Key('share-note')), 'for tonight');
    await t.tap(find.byKey(const Key('share-save')));
    await t.pumpAndSettle();
    expect(s.calls, ['journal:for tonight\n\nhttps://a.io']);
    expect(done, 1);
    expect(find.byKey(const Key('share-message')), findsOneWidget);
  });
}
