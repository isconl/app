import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/services/slate_hub_client.dart';
import 'package:slate_ui/slate_ui.dart';

void main() {
  rowParsingTests();
  test('parses a session from hub in snake_case and camelCase', () {
    final a = HubSlateClient.parseSession({
      'id': 's1',
      'machine': 'windows',
      'kind': 'build-app',
      'current_row': 'BI26101417',
      'current_row_title': 'mount',
      'position': 2,
      'total': 25,
      'last_seen': 1792043137,
    });
    expect(a.currentRow, 'BI26101417');
    expect(a.progress, '2 of 25');
    expect(a.lastSeen.toUtc().millisecondsSinceEpoch, 1792043137000);
    final b = HubSlateClient.parseSession({'sessionId': 's2', 'lastSeen': 0, 'currentRow': 'X'});
    expect(b.id, 's2');
    expect(b.currentRow, 'X');
  });

  test('a command body names its target, delivery and action', () {
    const d = CommandDraft(
      target: CommandTarget.kindOnMachine(kind: 'build', machine: 'windows'),
      message: 'Stop',
      persistent: true,
      expiresIn: Duration(hours: 1),
      action: QuickAction.stopForDay,
    );
    final body = HubSlateClient.commandBody(d);
    expect(body['to'], {'kind': 'build', 'machine': 'windows'});
    expect(body['expires_in_seconds'], 3600);
    expect(body['action'], 'stopForDay');
    expect(HubSlateClient.commandBody(const CommandDraft(
        target: CommandTarget.everyone(), message: 'x', persistent: false))['to'], {'everyone': true});
  });

  test('delivery states map, unknown means sent', () {
    expect(HubSlateClient.parseState('acked'), DeliveryState.acknowledged);
    expect(HubSlateClient.parseState('delivered'), DeliveryState.delivered);
    expect(HubSlateClient.parseState(null), DeliveryState.sent);
  });
}

void rowParsingTests() {
  test('rows, blockers, matrix and today parse from hub shapes', () {
    final r = HubSlateClient.parseRow({
      'id': 'BI1', 'project': 'iSconl', 'type': 'build', 'title': 'T',
      'effectiveStatus': 'claimed', 'claimedBySession': 's9', 'subset': 'app',
    });
    expect(r.status, 'claimed');
    expect(r.isClaimed, isTrue);
    final d = HubSlateClient.parseDetail({'id': 'BI1', 'body': 'Do it'});
    expect(d.body, 'Do it');
    final b = HubSlateClient.parseBlocker({'id': 'k', 'row': 'BI1', 'class': 'access', 'need': 'n', 'raised_at': 100});
    expect(b.kind, 'access');
    final m = HubSlateClient.parseMatrix({
      'types': ['plan', 'build'],
      'projects': {'a': {'plan': 1, 'build': 2}},
    });
    expect(m.total, 3);
    final t = HubSlateClient.parseToday({'closed_today': 3, 'weekly_daily_average': 10, 'in_flight': 2});
    expect(t.belowPace, isTrue);
  });
}
