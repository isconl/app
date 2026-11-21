import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/ui/views/codex.dart';
import 'package:isconl/ui/widgets/common.dart';

/// BI26092651: visibility, practices and the Codex id on a journal entry or an idea.
void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

  bool selected(WidgetTester t, String label) => t.widget<Pill>(find.widgetWithText(Pill, label)).selected;

  test('a missing or unknown visibility reads private, and a dash reads as empty', () {
    expect(codexVisibilityOf(null), 'private');
    expect(codexVisibilityOf('-'), 'private');
    expect(codexVisibilityOf('Public'), 'public');
    expect(codexVisibilityOf('everyone'), 'private');
    expect(codexCell('-'), '');
    expect(codexCell(' CX-261005-01 '), 'CX-261005-01');
  });

  testWidgets('three visibility choices, the current one selected, and a change sends only the visibility', (t) async {
    final sent = <Map<String, dynamic>>[];
    await t.pumpWidget(host(CodexControls(
      row: const {'ID': 'J1', 'VISIBILITY': 'private'},
      onSave: (f) async {
        sent.add(f);
        return true;
      },
    )));
    for (final v in codexVisibilities) {
      expect(find.widgetWithText(Pill, v), findsOneWidget);
    }
    expect(selected(t, 'private'), isTrue);
    await t.tap(find.widgetWithText(Pill, 'public'));
    await t.pump();
    expect(sent, [
      {'visibility': 'public'}
    ]);
    expect(selected(t, 'public'), isTrue);
    expect(selected(t, 'private'), isFalse);
  });

  testWidgets('a refused change puts the choice back', (t) async {
    await t.pumpWidget(host(CodexControls(row: const {'ID': 'J1', 'VISIBILITY': 'unlisted'}, onSave: (f) async => false)));
    await t.tap(find.widgetWithText(Pill, 'public'));
    await t.pump();
    expect(selected(t, 'unlisted'), isTrue);
    expect(selected(t, 'public'), isFalse);
  });

  testWidgets('practices save as typed, and the Codex id shows once there is one', (t) async {
    final sent = <Map<String, dynamic>>[];
    await t.pumpWidget(host(CodexControls(
      row: const {'ID': 'ID9', 'VISIBILITY': 'public', 'PRACTICES': '-', 'CODEX_ID': 'CX-261005-02'},
      onSave: (f) async {
        sent.add(f);
        return true;
      },
    )));
    expect(find.text('CX-261005-02'), findsOneWidget);
    await t.enterText(find.byType(TextField), ' deep-work,gardening ');
    await t.tap(find.byKey(const ValueKey('codex-save-practices')));
    await t.pump();
    expect(sent, [
      {'practices': 'deep-work,gardening'}
    ]);
  });

  testWidgets('no Codex id is shown before one is minted, and a queued entry cannot be changed yet', (t) async {
    await t.pumpWidget(host(CodexControls(row: const {'ID': 'J2', 'CODEX_ID': '-'}, onSave: (f) async => true)));
    expect(find.text('Codex id'), findsNothing);
    await t.pumpWidget(host(CodexControls(row: const {'ID': 'QUEUED'}, onSave: (f) async => true)));
    expect(find.byType(Pill), findsNothing);
    expect(find.textContaining('once this has synced'), findsOneWidget);
  });
}