import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:isconl/theme.dart';
import 'package:isconl/ui/shell.dart';

// BI26100539: the app bar holds one stroked cloud, not two dots.
void main() {
  test('state: green when idle and empty, yellow when waiting or syncing, offline wins', () {
    expect(syncMarkFor(online: true, busy: false, pending: 0), SyncMark.synced);
    expect(syncMarkFor(online: true, busy: false, pending: 1), SyncMark.waiting);
    expect(syncMarkFor(online: true, busy: true, pending: 0), SyncMark.waiting);
    expect(syncMarkFor(online: false, busy: false, pending: 3), SyncMark.offline);
  });

  test('labels carry the pending count', () {
    expect(syncMarkLabel(SyncMark.synced, 0), 'All synced');
    expect(syncMarkLabel(SyncMark.waiting, 3), '3 waiting to sync');
    expect(syncMarkLabel(SyncMark.waiting, 0), 'Syncing');
    expect(syncMarkLabel(SyncMark.offline, 2), 'Offline');
  });

  Future<Icon> pump(WidgetTester t, SyncMark m) async {
    await t.pumpWidget(MaterialApp(home: Scaffold(body: SyncCloud(mark: m, label: syncMarkLabel(m, 1)))));
    expect(find.byType(Icon), findsOneWidget);
    return t.widget<Icon>(find.byType(Icon));
  }

  testWidgets('idle shows one green outlined cloud and no dot', (t) async {
    final i = await pump(t, SyncMark.synced);
    expect(i.icon, Icons.cloud_outlined);
    expect(i.color, C.green);
  });

  testWidgets('waiting shows the cloud in yellow', (t) async {
    final i = await pump(t, SyncMark.waiting);
    expect(i.icon, Icons.cloud_outlined);
    expect(i.color, C.amber);
  });

  testWidgets('offline shows the crossed cloud', (t) async {
    final i = await pump(t, SyncMark.offline);
    expect(i.icon, Icons.cloud_off_outlined);
  });
}
