import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/api/client.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/services/parity9c.dart';
import 'package:isconl/ui/widgets/parity9c_widgets.dart';

import 'support/test_services.dart';

/// A fixture hub: answers by exact path, and records every call (method, path, body).
class FixtureHub extends ApiClient {
  FixtureHub(this.answers) : super(baseUrl: 'http://test', token: 'test');
  final Map<String, Object> answers;
  final List<(String, String, Object?)> calls = [];

  Object _answer(String path) {
    final key = path.split('?').first;
    final v = answers[path] ?? answers[key] ?? <String, dynamic>{};
    if (v is ApiException) throw v;
    return v;
  }

  @override
  Future<dynamic> getJson(String path, {bool cold = false, bool stored = true}) async {
    calls.add(('GET', path, null));
    return _answer(path);
  }

  @override
  Future<dynamic> postJson(String path, Map<String, dynamic> body, {bool cold = false}) async {
    calls.add(('POST', path, body));
    return _answer(path);
  }
}

class FakeApi implements Parity9cApi {
  final calls = <String>[];
  GooglePollState poll = GooglePollState.waiting;
  Object? sendError;

  @override
  Future<ChatExport> exportThread() async {
    calls.add('export');
    return const ChatExport(content: '# chat', filename: 'c.md');
  }

  @override
  Future<void> deleteThread(String id) async => calls.add('delete:$id');
  @override
  Future<GoogleDeviceCode> googleStart(String account) async {
    calls.add('gstart:$account');
    return const GoogleDeviceCode(userCode: 'ABCD-1234', verificationUri: 'https://g.test/device', deviceCode: 'dc', pollIntervalSec: 2);
  }

  @override
  Future<GooglePoll> googlePoll(String account, String deviceCode) async {
    calls.add('gpoll');
    return GooglePoll(poll);
  }

  @override
  Future<void> googleSend(GoogleDraft draft) async => calls.add('send:${draft.to}');
  @override
  Future<void> inboxBackfill() async => calls.add('backfill');
  @override
  Future<bool> inboxDelete(String id) async {
    calls.add('idelete:$id');
    return true;
  }

  @override
  Future<List<InboxIdentity>> inboxIdentities() async => const [InboxIdentity(label: 'a@b.c')];
  @override
  Future<void> setProjectUrl(String id, String url) async => calls.add('url:$id:$url');
  @override
  Future<SpacesDrift> spacesCheck() async => const SpacesDrift(walked: 9, missingLocally: ['Work/x']);
  @override
  Future<PersonaSplit> personaSplit({String? day}) async => PersonaSplit(day: day ?? '', lines: const ['work: 60%']);
  @override
  Future<VoiceCard> voiceCard() async => const VoiceCard(lines: ['formality: 3']);
  @override
  Future<bool> pinIsSet() async => true;
  @override
  Future<void> setPin(String pin) async => calls.add('setpin');
  @override
  Future<PinCheck> verifyPin(String pin) async {
    calls.add('verifypin');
    return const PinCheck(ok: false, error: 'Incorrect PIN.', attemptsLeft: 2);
  }
}

void main() {
  group('the repository against a fixture hub', () {
    test('chat: export asks for markdown and returns the content; delete posts the id', () async {
      final hub = FixtureHub({'/api/chat/export': {'success': true, 'content': '# t', 'filename': 'x.md'}, '/api/chat/thread/delete': {'success': true}});
      final api = HttpParity9cApi(hub);
      final e = await api.exportThread();
      expect((e.content, e.filename), ('# t', 'x.md'));
      await api.deleteThread('T1');
      expect(hub.calls[0].$3, {'format': 'md'});
      expect(hub.calls[1].$3, {'id': 'T1'});
    });

    test('chat: a refused export carries the hub error', () async {
      final api = HttpParity9cApi(FixtureHub({'/api/chat/export': {'success': false, 'error': 'nothing to export'}}));
      await expectLater(api.exportThread(), throwsA(isA<Parity9cException>().having((e) => e.message, 'm', 'nothing to export')));
    });

    test('google: start, poll waiting, poll connected, poll failed, and send', () async {
      final hub = FixtureHub({
        '/api/google/auth/start': {'ok': true, 'userCode': 'U-1', 'verificationUri': 'https://g.test', 'deviceCode': 'D', 'pollIntervalSec': 7},
        '/api/google/send': {'ok': true},
      });
      final api = HttpParity9cApi(hub);
      final c = await api.googleStart('default');
      expect((c.userCode, c.deviceCode, c.pollIntervalSec), ('U-1', 'D', 7));
      hub.answers['/api/google/auth/poll'] = {'waiting': true};
      expect((await api.googlePoll('default', 'D')).state, GooglePollState.waiting);
      hub.answers['/api/google/auth/poll'] = {'connected': true};
      expect((await api.googlePoll('default', 'D')).state, GooglePollState.connected);
      hub.answers['/api/google/auth/poll'] = {'error': 'access_denied'};
      final f = await api.googlePoll('default', 'D');
      expect((f.state, f.error), (GooglePollState.failed, 'access_denied'));
      await api.googleSend(const GoogleDraft(to: 'a@b.c', subject: 'Re: x', body: 'hi', personId: 'P1'));
      expect(hub.calls.last.$3, {'to': 'a@b.c', 'subject': 'Re: x', 'body': 'hi', 'personId': 'P1'});
    });

    test('inbox: backfill, delete, identities', () async {
      final hub = FixtureHub({
        '/api/inbox/backfill': {'ok': true},
        '/api/inbox/delete': {'success': true},
        '/api/inbox/identities': {'identities': [{'value': 'a@b.c', 'kind': 'email', 'person': 'Amina'}]},
      });
      final api = HttpParity9cApi(hub);
      await api.inboxBackfill();
      expect(await api.inboxDelete('M1'), isTrue);
      final ids = await api.inboxIdentities();
      expect((ids.single.label, ids.single.person), ('a@b.c', 'Amina'));
      hub.answers['/api/inbox/backfill'] = {'error': 'gmail not connected'};
      await expectLater(api.inboxBackfill(), throwsA(isA<Parity9cException>()));
    });

    test('projects url, spaces sync (read-only), persona split and voice card', () async {
      final hub = FixtureHub({
        '/api/projects/url': {'success': true},
        '/api/spaces/sync': {'success': true, 'walked': 12, 'missingLocally': ['a'], 'goneRemotely': []},
        '/api/identity/persona-split': {'day': 'Mon', 'work': '60%', 'notes': ['deep work first']},
        '/api/voice/card': {'lines': ['short sentences']},
      });
      final api = HttpParity9cApi(hub);
      await api.setProjectUrl('P1', 'https://x.test');
      final d = await api.spacesCheck();
      expect(d.inSync, isFalse);
      expect(d.line, contains('1 folder(s) not in the registry'));
      expect(hub.calls.firstWhere((c) => c.$2 == '/api/spaces/sync').$3, {'apply': false});
      final p = await api.personaSplit(day: 'Mon');
      expect(p.lines, containsAll(['work: 60%', 'deep work first']));
      expect(hub.calls.last.$2, '/api/identity/persona-split?day=Mon');
      expect((await api.voiceCard()).lines, ['short sentences']);
    });

    test('pin: set, status and verify with tries left', () async {
      final hub = FixtureHub({'/api/auth/set-pin': {'ok': true}, '/api/auth/methods': {'pin': true}, '/api/auth/pin': {'success': false, 'error': 'Incorrect PIN.', 'attemptsLeft': 1}});
      final api = HttpParity9cApi(hub);
      await api.setPin('123456');
      expect(await api.pinIsSet(), isTrue);
      final r = await api.verifyPin('0000');
      expect(r.ok, isFalse);
      expect(r.message, 'Incorrect PIN. 1 try left.');
      expect(pinProblem('12', '12'), 'PIN must be 4-12 digits.');
      expect(pinProblem('1234', '1235'), 'PINs do not match.');
      expect(pinProblem('1234', '1234'), isNull);
    });

    test('google send preview names the recipient and the subject', () {
      expect(googleSendPreview(const GoogleDraft(to: 'a@b.c', subject: 'Re: lunch', body: 'x')), 'To: a@b.c\nSubject: Re: lunch');
    });
  });

  group('the screens', () {
    Future<AppServices> services(WidgetTester tester) async => (await tester.runAsync(() => buildTestServices(ScriptedApi({}))))!;

    Future<void> host(WidgetTester tester, AppServices s, Widget Function(BuildContext) child) async {
      tester.view.physicalSize = const Size(400, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(AppScope(services: s, child: MaterialApp(home: Scaffold(body: Builder(builder: (c) => SingleChildScrollView(child: child(c)))))));
      await tester.pump();
    }

    Future<void> done(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
    }

    testWidgets('a delete asks first and does nothing on Cancel; Delete goes through', (tester) async {
      final api = FakeApi();
      final s = await services(tester);
      await host(tester, s, (c) => TextButton(key: const Key('go'), onPressed: () => deleteChatThread(c, api, 'T1', 'Trip plan'), child: const Text('go')));
      await tester.tap(find.byKey(const Key('go')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Trip plan'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(api.calls, isEmpty);
      await tester.tap(find.byKey(const Key('go')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(api.calls, ['delete:T1']);
      await done(tester);
    });

    testWidgets('inbox delete names how many and deletes each only after the confirm', (tester) async {
      final api = FakeApi();
      final s = await services(tester);
      await host(tester, s, (c) => TextButton(key: const Key('go'), onPressed: () => deleteInboxMessages(c, api, ['A', 'B']), child: const Text('go')));
      await tester.tap(find.byKey(const Key('go')));
      await tester.pumpAndSettle();
      expect(find.text('Delete 2 messages from the inbox?'), findsOneWidget);
      expect(api.calls, isEmpty);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(api.calls, ['idelete:A', 'idelete:B']);
      await done(tester);
    });

    testWidgets('Google send shows the recipient and subject and sends only on the tap', (tester) async {
      final api = FakeApi();
      final s = await services(tester);
      await host(tester, s, (c) => TextButton(key: const Key('go'), onPressed: () => confirmAndSendGoogle(c, api, const GoogleDraft(to: 'amina@x.test', subject: 'Re: lunch', body: 'yes')), child: const Text('go')));
      await tester.tap(find.byKey(const Key('go')));
      await tester.pumpAndSettle();
      expect(find.textContaining('To: amina@x.test'), findsOneWidget);
      expect(find.textContaining('Subject: Re: lunch'), findsOneWidget);
      expect(api.calls, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(api.calls, isEmpty);
      await tester.tap(find.byKey(const Key('go')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(api.calls, ['send:amina@x.test']);
      await done(tester);
    });

    testWidgets('Google connect shows the code, polls, and says connected', (tester) async {
      final api = FakeApi();
      final s = await services(tester);
      await host(tester, s, (c) => GoogleConnectCard(api: api));
      await tester.tap(find.byKey(const Key('google-start')));
      await tester.pump();
      await tester.pump();
      expect(find.text('ABCD-1234'), findsOneWidget);
      api.poll = GooglePollState.connected;
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(find.text('Google account connected.'), findsOneWidget);
      await done(tester);
    });

    testWidgets('PIN: a mismatch is refused before any call; a match saves; the check names tries left', (tester) async {
      final api = FakeApi();
      final s = await services(tester);
      await host(tester, s, (c) => PinCard(api: api));
      await tester.pump();
      expect(find.text('PIN set'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('pin-new')), '1234');
      await tester.enterText(find.byKey(const Key('pin-confirm')), '9999');
      await tester.tap(find.byKey(const Key('pin-save')));
      await tester.pump();
      expect(find.text('PINs do not match.'), findsOneWidget);
      expect(api.calls, isEmpty);
      await tester.enterText(find.byKey(const Key('pin-confirm')), '1234');
      await tester.tap(find.byKey(const Key('pin-save')));
      await tester.pump();
      await tester.pump();
      expect(api.calls, ['setpin']);
      expect(find.text('PIN updated.'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('pin-check')), '0000');
      await tester.tap(find.byKey(const Key('pin-verify')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check').last);
      await tester.pumpAndSettle();
      expect(find.text('Incorrect PIN. 2 tries left.'), findsOneWidget);
      await done(tester);
    });

    testWidgets('persona split and voice card render what the hub returned', (tester) async {
      final api = FakeApi();
      final s = await services(tester);
      await host(tester, s, (c) => PersonaVoiceSection(api: api));
      await tester.pump();
      await tester.pump();
      expect(find.text('work: 60%'), findsOneWidget);
      expect(find.text('formality: 3'), findsOneWidget);
      await done(tester);
    });

    testWidgets('spaces check reports drift in a dialog', (tester) async {
      final api = FakeApi();
      final s = await services(tester);
      await host(tester, s, (c) => TextButton(key: const Key('go'), onPressed: () => spacesSyncCheck(c, api), child: const Text('go')));
      await tester.tap(find.byKey(const Key('go')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('drift-text')), findsOneWidget);
      expect(find.textContaining('Work/x'), findsOneWidget);
      await done(tester);
    });

    testWidgets('project url dialog saves the trimmed address', (tester) async {
      final api = FakeApi();
      final s = await services(tester);
      await host(tester, s, (c) => TextButton(key: const Key('go'), onPressed: () => projectUrlDialog(c, api, 'P1'), child: const Text('go')));
      await tester.tap(find.byKey(const Key('go')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('project-url-field')), ' https://x.test ');
      await tester.tap(find.byKey(const Key('project-url-save')));
      await tester.pumpAndSettle();
      expect(api.calls, ['url:P1:https://x.test']);
      await done(tester);
    });
  });
}
