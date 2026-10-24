import 'package:isconl/app_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/data/accounts_data.dart';
import 'package:isconl/ui/views/accounts_space.dart';

import 'support/test_services.dart';

/// BI26102401: the Accounts space, its import guard and its note scan.
void main() {
  final now = DateTime(2026, 10, 24, 9);

  Future<void> pump(WidgetTester tester, AccountsApi api) async {
    tester.view.physicalSize = const Size(400, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final services = (await tester.runAsync(() => buildTestServices(ScriptedApi({}))))!;
    await tester.pumpWidget(AppScope(services: services, child: MaterialApp(home: Scaffold(body: AccountsSpace(api: api, clock: () => now)))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  group('guards', () {
    test('a note holding a token shape is refused without echoing it', () async {
      final api = FakeAccountsApi();
      await expectLater(
        api.addAddress(const AccountAddress(address: 'x@y.z', note: 'ghp_abcdefghijklmnopqrstuvwxyz0123456789')),
        throwsA(isA<AccountsException>().having((e) => e.message, 'message', isNot(contains('ghp_')))),
      );
    });

    test('an import with a password column is refused', () {
      final r = AccountsImport.parse('address,service,password\na@b.c,Netflix,hunter2hunter2');
      expect(r.ok, isFalse);
      expect(r.refusal, isNot(contains('hunter2')));
    });

    test('a Bitwarden export is refused outright', () {
      expect(AccountsImport.parse('folder,favorite,type,name,login_uri,login_username,login_password,login_totp\n,,login,x,y,z,w,').ok, isFalse);
    });

    test('a clean list previews its rows', () {
      final r = AccountsImport.parse('address,service,plan,cost,renewal,note\na@b.c,Netflix,Basic,5.5,2026-11-01,');
      expect(r.ok, isTrue);
      expect(r.rows.single.monthlyCost, 5.5);
    });

    test('recovery single point is flagged at three', () {
      const a = [
        AccountAddress(address: 'a@x', recoveryAddress: 'r@x'),
        AccountAddress(address: 'b@x', recoveryAddress: 'r@x'),
        AccountAddress(address: 'c@x', recoveryAddress: 'r@x'),
      ];
      expect(recoverySinglePoints(a), ['r@x']);
    });

    test('last seen shows its source', () {
      expect(lastSeenLabel(now.subtract(const Duration(hours: 2)), 'slate', now), 'seen in slate 2h ago');
      expect(lastSeenLabel(DateTime(2026, 9, 3), 'typed', now), 'you said 3 Sep');
    });
  });

  Future<void> teardown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('the Addresses tab seeds the five addresses and marks the team lead not mine', (tester) async {
    await pump(tester, FakeAccountsApi());
    expect(find.byKey(const Key('address-sconl.vv@gmail.com')), findsOneWidget);
    expect(find.byKey(const Key('not-mine-evansnyambegavv@gmail.com')), findsOneWidget);
    expect(find.byKey(const Key('not-mine-sconl@proton.me')), findsNothing);
    await teardown(tester);
  });

  testWidgets('the Sign-ups tab totals the month and warns of a renewal inside 14 days', (tester) async {
    await pump(tester, FakeAccountsApi(signUps: [SignUp(service: 'Claude', address: 'a@b.c', monthlyCost: 20, renewal: now.add(const Duration(days: 5)))]));
    await tester.tap(find.text('Sign-ups'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const Key('monthly-total')), findsOneWidget);
    expect(find.byKey(const Key('renewal-notice')), findsOneWidget);
    await teardown(tester);
  });

  testWidgets('the AI seats tab shows both usage figures', (tester) async {
    await pump(tester, FakeAccountsApi(seats: [const AiSeat(account: 'work', provider: 'claude', fiveHourPct: 42, sevenDayPct: 61)]));
    await tester.tap(find.text('AI seats'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining('5-hour 42% · 7-day 61%'), findsOneWidget);
    await teardown(tester);
  });

  // BI26102402: suggestions from mail headers, and the optional breach check.
  final acme = SignUpSuggestion(id: 'acme-com-me-x-com', service: 'Acme', domain: 'acme.com', address: 'me@x.com', firstMail: DateTime(2026, 6, 1), lastMail: DateTime(2026, 9, 1), paid: true, count: 2);
  final zed = SignUpSuggestion(id: 'zed-co-uk-me-x-com', service: 'Zed', domain: 'zed.co.uk', address: 'me@x.com', lastMail: DateTime(2025, 1, 3), count: 1);

  Future<void> openSignUps(WidgetTester tester) async {
    await tester.tap(find.text('Sign-ups'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('suggestions are offered one at a time and Accept adds the sign-up with the mail date as last seen', (tester) async {
    final api = FakeAccountsApi(suggestions: [acme, zed]);
    await pump(tester, api);
    await openSignUps(tester);
    expect(find.byKey(Key('suggestion-${acme.id}')), findsOneWidget);
    expect(find.byKey(Key('suggestion-${zed.id}')), findsNothing);
    expect(find.textContaining('2 to look at'), findsOneWidget);
    await tester.tap(find.byKey(const Key('suggestion-accept')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final added = (await api.signUps()).single;
    expect(added.service, 'Acme');
    expect(added.lastSeenSource, 'mail');
    expect(added.lastSeen, DateTime(2026, 9, 1));
    await teardown(tester);
  });

  testWidgets('Not a sign-up removes the suggestion for good and Later keeps it', (tester) async {
    final api = FakeAccountsApi(suggestions: [acme, zed]);
    await pump(tester, api);
    await openSignUps(tester);
    await tester.tap(find.byKey(const Key('suggestion-never')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect((await api.suggestions()).map((x) => x.id), [zed.id]);
    await api.decide(zed.id, 'later');
    expect((await api.suggestions()).map((x) => x.id), [zed.id]);
    expect(await api.signUps(), isEmpty);
    await teardown(tester);
  });

  testWidgets('with no Have I Been Pwned key the Addresses tab says the breach check is off and nothing else', (tester) async {
    await pump(tester, FakeAccountsApi());
    expect(find.text('Breach check off: needs a Have I Been Pwned key'), findsOneWidget);
    expect(find.byKey(const Key('breach-notice')), findsNothing);
    await teardown(tester);
  });

  testWidgets('a new breach is named on its address card and raises one notice that Got it clears', (tester) async {
    final api = FakeAccountsApi(breaches: BreachStatus(enabled: true, line: 'Breach check on: weekly.', items: [Breach(address: 'sconl@proton.me', breach: 'Adobe', date: DateTime(2013, 10, 4))]));
    await pump(tester, api);
    expect(find.byKey(const Key('breach-notice')), findsOneWidget);
    expect(find.textContaining('New breach: Adobe'), findsOneWidget);
    expect(find.byKey(const Key('breaches-sconl@proton.me')), findsOneWidget);
    expect(find.textContaining('Adobe 2013'), findsOneWidget);
    await tester.tap(find.byKey(const Key('breach-dismiss')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const Key('breach-notice')), findsNothing);
    expect(find.byKey(const Key('breaches-sconl@proton.me')), findsOneWidget);
    await teardown(tester);
  });
}
