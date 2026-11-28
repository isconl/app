import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/api/client.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/services/course_standard.dart';
import 'package:isconl/ui/views/course_standards_view.dart';

import 'support/test_services.dart';

// BI26112307: the Study page that lists every archetype of the live course standard.
const _standard = {
  'version': '4.8.0',
  'archetypes': [
    {
      'name': 'Conceptual',
      'used_for': 'Business and systems content.',
      'explanation': 'BUILD and SEE carry the weight.',
      'example': {'course_id': 'systems', 'module_id': 'systems/00', 'title': 'Feedback Loops Explained'},
    },
    {'name': 'Clinical', 'used_for': 'Medicine & Surgery.', 'explanation': 'GUARD and MASTER carry real weight.', 'example': null},
  ],
};

void main() {
  test('an archetype reads from hub and back, with or without an example', () {
    final a = StandardArchetype.fromJson(Map<String, dynamic>.from((_standard['archetypes']! as List).first as Map));
    expect(a.name, 'Conceptual');
    expect(a.hasExample, isTrue);
    expect(a.exampleModule, 'systems/00');
    expect(StandardArchetype.fromJson(a.toJson()).exampleTitle, 'Feedback Loops Explained');
    final b = StandardArchetype.fromJson({'name': 'Clinical', 'example': null});
    expect(b.hasExample, isFalse);
    expect(b.toJson()['example'], isNull);
  });

  Future<void> pump(WidgetTester tester, ApiClient api) async {
    CourseStandard.instance.debugPreload(version: null);
    final services = (await tester.runAsync(() => buildTestServices(api)))!;
    await tester.pumpWidget(AppScope(services: services, child: const MaterialApp(home: Scaffold(body: CourseStandardsView()))));
    await tester.pump();
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 150)));
    await tester.pump();
  }

  testWidgets('every archetype lists with when it is used, and a tap explains it with its example', (tester) async {
    await pump(tester, ScriptedApi({'/api/learning/standard': _standard}));
    expect(find.byKey(const Key('archetype-Conceptual')), findsOneWidget);
    expect(find.byKey(const Key('archetype-Clinical')), findsOneWidget);
    expect(find.text('Medicine & Surgery.'), findsOneWidget);
    expect(find.text('Standard 4.8.0'), findsOneWidget);

    await tester.tap(find.byKey(const Key('archetype-Conceptual')));
    await tester.pumpAndSettle();
    expect(find.text('BUILD and SEE carry the weight.'), findsOneWidget);
    expect(find.byKey(const Key('archetype-example-Conceptual')), findsOneWidget);
    expect(find.text('Feedback Loops Explained'), findsOneWidget);
  });

  testWidgets('an archetype with no live module says so instead of a dead link', (tester) async {
    await pump(tester, ScriptedApi({'/api/learning/standard': _standard}));
    await tester.tap(find.byKey(const Key('archetype-Clinical')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('archetype-example-Clinical')), findsNothing);
    expect(find.text('No live module uses this archetype yet.'), findsOneWidget);
  });

  testWidgets('with no server and nothing saved, the page says why', (tester) async {
    await pump(tester, ScriptedApi({'/api/learning/standard': ApiException(0, 'unreachable')}));
    expect(find.text('No archetypes yet'), findsOneWidget);
    expect(find.textContaining('could not be reached'), findsOneWidget);
  });
}
