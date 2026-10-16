import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/services/course_standard.dart';
import 'package:isconl/theme.dart';
import 'package:isconl/ui/widgets/standard_tag.dart';
import 'package:isconl/util/module_standard.dart';

import 'support/test_services.dart';

void main() {
  group('BI26101601: reading the standard from a module', () {
    test('the frontmatter version, even after a leading HTML comment', () {
      final md = File('test/fixtures/modules/comment_frontmatter.md').readAsStringSync();
      expect(frontmatterVersion(md), '3.1.0');
      expect(frontmatterVersion('---\ntitle: X\nversion: "4.5.0"\n---\n# Body'), '4.5.0');
      expect(frontmatterVersion('# No frontmatter\n\nversion: 9.9.9 in prose'), isNull);
      expect(frontmatterVersion('---\ntitle: X\n---\nbody'), isNull);
    });

    test('major and minor decide; the patch is ignored', () {
      final cur = parseStandard('4.5.0')!;
      expect(compareStandard(parseStandard('4.5.3')!, cur), 0);
      expect(compareStandard(parseStandard('4.4.9')!, cur), lessThan(0));
      expect(compareStandard(parseStandard('3.11.0')!, cur), lessThan(0));
      expect(compareStandard(parseStandard('4.10.0')!, cur), greaterThan(0));
      expect(parseStandard('abc'), isNull);
    });

    test('the tag text: current, older, unknown, and no judgement before the current standard is known', () {
      expect(standardTagFor(version: '4.5.0', current: '4.5.0').text, 'standard 4.5');
      expect(standardTagFor(version: '4.5.0', current: '4.5.0').amber, isFalse);
      final older = standardTagFor(version: '4.0.2', current: '4.5.0');
      expect(older.text, 'standard 4.0 · older standard');
      expect(older.amber, isTrue);
      final unknown = standardTagFor(version: null, current: '4.5.0');
      expect(unknown.text, 'standard unknown');
      expect(unknown.amber, isTrue);
      expect(standardTagFor(version: '3.1.0', current: null).amber, isFalse);
    });
  });

  group('BI26101601: the tag on screen', () {
    Future<AppServices> pump(WidgetTester tester, Widget child) async {
      final api = ScriptedApi({
        '/api/learning/standard': {'version': '4.5.0'},
      });
      final services = (await tester.runAsync(() => buildTestServices(api)))!;
      await tester.pumpWidget(AppScope(services: services, child: MaterialApp(home: Scaffold(body: child))));
      await tester.pump();
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 120)));
      await tester.pump();
      return services;
    }

    testWidgets('a current module reads standard 4.5 in the quiet colour', (tester) async {
      await pump(tester, const StandardTagLine(version: '4.5.0'));
      final t = tester.widget<Text>(find.byKey(const Key('standard-tag')));
      expect(t.data, 'standard 4.5');
      expect(t.style?.color, C.text3);
    });

    testWidgets('an older module is amber with older standard, and a tap says why', (tester) async {
      await pump(tester, const StandardTagLine(version: '4.0.0'));
      final t = tester.widget<Text>(find.byKey(const Key('standard-tag')));
      expect(t.data, 'standard 4.0 · older standard');
      expect(t.style?.color, C.amber);
      await tester.tap(find.byKey(const Key('standard-tag')));
      await tester.pump();
      expect(find.text(olderStandardSentence), findsOneWidget);
    });

    testWidgets('a module with no version reads standard unknown in amber', (tester) async {
      await pump(tester, const StandardTagLine(version: null));
      final t = tester.widget<Text>(find.byKey(const Key('standard-tag')));
      expect(t.data, 'standard unknown');
      expect(t.style?.color, C.amber);
    });

    testWidgets('the Settings switch turns the module-list tag on and off', (tester) async {
      CourseStandard.instance.showOnList = false;
      await pump(tester, const StandardOnListSwitch());
      expect(CourseStandard.instance.showOnList, isFalse);
      Future<void> settle() async {
        await tester.pump();
        await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 150)));
        await tester.pump(const Duration(seconds: 1));
      }

      await tester.tap(find.byKey(const Key('standard-on-list')));
      await settle();
      expect(CourseStandard.instance.showOnList, isTrue);
      await tester.tap(find.byKey(const Key('standard-on-list')));
      await settle();
      expect(CourseStandard.instance.showOnList, isFalse);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 150)));
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
