// BI26111899: when start-up fails, the phone shows what happened and a way out, never a blank screen.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/main.dart';

void main() {
  testWidgets('a failed start shows the error, Try again and Reset stored data', (t) async {
    await t.pumpWidget(const StartFailedApp(error: 'Bad state: example'));
    await t.pump();
    expect(find.byKey(const Key('start-failed')), findsOneWidget);
    expect(find.text('iSconl could not start'), findsOneWidget);
    expect(find.textContaining('Bad state: example'), findsOneWidget);
    expect(find.byKey(const Key('start-retry')), findsOneWidget);
    expect(find.byKey(const Key('start-reset')), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
