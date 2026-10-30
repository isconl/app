import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/data/modules.dart';
import 'package:isconl/ui/views/learning.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/test_services.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('BI26102806: moduleMetaLine unit tests', () {
    test('manifest with every field formats all parts in order with separator', () {
      final line = moduleMetaLine(
        lesson: {
          'status': 'learning',
          'progressPct': 45,
          'minutes': 8,
          'offline': 'on device',
          'version': '1.2.0',
          'reviewedAt': '2026-09-20',
          'subjects': ['Systems Architecture', 'Distributed Systems'],
        },
      );
      expect(
        line,
        'reading 45% · 8 min · on device · v1.2.0 · reviewed 20 Sep 2026 · Systems Architecture, Distributed Systems',
      );
    });

    test('done progress state and string minutes format properly', () {
      final line = moduleMetaLine(
        lesson: {
          'status': 'done',
          'minutes': '12 min',
          'offline': 'updated',
          'version': 'v2.0.0',
          'reviewedAt': '2026-10-15',
          'subjects': 'Storage Engines',
        },
      );
      expect(
        line,
        'done · 12 min · updated · v2.0.0 · reviewed 15 Oct 2026 · Storage Engines',
      );
    });

    test('not started progress state and not downloaded offline state', () {
      final line = moduleMetaLine(
        lesson: {
          'status': 'new',
          'minutes': 15,
          'offline': 'not downloaded',
          'version': 'v1.0.0',
          'reviewedAt': '2026-08-01',
          'subjects': 'Foundations',
        },
      );
      expect(
        line,
        'not started · 15 min · not downloaded · v1.0.0 · reviewed 1 Aug 2026 · Foundations',
      );
    });

    test('manifest with none of the fields returns null and no placeholders', () {
      final line = moduleMetaLine(
        lesson: {
          'file': '01-intro.md',
          'title': 'Intro',
        },
      );
      expect(line, isNull);
    });

    test('zero minutes or placeholder "0 min" is completely omitted', () {
      final line1 = moduleMetaLine(
        lesson: {
          'status': 'done',
          'minutes': 0,
        },
      );
      expect(line1, 'done');
      expect(line1?.contains('0 min'), isFalse);

      final line2 = moduleMetaLine(
        lesson: {
          'status': 'done',
          'minutes': '0 min',
        },
      );
      expect(line2, 'done');
      expect(line2?.contains('0 min'), isFalse);
    });

    test('merges fields from manifest and lesson cleanly', () {
      final line = moduleMetaLine(
        lesson: {
          'file': '01.md',
          'status': 'opened',
        },
        manifest: {
          'minutes': 10,
          'version': 'v3.1.0',
          'reviewedAt': '2026-07-10',
          'subjects': 'Networking',
          'offline': 'on device',
        },
      );
      expect(
        line,
        'reading · 10 min · on device · v3.1.0 · reviewed 10 Jul 2026 · Networking',
      );
    });
  });

  group('BI26102806: modules list widget tests', () {
    testWidgets('manifest with every field renders on 360 dp screen with no overflow', (tester) async {
      final services = (await tester.runAsync(() => buildTestServices(ScriptedApi({}))))!;
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      services.modules.setManifestForTesting({
        'lessons': [
          {
            'course': 'arch101',
            'file': '01-consensus.md',
            'status': 'learning',
            'progressPct': 45,
            'minutes': 8,
            'offline': 'on device',
            'version': 'v1.2.0',
            'reviewedAt': '2026-09-20',
            'subjects': 'Systems Architecture',
          },
          {
            'course': 'arch101',
            'file': '02-storage.md',
            'status': 'done',
            'minutes': 12,
            'offline': 'updated',
            'version': 'v2.0.0',
            'reviewedAt': '2026-10-15',
            'subjects': 'Storage Engines',
          },
        ],
      });

      final course = {
        'ID': 'arch101',
        'TITLE': 'Systems Architecture 101',
        'lessons': [
          {
            'file': '01-consensus.md',
            'title': 'Consensus Models',
            'subtitle': 'Raft and Paxos in distributed logs',
            'status': 'learning',
            'progressPct': 45,
            'minutes': 8,
            'offline': 'on device',
            'version': 'v1.2.0',
            'reviewedAt': '2026-09-20',
            'subjects': 'Systems Architecture',
          },
          {
            'file': '02-storage.md',
            'title': 'LSM Tree Storage',
            'subtitle': 'SSTables and memtable flush pipeline',
            'status': 'done',
            'minutes': 12,
            'offline': 'updated',
            'version': 'v2.0.0',
            'reviewedAt': '2026-10-15',
            'subjects': 'Storage Engines',
          },
        ],
      };

      await tester.pumpWidget(
        AppScope(
          services: services,
          child: MaterialApp(
            home: Scaffold(
              body: CourseDetailScreen(
                title: 'Systems Architecture 101',
                course: course,
                trackColor: const Color(0xFF10B981),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      final metaWidgets = find.byKey(const Key('module-meta'));
      expect(metaWidgets, findsNWidgets(2));

      expect(
        find.text('reading 45% · 8 min · on device · v1.2.0 · reviewed 20 Sep 2026 · Systems Architecture'),
        findsOneWidget,
      );
      expect(
        find.text('done · 12 min · updated · v2.0.0 · reviewed 15 Oct 2026 · Storage Engines'),
        findsOneWidget,
      );
    });

    testWidgets('manifest with none of the fields renders cleanly at 360 dp without placeholders', (tester) async {
      final services = (await tester.runAsync(() => buildTestServices(ScriptedApi({}))))!;
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // Manifest has no metadata fields
      services.modules.setManifestForTesting({
        'lessons': [
          {
            'course': 'arch101',
            'file': '01-consensus.md',
          },
        ],
      });

      final course = {
        'ID': 'arch101',
        'TITLE': 'Systems Architecture 101',
        'lessons': [
          {
            'file': '01-consensus.md',
            'title': 'Consensus Models',
          },
        ],
      };

      await tester.pumpWidget(
        AppScope(
          services: services,
          child: MaterialApp(
            home: Scaffold(
              body: CourseDetailScreen(
                title: 'Systems Architecture 101',
                course: course,
                trackColor: const Color(0xFF10B981),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      // No module meta line should be rendered
      expect(find.byKey(const Key('module-meta')), findsNothing);

      // No placeholder text like "0 min", "v0.0.0", or stray dots
      expect(find.textContaining('0 min'), findsNothing);
      expect(find.textContaining('v0.0.0'), findsNothing);
      expect(find.textContaining('·'), findsNothing);
    });
  });
}
