import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/services/circle_depth.dart';
import 'package:isconl/services/circle_pickers.dart';
import 'package:isconl/theme.dart';
import 'package:isconl/ui/widgets/circle_depth_widgets.dart';

class FakeCircle implements CircleDepthApi {
  final calls = <String>[];
  ReachoutState reachoutState = const ReachoutState(reachout: Reachout(urgency: 'high', why: 'Due now', channel: 'whatsapp', intent: 'Check in', body: 'Hi Amina, how are you?'));
  List<TagCount> tagList = const [TagCount('mentor', 3), TagCount('alumni', 2), TagCount('investor', 1)];
  WhoCan whoCanResult = const WhoCan();
  GalleryFilters filters = const GalleryFilters(
    people: [GalleryPerson('p1', 'Amina', ['family']), GalleryPerson('p2', 'Joe', ['work'])],
    tags: ['family', 'work'],
    events: ['Wedding 2026'],
  );
  List<GalleryItem> items = const [GalleryItem(id: 'i1', name: 'a.jpg', downloadUrl: 'https://x/a.jpg'), GalleryItem(id: 'i2', name: 'b.mp4', downloadUrl: 'https://x/b.mp4')];
  ChatImportResult? importResult;
  Object? fail;
  String? analysisText;

  void _f() {
    if (fail != null) throw fail!;
  }

  @override
  Future<ReachoutState> reachout(String id) async {
    calls.add('reachout:$id');
    return reachoutState;
  }

  @override
  Future<Reachout> rewriteReachout(String id, {String intent = ''}) async {
    _f();
    calls.add('rewrite:$id:$intent');
    return Reachout(urgency: 'high', channel: 'whatsapp', intent: intent, body: 'Rewritten for $intent');
  }

  @override
  Future<void> logSent(String id, {required String channel, required String summary}) async {
    _f();
    calls.add('sent:$id:$channel:$summary');
  }

  @override
  Future<String?> analysis() async => analysisText;
  @override
  Future<WhoCan> whoCan(String q) async {
    calls.add('whocan:$q');
    return whoCanResult;
  }

  @override
  Future<List<TagCount>> tags() async => tagList;
  @override
  Future<void> addTag(String id, String tag) async {
    _f();
    calls.add('addTag:$id:$tag');
  }

  @override
  Future<void> removeTag(String id, String tag) async {
    _f();
    calls.add('removeTag:$id:$tag');
  }

  @override
  Future<void> renameTag(String from, String to) async {
    _f();
    calls.add('rename:$from:$to');
    tagList = [for (final t in tagList) t.tag == from ? TagCount(to, t.count) : t];
  }

  @override
  Future<void> mergeTags(List<String> s, String into) async {
    _f();
    calls.add('merge:${s.join(',')}:$into');
  }

  @override
  Future<void> deleteTag(String tag) async {
    _f();
    calls.add('delete:$tag');
    tagList = [for (final t in tagList) if (t.tag != tag) t];
  }

  @override
  Future<GalleryFilters> galleryFilters() async => filters;
  @override
  Future<List<GalleryItem>> galleryItems({required String scope, required String id}) async {
    calls.add('items:$scope:$id');
    return items;
  }

  @override
  Future<void> galleryUpload({required String scope, required String id, required String kind, required String fileName, required Uint8List bytes, String contentType = ''}) async {
    _f();
    calls.add('upload:$scope:$id:$kind:$fileName:${bytes.length}:$contentType');
  }

  @override
  Future<ChatImportResult> importChat(String fileName, Uint8List bytes) async {
    _f();
    calls.add('import:$fileName:${bytes.length}');
    return importResult!;
  }

  @override
  Future<({String name, int messages})> addSender({required String importId, required String speaker, required String name, required String circle, String role = '', String cadence = ''}) async {
    _f();
    calls.add('addSender:$importId:$speaker:$name:$circle:$role:$cadence');
    return (name: name, messages: 12);
  }

  @override
  Future<void> createFolder(String personId, String folder) async {
    _f();
    calls.add('folder:$personId:$folder');
  }
}

Widget host(Widget w) => MaterialApp(theme: buildTheme(), home: Scaffold(body: w));
Widget hostScroll(Widget w) => MaterialApp(theme: buildTheme(), home: Scaffold(body: SingleChildScrollView(child: w)));

void main() {
  group('pure helpers', () {
    test('the folder path matches the console', () {
      expect(circleFolderFor(name: 'Amina Wanjiru', circle: 'family', met: '2019-03-02'), 'Sconl/Circle/Family/2019-amina-wanjiru');
      expect(circleFolderFor(name: 'Joe', circle: 'social', met: '-'), 'Sconl/Circle/Social/Friends/2026-joe');
      expect(circleFolderFor(name: '!!!', circle: 'professional'), 'Sconl/Circle/Professional/2026-contact');
    });

    test('the sent summary is the first line actually sent, trimmed', () {
      expect(sentSummary('\n\nHello there\nsecond line'), 'Sent: Hello there');
      expect(sentSummary(''), 'Sent: the drafted message');
      expect(sentSummary('x' * 200).length, 'Sent: '.length + 90);
    });

    test('gallery filters narrow people by tag', () {
      final f = FakeCircle().filters;
      expect(f.peopleWith('family').map((p) => p.id), ['p1']);
      expect(f.peopleWith('').length, 2);
      expect(const GalleryItem(id: '1', name: 'X.MOV').isVideo, isTrue);
      expect(const GalleryItem(id: '1', name: 'x.jpg').isVideo, isFalse);
    });
  });

  group('ReachoutCard', () {
    testWidgets('shows the written message and nothing is sent by showing it', (t) async {
      final api = FakeCircle();
      await t.pumpWidget(hostScroll(ReachoutCard(personId: 'p1', fallbackChannel: 'call', api: api, pollStale: false)));
      await t.pumpAndSettle();
      expect(t.widget<TextField>(find.byKey(const Key('reachout-text'))).controller!.text, 'Hi Amina, how are you?');
      expect(find.text('high priority'), findsOneWidget);
      expect(find.textContaining('The angle: Check in'), findsOneWidget);
      expect(api.calls, ['reachout:p1']);
    });

    testWidgets('Copy copies what the reader edited', (t) async {
      String? copied;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async {
        if (c.method == 'Clipboard.setData') copied = (c.arguments as Map)['text'] as String;
        return null;
      });
      addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await t.pumpWidget(hostScroll(ReachoutCard(personId: 'p1', fallbackChannel: '', api: FakeCircle(), pollStale: false)));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('reachout-text')), 'My version');
      await t.tap(find.byKey(const Key('reachout-copy')));
      await t.pumpAndSettle();
      expect(copied, 'My version');
    });

    testWidgets('Sent it logs a touch with what was actually sent', (t) async {
      final api = FakeCircle();
      var logged = 0;
      await t.pumpWidget(hostScroll(ReachoutCard(personId: 'p1', fallbackChannel: 'call', api: api, onLogged: () => logged++, pollStale: false)));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('reachout-sent')));
      await t.pumpAndSettle();
      expect(api.calls, contains('sent:p1:whatsapp:Sent: Hi Amina, how are you?'));
      expect(logged, 1);
    });

    testWidgets('Different words and a new angle rewrite; an empty angle is refused', (t) async {
      final api = FakeCircle();
      await t.pumpWidget(hostScroll(ReachoutCard(personId: 'p1', fallbackChannel: '', api: api, pollStale: false)));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('reachout-regen')));
      await t.pumpAndSettle();
      expect(api.calls.last, 'rewrite:p1:');
      await t.tap(find.byKey(const Key('reachout-rewrite')));
      await t.pumpAndSettle();
      expect(find.text('Say what the message should achieve.'), findsOneWidget);
      await t.enterText(find.byKey(const Key('reachout-angle')), 'ask for an intro');
      await t.tap(find.byKey(const Key('reachout-rewrite')));
      await t.pumpAndSettle();
      expect(api.calls.last, 'rewrite:p1:ask for an intro');
      expect(t.widget<TextField>(find.byKey(const Key('reachout-text'))).controller!.text, 'Rewritten for ask for an intro');
    });

    testWidgets('no message yet says so; a stale draft says it is being rewritten', (t) async {
      final api = FakeCircle()..reachoutState = const ReachoutState(error: 'No message yet.');
      await t.pumpWidget(hostScroll(ReachoutCard(personId: 'p1', fallbackChannel: '', api: api, pollStale: false)));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('reachout-none')), findsOneWidget);
      final stale = FakeCircle()..reachoutState = const ReachoutState(reachout: Reachout(body: 'old'), stale: true);
      await t.pumpWidget(hostScroll(ReachoutCard(key: const Key('s'), personId: 'p2', fallbackChannel: '', api: stale, pollStale: false)));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('reachout-stale')), findsOneWidget);
    });
  });

  group('tags', () {
    testWidgets('a person can add and remove tags', (t) async {
      final api = FakeCircle();
      var changed = 0;
      await t.pumpWidget(hostScroll(PersonTagsCard(personId: 'p1', tags: const ['mentor'], api: api, onChanged: () => changed++)));
      expect(find.byKey(const Key('chip-mentor')), findsOneWidget);
      await t.tap(find.byKey(const Key('tag-add')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('text-dialog-field')), 'alumni');
      await t.tap(find.byKey(const Key('text-dialog-ok')));
      await t.pumpAndSettle();
      expect(api.calls, ['addTag:p1:alumni']);
      expect(find.byKey(const Key('chip-alumni')), findsOneWidget);
      await t.tap(find.byTooltip('Remove mentor'));
      await t.pumpAndSettle();
      expect(api.calls.last, 'removeTag:p1:mentor');
      expect(find.byKey(const Key('chip-mentor')), findsNothing);
      expect(changed, 2);
    });

    testWidgets('the manager lists tags with counts and renames one', (t) async {
      final api = FakeCircle();
      await t.pumpWidget(host(TagsManager(api: api)));
      await t.pumpAndSettle();
      expect(t.widget<Text>(find.byKey(const Key('count-mentor'))).data, '3');
      await t.tap(find.byKey(const Key('tag-menu-mentor')));
      await t.pumpAndSettle();
      await t.tap(find.text('Rename'));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('text-dialog-field')), 'coach');
      await t.tap(find.byKey(const Key('text-dialog-ok')));
      await t.pumpAndSettle();
      expect(api.calls, ['rename:mentor:coach']);
      expect(find.byKey(const Key('tag-coach')), findsOneWidget);
    });

    testWidgets('merge shows the affected count before it applies', (t) async {
      final api = FakeCircle();
      await t.pumpWidget(host(TagsManager(api: api)));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('tag-menu-mentor')));
      await t.pumpAndSettle();
      await t.tap(find.text('Merge into another tag'));
      await t.pumpAndSettle();
      expect(find.textContaining('3 contacts carrying "mentor" will carry "alumni" instead.'), findsOneWidget);
      expect(api.calls, isEmpty); // nothing applied yet
      await t.tap(find.byKey(const Key('merge-confirm')));
      await t.pumpAndSettle();
      expect(api.calls, ['merge:mentor:alumni']);
    });

    testWidgets('delete asks first and says how many contacts lose the tag', (t) async {
      final api = FakeCircle();
      await t.pumpWidget(host(TagsManager(api: api)));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('tag-menu-investor')));
      await t.pumpAndSettle();
      await t.tap(find.text('Delete'));
      await t.pumpAndSettle();
      expect(find.textContaining('Removes it from 1 contact.'), findsOneWidget);
      await t.tap(find.text('Keep it'));
      await t.pumpAndSettle();
      expect(api.calls, isEmpty);
      await t.tap(find.byKey(const Key('tag-menu-investor')));
      await t.pumpAndSettle();
      await t.tap(find.text('Delete'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('tag-delete-confirm')));
      await t.pumpAndSettle();
      expect(api.calls, ['delete:investor']);
      expect(find.byKey(const Key('tag-investor')), findsNothing);
    });

    testWidgets('a refusal from the agent is shown', (t) async {
      final api = FakeCircle()..fail = Exception('Tag exists');
      await t.pumpWidget(host(TagsManager(api: api)));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('tag-menu-mentor')));
      await t.pumpAndSettle();
      await t.tap(find.text('Rename'));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('text-dialog-field')), 'alumni');
      await t.tap(find.byKey(const Key('text-dialog-ok')));
      await t.pumpAndSettle();
      expect(find.textContaining('Tag exists'), findsOneWidget);
    });
  });

  group('who can', () {
    testWidgets('direct matches with evidence, warm paths, and the empty case', (t) async {
      final api = FakeCircle()
        ..whoCanResult = const WhoCan(
          direct: [WhoCanPerson(id: 'a', name: 'Amina', role: 'CFO', why: ['Raised a seed round'])],
          adjacent: [WhoCanPerson(id: 'b', name: 'Joe', note: 'Knows two investors')],
        );
      final opened = <String>[];
      await t.pumpWidget(host(WhoCanView(api: api, onOpen: opened.add)));
      await t.enterText(find.byKey(const Key('whocan-q')), 'investor');
      await t.tap(find.byKey(const Key('whocan-go')));
      await t.pumpAndSettle();
      expect(find.text('Amina'), findsOneWidget);
      expect(find.textContaining('Raised a seed round'), findsOneWidget);
      expect(find.text('WARM PATHS'), findsOneWidget);
      await t.tap(find.byKey(const Key('warm-b')));
      expect(opened, ['b']);
      api.whoCanResult = const WhoCan();
      await t.tap(find.byKey(const Key('whocan-go')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('whocan-none')), findsOneWidget);
    });
  });

  group('gallery', () {
    testWidgets('choose a person (narrowed by tag), see their items, upload from the camera roll', (t) async {
      final api = FakeCircle();
      await t.binding.setSurfaceSize(const Size(420, 1400));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(host(CircleGalleryView(
        api: api,
        pick: () async => PickedBytes('new.jpg', Uint8List.fromList([1, 2, 3]), contentType: 'image/jpeg'),
      )));
      await t.pumpAndSettle();
      expect(find.text('Pick a person to see their gallery.'), findsOneWidget);
      await t.tap(find.byKey(const Key('gallery-tag')));
      await t.pumpAndSettle();
      await t.tap(find.text('family').last);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('gallery-person')));
      await t.pumpAndSettle();
      expect(find.text('Joe'), findsNothing); // narrowed out by the tag
      await t.tap(find.text('Amina').last);
      await t.pumpAndSettle();
      expect(api.calls, ['items:person:p1']);
      expect(find.byKey(const Key('item-i1')), findsOneWidget);
      await t.tap(find.byKey(const Key('gallery-upload')));
      await t.pumpAndSettle();
      expect(api.calls, contains('upload:person:p1:photos:new.jpg:3:image/jpeg'));
      expect(find.text('new.jpg uploaded.'), findsOneWidget);
    });

    testWidgets('by event, a video opens by link, and an upload failure is shown', (t) async {
      final api = FakeCircle()..fail = Exception('Quota');
      final opened = <String>[];
      await t.binding.setSurfaceSize(const Size(420, 1400));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(host(CircleGalleryView(api: api, openUrl: (u) async => opened.add(u), pick: () async => PickedBytes('v.mp4', Uint8List(2)))));
      await t.pumpAndSettle();
      await t.tap(find.text('By event'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('gallery-event')));
      await t.pumpAndSettle();
      await t.tap(find.text('Wedding 2026').last);
      await t.pumpAndSettle();
      expect(api.calls, ['items:event:Wedding 2026']);
      await t.tap(find.byKey(const Key('item-i2')));
      expect(opened, ['https://x/b.mp4']);
      await t.tap(find.byKey(const Key('gallery-upload')));
      await t.pumpAndSettle();
      expect(find.textContaining('Upload failed: Quota'), findsOneWidget);
    });
  });

  group('chat import', () {
    ChatImportResult result() => const ChatImportResult(
          importId: 'imp1',
          messages: 480,
          channel: 'whatsapp',
          filed: true,
          updated: [ChatUpdated(id: 'p1', name: 'Amina', note: 'Warm tone', messages: 300)],
          unmatched: [ChatUnmatched('Kevin', 40), ChatUnmatched('Zed', 3)],
        );

    testWidgets('imports a chat, shows who was recognised, and maps an unknown sender with a confirm step', (t) async {
      final api = FakeCircle()..importResult = result();
      final opened = <String>[];
      await t.binding.setSurfaceSize(const Size(420, 1400));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(host(ChatImportView(api: api, onOpen: opened.add, pick: () async => PickedBytes('chat.zip', Uint8List(50)))));
      await t.tap(find.byKey(const Key('chat-pick')));
      await t.pumpAndSettle();
      expect(api.calls, ['import:chat.zip:50']);
      expect(find.textContaining('480 messages read, whatsapp, filed to the vault'), findsOneWidget);
      expect(find.text('Amina'), findsOneWidget);
      await t.tap(find.byKey(const Key('updated-p1')));
      expect(opened, ['p1']);
      // The unknown sender: nothing is added until the form is confirmed.
      await t.tap(find.byKey(const Key('unmatched-Kevin')));
      await t.pumpAndSettle();
      expect(api.calls.length, 1);
      expect(t.widget<TextField>(find.byKey(const Key('sender-name'))).controller!.text, 'Kevin'); // pre-filled, suggest and confirm
      await t.enterText(find.byKey(const Key('sender-role')), 'cousin');
      await t.tap(find.byKey(const Key('sender-add')));
      await t.pumpAndSettle();
      expect(api.calls.last, 'addSender:imp1:Kevin:Kevin:social:cousin:');
      expect(find.byKey(const Key('unmatched-Kevin')), findsNothing);
      expect(find.byKey(const Key('unmatched-Zed')), findsOneWidget);
      expect(find.textContaining('Kevin joins the circle. 12 messages filed.'), findsOneWidget);
    });

    testWidgets('a file over 12 MB is refused before anything is sent', (t) async {
      final api = FakeCircle();
      await t.pumpWidget(host(ChatImportView(api: api, pick: () async => PickedBytes('big.zip', Uint8List(maxChatBytes + 1)))));
      await t.tap(find.byKey(const Key('chat-pick')));
      await t.pumpAndSettle();
      expect(find.textContaining('under 12 MB'), findsOneWidget);
      expect(api.calls, isEmpty);
    });

    testWidgets('nobody matching says so, and a failed import shows why', (t) async {
      final api = FakeCircle()..importResult = const ChatImportResult(importId: 'i', messages: 5);
      await t.pumpWidget(host(ChatImportView(api: api, pick: () async => PickedBytes('c.txt', Uint8List(5)))));
      await t.tap(find.byKey(const Key('chat-pick')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('chat-none')), findsOneWidget);
      api.fail = Exception('Unsupported export');
      await t.tap(find.byKey(const Key('chat-pick')));
      await t.pumpAndSettle();
      expect(find.textContaining('Unsupported export'), findsOneWidget);
    });
  });

  group('folder and analysis', () {
    testWidgets('the folder path is shown first, and Cancel creates nothing', (t) async {
      final api = FakeCircle();
      await t.pumpWidget(host(CreateFolderButton(personId: 'p1', name: 'Amina', circle: 'family', api: api)));
      await t.tap(find.byKey(const Key('create-folder')));
      await t.pumpAndSettle();
      expect(find.text('Sconl/Circle/Family/2026-amina'), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(api.calls, isEmpty);
      await t.tap(find.byKey(const Key('create-folder')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('folder-confirm')));
      await t.pumpAndSettle();
      expect(api.calls, ['folder:p1:Sconl/Circle/Family/2026-amina']);
    });

    testWidgets('the circle-wide read shows, or says it is being written', (t) async {
      await t.pumpWidget(host(CircleAnalysisView(api: FakeCircle()..analysisText = 'The circle is **warm**.')));
      await t.pumpAndSettle();
      expect(find.textContaining('warm'), findsWidgets);
      await t.pumpWidget(host(CircleAnalysisView(key: const Key('x'), api: FakeCircle())));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('analysis-none')), findsOneWidget);
    });
  });
}
