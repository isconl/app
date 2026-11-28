import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/api/client.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/services/passkey_client.dart';
import 'package:isconl/ui/login.dart';
import 'package:isconl/ui/widgets/passkeys_card.dart';
import 'package:passkeys/types.dart';

import 'support/test_services.dart';

class FakePasskeys implements PasskeyClient {
  FakePasskeys({this.isAvailable = true, this.failWith});
  final bool isAvailable;
  final Object? failWith;
  final List<Map<String, dynamic>> authenticated = [];
  final List<Map<String, dynamic>> registered = [];

  @override
  Future<bool> available() async => isAvailable;

  @override
  Future<Map<String, dynamic>> authenticate(Map<String, dynamic> options) async {
    authenticated.add(options);
    if (failWith != null) throw failWith!;
    return {'id': 'cred-1', 'response': {'signature': 'sig'}};
  }

  @override
  Future<Map<String, dynamic>> register(Map<String, dynamic> options) async {
    registered.add(options);
    if (failWith != null) throw failWith!;
    return {'id': 'cred-2', 'response': {'attestationObject': 'att'}};
  }
}

class PasskeyApi extends ScriptedApi {
  PasskeyApi(super.answers, this.posts);
  final List<Map<String, dynamic>> posts;

  @override
  Future<dynamic> postJson(String path, Map<String, dynamic> body, {bool cold = false}) async {
    posts.add({'path': path, ...body});
    for (final e in answers.entries) {
      if (path == e.key) {
        final v = e.value;
        if (v is Exception) throw v;
        return v;
      }
    }
    return {'ok': true};
  }
}

final options = {'challenge': 'abc', 'rpId': 'isconl.acexoft.com', 'allowCredentials': []};

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('each platform failure becomes a plain sentence, and the exception text never reaches the screen', () {
    expect(passkeyFailureFor(PasskeyAuthCancelledException()).cancelled, isTrue);
    expect(passkeyFailureFor(PasskeyAuthCancelledException()).message, 'Passkey cancelled.');
    expect(passkeyFailureFor(NoCredentialsAvailableException()).message, contains('No passkey for this app'));
    expect(passkeyFailureFor(DomainNotAssociatedException('isconl.acexoft.com')).message, isNot(contains('isconl.acexoft.com')));
    expect(passkeyFailureFor(DeviceNotSupportedException()).message, contains('does not support passkeys'));
    expect(passkeyFailureFor(Exception('secret detail')).message, 'Passkey sign-in did not work. Use your PIN.');
    expect(passkeyFailureFor(Exception('secret detail')).message, isNot(contains('secret')));
    final f = PasskeyFailure('x');
    expect(passkeyFailureFor(f), same(f));
  });

  test('the times read as dates, and never for a missing one', () {
    expect(passkeyWhen(null), 'never');
    expect(passkeyWhen('nonsense'), 'never');
    expect(passkeyWhen('2026-10-12T09:30:00Z').endsWith('Oct 2026'), isTrue);
    expect(passkeyLive({'revokedAt': null}), isTrue);
    expect(passkeyLive({'revokedAt': '2026-10-01T00:00:00Z'}), isFalse);
  });

  Future<({AppServices services, List<Map<String, dynamic>> posts, FakePasskeys fake})> build(WidgetTester tester, Map<String, Object> answers, {FakePasskeys? fake}) async {
    final posts = <Map<String, dynamic>>[];
    final api = PasskeyApi(answers, posts);
    final services = (await tester.runAsync(() => buildTestServices(api)))!;
    final f = fake ?? FakePasskeys();
    services.session.passkeys = f;
    return (services: services, posts: posts, fake: f);
  }

  testWidgets('sign in with a passkey: options, the phone prompt, then the server verifies and a session starts', (tester) async {
    final b = await build(tester, {
      '/api/auth/passkey/options': {'available': true, 'options': options},
      '/api/auth/passkey/verify': {'success': true, 'token': 'session-token'},
    });
    final err = await tester.runAsync(() => b.services.session.loginPasskey());
    expect(err, isNull);
    expect(b.fake.authenticated.single['challenge'], 'abc');
    final verify = b.posts.firstWhere((p) => p['path'] == '/api/auth/passkey/verify');
    expect(verify['response'], {'id': 'cred-1', 'response': {'signature': 'sig'}});
    expect(b.services.session.authenticated, isTrue);
    expect(b.services.session.api.token, 'session-token');
  });

  testWidgets('no registered passkey, a cancel, a refused assertion and an offline phone each give a plain message and no session', (tester) async {
    var b = await build(tester, {'/api/auth/passkey/options': {'available': false}});
    expect(await tester.runAsync(() => b.services.session.loginPasskey()), 'No passkey is set up for this app yet.');
    expect(b.fake.authenticated, isEmpty);

    b = await build(tester, {'/api/auth/passkey/options': {'available': true, 'options': options}}, fake: FakePasskeys(failWith: PasskeyAuthCancelledException()));
    expect(await tester.runAsync(() => b.services.session.loginPasskey()), 'Passkey cancelled.');
    expect(b.services.session.authenticated, isFalse);

    b = await build(tester, {
      '/api/auth/passkey/options': {'available': true, 'options': options},
      '/api/auth/passkey/verify': {'success': false, 'error': 'Passkey rejected'},
    });
    expect(await tester.runAsync(() => b.services.session.loginPasskey()), 'Passkey rejected');
    expect(b.services.session.authenticated, isFalse);

    b = await build(tester, {'/api/auth/passkey/options': OfflineException()}.cast<String, Object>());
    expect(await tester.runAsync(() => b.services.session.loginPasskey()), 'No connection - check network or server URL');
  });

  testWidgets('the sign-in screen offers the passkey first, and a failure opens the PIN field with the message', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final b = await build(tester, {
      '/api/auth/methods': {'totp': true, 'passkey': true},
      '/api/auth/passkey/options': {'available': true, 'options': options},
      '/api/auth/passkey/verify': {'success': false, 'error': 'Passkey rejected'},
    });
    await tester.pumpWidget(AppScope(services: b.services, child: const MaterialApp(home: LoginScreen())));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 40)));
    }
    expect(find.byKey(const Key('login-passkey')), findsOneWidget);
    expect(find.text('AUTHENTICATOR CODE'), findsOneWidget);
    await tester.tap(find.byKey(const Key('login-passkey')));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 40)));
    }
    expect(find.text('Passkey rejected'), findsOneWidget);
    expect(find.text('QUICK PIN'), findsOneWidget);
    expect(find.byKey(const Key('login-passkey')), findsNothing);
  });

  testWidgets('with no passkey on the server, or an unsupported phone, there is no passkey button', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final b = await build(tester, {'/api/auth/methods': {'totp': true, 'passkey': true}}, fake: FakePasskeys(isAvailable: false));
    await tester.pumpWidget(AppScope(services: b.services, child: const MaterialApp(home: LoginScreen())));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 40)));
    }
    expect(find.byKey(const Key('login-passkey')), findsNothing);
    expect(find.text('AUTHENTICATOR CODE'), findsOneWidget);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 40)));
    }
  }

  final listAnswer = {
    'passkeys': [
      {'id': 'p1', 'name': 'My phone', 'createdAt': '2026-10-01T09:00:00Z', 'lastUsedAt': null, 'revokedAt': null},
      {'id': 'p2', 'name': 'Old tablet', 'createdAt': '2026-09-01T09:00:00Z', 'revokedAt': '2026-09-20T09:00:00Z', 'revokedReason': 'user'},
    ],
  };

  testWidgets('the card lists passkeys, shows a revoked one without actions, and adds one through the phone prompt', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final b = await build(tester, {
      '/api/auth/passkeys': listAnswer,
      '/api/auth/passkey/register/options': options,
      '/api/auth/passkey/register/verify': {'ok': true, 'name': 'Pixel'},
    });
    await tester.pumpWidget(AppScope(services: b.services, child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: PasskeysCard())))));
    await settle(tester);
    expect(find.text('My phone'), findsOneWidget);
    expect(find.text('Old tablet (revoked)'), findsOneWidget);
    expect(find.byKey(const Key('passkey-revoke-p1')), findsOneWidget);
    expect(find.byKey(const Key('passkey-revoke-p2')), findsNothing);

    await tester.tap(find.byKey(const Key('passkey-add')));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 150)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('passkey-name')), 'Pixel');
    await tester.tap(find.byKey(const Key('passkey-add-go')));
    await settle(tester);
    expect(b.fake.registered.single['challenge'], 'abc');
    final verify = b.posts.firstWhere((p) => p['path'] == '/api/auth/passkey/register/verify');
    expect(verify['name'], 'Pixel');
    expect(verify['response'], {'id': 'cred-2', 'response': {'attestationObject': 'att'}});
  });

  testWidgets('revoke asks first and then sends the id; rename sends the new name', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final b = await build(tester, {'/api/auth/passkeys': listAnswer});
    await tester.pumpWidget(AppScope(services: b.services, child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: PasskeysCard())))));
    await settle(tester);

    await tester.tap(find.byKey(const Key('passkey-revoke-p1')));
    await tester.pumpAndSettle();
    expect(b.posts.where((p) => p['path'] == '/api/auth/passkeys/revoke'), isEmpty, reason: 'nothing is sent before the confirm');
    await tester.tap(find.text('Revoke').last);
    await settle(tester);
    expect(b.posts.firstWhere((p) => p['path'] == '/api/auth/passkeys/revoke')['id'], 'p1');

    await tester.tap(find.byKey(const Key('passkey-rename-p1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('passkey-rename')), 'Work phone');
    await tester.tap(find.byKey(const Key('passkey-rename-go')));
    await settle(tester);
    final rename = b.posts.firstWhere((p) => p['path'] == '/api/auth/passkeys/rename');
    expect(rename['id'], 'p1');
    expect(rename['name'], 'Work phone');
  });

  testWidgets('an unsupported phone says so and offers no Add button', (tester) async {
    final b = await build(tester, {'/api/auth/passkeys': {'passkeys': []}}, fake: FakePasskeys(isAvailable: false));
    await tester.pumpWidget(AppScope(services: b.services, child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: PasskeysCard())))));
    await settle(tester);
    expect(find.textContaining('Passkeys need an Android phone'), findsOneWidget);
    expect(find.byKey(const Key('passkey-add')), findsNothing);
  });
}
