import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/api/client.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/theme.dart';
import 'package:isconl/ui/widgets/offsite_backup_line.dart';

import 'support/test_services.dart';

void main() {
  group('BI26100503: the line', () {
    test('green under 24 hours reads the age', () {
      final v = backupLineView({'status': 'green', 'age_hours': 3.2, 'reason': ''});
      expect(v.text, 'Offsite backup: 3 h ago');
      expect(v.color, C.green);
    });

    test('red carries the server reason', () {
      final v = backupLineView({'status': 'red', 'age_hours': 30, 'reason': 'the last copy failed to upload'});
      expect(v.text, 'Offsite backup: 30 h ago, the last copy failed to upload');
      expect(v.color, C.red);
    });

    test('a green older than a day is red, never green', () {
      final v = backupLineView({'status': 'green', 'age_hours': 26, 'reason': ''});
      expect(v.color, C.red);
      expect(v.text, startsWith('Offsite backup: 26 h ago'));
    });

    test('unknown, an empty answer, a green with no age, and a failed call are all grey', () {
      for (final a in <dynamic>[
        {'status': 'unknown', 'age_hours': null, 'reason': 'vault could not be reached'},
        <String, dynamic>{},
        {'status': 'green', 'age_hours': null},
        null,
      ]) {
        final v = backupLineView(a, error: a == null ? 'timeout' : null);
        expect(v.color, C.text3, reason: '$a');
        expect(v.text, startsWith('Offsite backup: unknown ('), reason: '$a');
      }
      expect(backupLineView(null, error: 'timeout').text, 'Offsite backup: unknown (could not be reached)');
    });

    test('days past two days', () {
      expect(backupLineView({'status': 'red', 'age_hours': 72, 'reason': 'stale'}).text, 'Offsite backup: 3 days ago, stale');
    });
  });

  group('BI26100503: the widget', () {
    Future<void> pump(WidgetTester tester, Object answer) async {
      final api = ScriptedApi({'/api/vitals/backup': answer});
      final services = (await tester.runAsync(() => buildTestServices(api)))!;
      if (answer is Map<String, dynamic>) services.store.backupOffsite.value = answer;
      await tester.pumpWidget(AppScope(services: services, child: const MaterialApp(home: Scaffold(body: OffsiteBackupLine()))));
      await tester.pump();
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 80)));
      await tester.pump();
    }

    testWidgets('shows the green line from the hub route', (tester) async {
      await pump(tester, {'status': 'green', 'age_hours': 5, 'reason': '', 'target': 'onedrive'});
      expect(tester.widget<Text>(find.byKey(const Key('offsite-backup-line'))).data, 'Offsite backup: 5 h ago');
    });

    testWidgets('a failing call shows the grey line, not green and not blank', (tester) async {
      await pump(tester, ApiException(500, 'down'));
      final t = tester.widget<Text>(find.byKey(const Key('offsite-backup-line')));
      expect(t.style?.color, C.text3);
      expect(t.data, startsWith('Offsite backup: unknown ('));
    });
  });
}
