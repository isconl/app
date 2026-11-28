import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/services/task_delivery.dart';
import 'package:isconl/ui/widgets/task_delivery_section.dart';

class FakeTasks implements TaskDeliveryClient {
  final calls = <String>[];
  List<Recipient> people = const [Recipient('Alex Doe', 'Head of ops'), Recipient('Sam Roe', 'CEO')];
  TaskDocs docs = const TaskDocs(
    all: [
      Deliverable(name: 'week_review.docx', source: 'linked', bytes: 20480, webUrl: 'https://od.test/x', onedrive: true),
      Deliverable(name: 'maybe.docx', source: 'found', onedrive: false),
    ],
    noteText: 'Hello, here is the review.',
    dead: 1,
  );
  TaskCoverage? cov = const TaskCoverage(covered: false, gaps: ['no deliverable']);
  bool failLoad = false;

  @override
  Future<List<Recipient>> recipients() async {
    if (failLoad) throw Exception('down');
    return people;
  }

  @override
  Future<TaskDocs> deliverables(String id) async => docs;
  @override
  Future<String> note(String id) async => 'Subject\n\nBody';
  @override
  Future<TaskCoverage?> coverage(String id) async => cov;
  @override
  Future<String> provision(String id) async {
    calls.add('provision:$id');
    cov = const TaskCoverage(covered: true);
    return 'x.docx';
  }

  @override
  Future<String> relink() async {
    calls.add('relink');
    return '2 tasks relinked, 1 adopted, 0 dead links dropped';
  }

  @override
  Future<void> setDelivery(String id, String d) async => calls.add('delivery:$id:$d');
  @override
  Future<void> recordSend(String id, {required String sentTo, required String sentVia, required String sentAt, String note = ''}) async =>
      calls.add('send:$id:$sentTo:$sentVia:$sentAt:$note');
}

Widget host(FakeTasks c, {Map<String, dynamic>? task, bool online = true, List<String>? opened}) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: TaskDeliverySection(
            taskId: 'T1',
            task: task ?? {'STATUS': 'review'},
            client: c,
            online: online,
            openUrl: (u) async => opened?.add(u),
            today: () => '2026-10-15',
          ),
        ),
      ),
    );

void main() {
  setUp(() {});

  testWidgets('shows delivery state, note, recipients, coverage and deliverables', (t) async {
    await t.binding.setSurfaceSize(const Size(420, 2400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(host(FakeTasks()));
    await t.pumpAndSettle();
    expect(find.text('Drafted'), findsOneWidget); // STATUS review reads as drafted, like the console
    expect(find.text('Hello, here is the review.'), findsOneWidget);
    expect(find.text('Alex Doe, Head of ops'), findsOneWidget);
    expect(find.textContaining('Missing: no deliverable'), findsOneWidget);
    expect(find.text('week_review.docx'), findsOneWidget);
    expect(find.textContaining('attached, 20 KB'), findsOneWidget);
    expect(find.textContaining('best guess, not on OneDrive yet'), findsOneWidget);
    expect(find.textContaining('1 linked file no longer on disk'), findsOneWidget);
  });

  testWidgets('Provision creates the deliverable and coverage turns green', (t) async {
    await t.binding.setSurfaceSize(const Size(420, 2400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final c = FakeTasks();
    await t.pumpWidget(host(c));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('provision')));
    await t.pumpAndSettle();
    expect(c.calls, ['provision:T1']);
    expect(find.textContaining('Covered: it has its deliverable'), findsOneWidget);
    expect(find.byKey(const Key('provision')), findsNothing);
  });

  testWidgets('Relink reports what it did', (t) async {
    await t.binding.setSurfaceSize(const Size(420, 2400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final c = FakeTasks();
    await t.pumpWidget(host(c));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('relink')));
    await t.pumpAndSettle();
    expect(c.calls, ['relink']);
    expect(find.text('2 tasks relinked, 1 adopted, 0 dead links dropped'), findsOneWidget);
  });

  testWidgets('Mark reviewed writes and updates the badge', (t) async {
    await t.binding.setSurfaceSize(const Size(420, 2400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final c = FakeTasks();
    await t.pumpWidget(host(c));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('mark-reviewed')));
    await t.pumpAndSettle();
    expect(c.calls, ['delivery:T1:reviewed']);
    expect(find.text('Reviewed'), findsOneWidget);
    expect(find.byKey(const Key('mark-reviewed')), findsNothing);
  });

  testWidgets('recording a send shows the recipients first and sends nothing until the confirm', (t) async {
    await t.binding.setSurfaceSize(const Size(420, 2400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final c = FakeTasks();
    await t.pumpWidget(host(c));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('record-send')));
    await t.pumpAndSettle();
    expect(find.text('Record the send'), findsOneWidget);
    expect(find.textContaining('It does not send anything'), findsOneWidget);
    expect(find.text('Record sent to Alex Doe'), findsOneWidget);
    expect(c.calls, isEmpty); // the dialog alone changed nothing
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(c.calls, isEmpty);
  });

  testWidgets('confirming records who, how, when and the note, and the task reads Sent', (t) async {
    await t.binding.setSurfaceSize(const Size(420, 2400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final c = FakeTasks();
    await t.pumpWidget(host(c));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('record-send')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('send-to')));
    await t.pumpAndSettle();
    await t.tap(find.text('Sam Roe (CEO)').last);
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('send-note')), 'waiting on sign-off');
    await t.tap(find.byKey(const Key('send-confirm')));
    await t.pumpAndSettle();
    expect(c.calls, ['send:T1:Sam Roe:email:2026-10-15:waiting on sign-off']);
    expect(find.text('Sent'), findsOneWidget);
    expect(find.byKey(const Key('delivery-sent')), findsOneWidget);
    expect(find.textContaining('Still open until you close it'), findsOneWidget);
  });

  testWidgets('offline, every write is disabled and the reason is shown', (t) async {
    await t.binding.setSurfaceSize(const Size(420, 2400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final c = FakeTasks();
    await t.pumpWidget(host(c, online: false));
    await t.pumpAndSettle();
    expect(t.widget<FilledButton>(find.byKey(const Key('record-send'))).onPressed, isNull);
    expect(t.widget<OutlinedButton>(find.byKey(const Key('relink'))).onPressed, isNull);
    expect(t.widget<OutlinedButton>(find.byKey(const Key('provision'))).onPressed, isNull);
    expect(find.textContaining('Offline'), findsOneWidget);
  });

  testWidgets('a sent task offers Edit the record and Not sent after all', (t) async {
    await t.binding.setSurfaceSize(const Size(420, 2400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final c = FakeTasks();
    await t.pumpWidget(host(c, task: {'DELIVERY': 'sent', 'SENT_TO': 'Alex Doe', 'SENT_VIA': 'email', 'SENT_AT': '2026-10-10T09:00:00Z', 'DELIVERY_NOTE': 'sent the pdf'}));
    await t.pumpAndSettle();
    expect(find.textContaining('Sent to Alex Doe via email on 2026-10-10'), findsOneWidget);
    expect(find.text('Edit the record'), findsOneWidget);
    await t.tap(find.byKey(const Key('not-sent')));
    await t.pumpAndSettle();
    expect(c.calls, ['delivery:T1:reviewed']);
    expect(find.text('Reviewed'), findsOneWidget);
  });

  testWidgets('a deliverable opens by its OneDrive link', (t) async {
    await t.binding.setSurfaceSize(const Size(420, 2400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final opened = <String>[];
    await t.pumpWidget(host(FakeTasks(), opened: opened));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('open-week_review.docx')));
    expect(opened, ['https://od.test/x']);
  });

  testWidgets('a failed load says so instead of showing an empty page', (t) async {
    await t.binding.setSurfaceSize(const Size(420, 2400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final c = FakeTasks()..failLoad = true;
    await t.pumpWidget(host(c));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('delivery-failed')), findsOneWidget);
  });

  test('delivery vocabulary matches the console', () {
    expect(deliveryStateOf({'DELIVERY': 'reviewed'}), 'reviewed');
    expect(deliveryStateOf({'DELIVERY': '-', 'STATUS': 'review'}), 'drafted');
    expect(deliveryStateOf({'STATUS': 'todo'}), '-');
    final d = HubTaskDeliveryClient.parseDeliverable({'name': 'a', 'source': 'found', 'onedrive': false, 'bytes': 5});
    expect(d.isGuess, isTrue);
    expect(d.onedrive, isFalse);
  });
}
