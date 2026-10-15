import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/services/cx_grants.dart';
import 'package:isconl/ui/widgets/journal_access.dart';

class FakeGrants implements CxGrantsClient {
  FakeGrants({this.approves = true});
  bool approves;
  final calls = <String>[];
  List<LiveGrant> liveList = [];

  @override
  Future<GrantRequest?> request(String id) async => null;
  @override
  Future<List<LiveGrant>> live() async => liveList;
  @override
  Future<bool> approve(String id) async {
    calls.add('approve:$id');
    return approves;
  }

  @override
  Future<void> refuse(String id) async => calls.add('refuse:$id');
  @override
  Future<void> revoke(String id) async {
    calls.add('revoke:$id');
    liveList = liveList.where((g) => g.id != id).toList();
  }
}

const _req = GrantRequest(id: 'g1', session: '20261015-0900-linux-build-x', machine: 'linux', reason: 'Draft the week review');

Widget _host(Widget w) => MaterialApp(home: Scaffold(body: w));

void main() {
  testWidgets('the sheet names the session, machine, reason and limit, and shows no journal text', (t) async {
    await t.pumpWidget(_host(GrantRequestSheet(client: FakeGrants(), request: _req)));
    expect(find.text('20261015-0900-linux-build-x wants to read your journal'), findsOneWidget);
    expect(find.text('linux'), findsOneWidget);
    expect(find.text('Draft the week review'), findsOneWidget);
    expect(find.textContaining('2 hours'), findsOneWidget);
  });

  testWidgets('Approve calls the passkey approval and reports it', (t) async {
    final c = FakeGrants();
    await t.pumpWidget(_host(GrantRequestSheet(client: c, request: _req)));
    await t.tap(find.byKey(const Key('grant-approve')));
    await t.pumpAndSettle();
    expect(c.calls, ['approve:g1']);
    expect(find.textContaining('Approved.'), findsOneWidget);
    expect(t.widget<FilledButton>(find.byKey(const Key('grant-approve'))).onPressed, isNull);
  });

  testWidgets('a cancelled passkey prompt approves nothing', (t) async {
    final c = FakeGrants(approves: false);
    await t.pumpWidget(_host(GrantRequestSheet(client: c, request: _req)));
    await t.tap(find.byKey(const Key('grant-approve')));
    await t.pumpAndSettle();
    expect(find.textContaining('Nothing was changed'), findsOneWidget);
    expect(find.textContaining('Approved.'), findsNothing);
  });

  testWidgets('Refuse refuses', (t) async {
    final c = FakeGrants();
    await t.pumpWidget(_host(GrantRequestSheet(client: c, request: _req)));
    await t.tap(find.byKey(const Key('grant-refuse')));
    await t.pumpAndSettle();
    expect(c.calls, ['refuse:g1']);
    expect(find.textContaining('Refused.'), findsOneWidget);
  });

  testWidgets('live grants list time left and reads, and each can be revoked', (t) async {
    final now = DateTime.utc(2026, 10, 15, 12);
    final c = FakeGrants()
      ..liveList = [
        LiveGrant(id: 'a', session: 'sess-a', machine: 'linux', expiresAt: now.add(const Duration(minutes: 90)), reads: 4),
        LiveGrant(id: 'b', session: 'sess-b', machine: 'windows', expiresAt: now.add(const Duration(minutes: 20)), reads: 0),
      ];
    await t.pumpWidget(_host(JournalAccessCard(client: c, now: () => now)));
    await t.pumpAndSettle();
    expect(find.textContaining('1 h 30 min left'), findsOneWidget);
    expect(find.textContaining('4 reads'), findsOneWidget);
    await t.tap(find.byKey(const Key('revoke-a')));
    await t.pumpAndSettle();
    expect(c.calls, ['revoke:a']);
    expect(find.text('sess-a'), findsNothing);
    expect(find.text('sess-b'), findsOneWidget);
    await t.tap(find.byKey(const Key('revoke-b')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('no-grants')), findsOneWidget);
  });

  test('hub shapes parse', () {
    final r = HubCxGrantsClient.parseRequest({'id': 'g', 'session': 's', 'machine': 'm', 'reason': 'r', 'limit_seconds': 3600});
    expect(r.limit, const Duration(hours: 1));
    final l = HubCxGrantsClient.parseLive({'id': 'g', 'session': 's', 'machine': 'm', 'expires_at': 100, 'reads': 2});
    expect(l.reads, 2);
    expect(l.timeLeft(DateTime.utc(2030)), Duration.zero);
  });
}
