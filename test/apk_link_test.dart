import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/api/client.dart';
import 'package:isconl/services/apk_link.dart';
import 'package:isconl/ui/widgets/apk_link_button.dart';

import 'support/test_services.dart';

/// BI26101514: the APK ticket link for another phone.
class _TicketApi extends ScriptedApi {
  _TicketApi(this.reply) : super({});
  final Object reply;
  int posts = 0;
  @override
  Future<dynamic> postJson(String path, Map<String, dynamic> body, {bool cold = false}) async {
    posts++;
    expect(path, '/api/apk/ticket');
    if (reply is ApiException) throw reply as ApiException;
    return reply;
  }
}

void main() {
  test('the ticket path becomes a full link on the agent address, with its lifetime in minutes', () async {
    final l = await issueApkLink(_TicketApi({'success': true, 'url': '/api/apk/download?t=abc', 'expiresInMs': 900000}));
    expect(l.url, 'http://test/api/apk/download?t=abc');
    expect(l.minutes, 15);
  });

  test('an answer without a link is an error, not an empty link', () async {
    await expectLater(issueApkLink(_TicketApi({'error': 'nope'})), throwsA(isA<ApiException>()));
  });

  testWidgets('the link is shown once with its lifetime, and Close forgets it', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ApkLinkButton(issue: () async => const ApkLink(url: 'http://test/api/apk/download?t=abc', minutes: 15)))));
    await tester.tap(find.byKey(const Key('apk-link')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('apk-link-url')), findsOneWidget);
    expect(find.textContaining('Works once, for 15 minutes'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('apk-link-url')), findsNothing);
  });

  testWidgets('a refusal shows its message and no dialog', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ApkLinkButton(issue: () async => throw ApiException(500, 'Hub is busy')))));
    await tester.tap(find.byKey(const Key('apk-link')));
    await tester.pumpAndSettle();
    expect(find.text('Hub is busy'), findsOneWidget);
    expect(find.byKey(const Key('apk-link-url')), findsNothing);
  });
}
