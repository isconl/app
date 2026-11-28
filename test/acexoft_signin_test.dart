// PI26111401: the app's QAce ID sign-in. The browser leg is faked; what is checked is what the app sends and
// what it does with each answer.
import 'dart:convert';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/api/client.dart';
import 'package:isconl/services/session.dart';

class _Api extends ApiClient {
  _Api(this.answer) : super(baseUrl: 'https://isconl.test', token: '');
  final Object answer; // a Map to return, or an exception to throw
  final List<(String, Map<String, dynamic>)> posts = [];
  @override
  Future<dynamic> postJson(String path, Map<String, dynamic> body, {bool cold = false}) async {
    posts.add((path, body));
    if (answer is Exception) throw answer;
    return answer;
  }
}

class _Session extends SessionService {
  _Session(this._api);
  final _Api _api;
  @override
  ApiClient get api => _api;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  test('the challenge is the S256 of the verifier it later sends, and a code becomes the session', () async {
    final api = _Api({'success': true, 'token': 't' * 64});
    final s = _Session(api)..serverUrl = 'https://isconl.test/';
    String? opened;
    final err = await s.loginAcexoft(openBrowser: (url, scheme) async {
      opened = url;
      expect(scheme, 'com.sconl.isconl');
      return 'com.sconl.isconl:/auth/acexoft?code=abc';
    });
    expect(err, isNull);
    final u = Uri.parse(opened!);
    expect(u.origin + u.path, 'https://isconl.test/auth/guard/start');
    final challenge = u.queryParameters['app_challenge']!;
    expect(challenge, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
    final (path, body) = api.posts.single;
    expect(path, '/auth/guard/app-exchange');
    expect(body['code'], 'abc');
    final verifier = body['verifier'] as String;
    expect(base64UrlEncode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', ''), challenge);
    expect(s.api.token, 't' * 64);
    expect(s.authenticated, isTrue);
  });

  test('a cancelled tab, a refusal from hub, and a refused exchange each give a plain message and no session', () async {
    final cancelled = _Session(_Api({}))..serverUrl = 'https://isconl.test';
    expect(await cancelled.loginAcexoft(openBrowser: (_, _) async => throw PlatformException(code: 'CANCELED')),
        'Sign-in was cancelled.');

    final refusedApi = _Api({});
    final refused = _Session(refusedApi)..serverUrl = 'https://isconl.test';
    expect(
        await refused.loginAcexoft(
            openBrowser: (_, _) async => 'com.sconl.isconl:/auth/acexoft?error=This%20account%20is%20not%20an%20owner'),
        'This account is not an owner');
    expect(refusedApi.posts, isEmpty, reason: 'nothing is exchanged after a refusal');

    final badApi = _Api(ApiException(400, 'That sign-in could not be completed. Start again from the app.'));
    final bad = _Session(badApi)..serverUrl = 'https://isconl.test';
    expect(await bad.loginAcexoft(openBrowser: (_, _) async => 'com.sconl.isconl:/auth/acexoft?code=x'),
        'That sign-in could not be completed. Start again from the app.');
    expect(bad.authenticated, isFalse);
  });
}
