import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/services/parity3b.dart';
import 'package:isconl/theme.dart';
import 'package:isconl/ui/widgets/parity3b_widgets.dart';

class FakeApi implements Parity3bApi {
  final calls = <String>[];
  int draftNo = 0;
  Object? failChase;
  Adherence adh = const Adherence(days: 7, perBlock: [], recommendations: []);
  String? theme;
  int raised = 0;
  Object? failDelete;

  @override
  Future<ChaseDraft> chase(String id) async {
    calls.add('chase:$id');
    if (failChase != null) throw failChase!;
    return ChaseDraft(
      id: id, by: 'Alex', date: '2026-10-01', to: 'Alex Doe', channel: 'email',
      body: 'Hi Alex, draft ${++draftNo}.',
      checks: const [(found: 'Friday', say: 'check the date is still right')],
    );
  }

  @override
  Future<void> rechase(String id) async => calls.add('rechase:$id');
  @override
  Future<void> deleteDate(String id) async {
    if (failDelete != null) throw failDelete!;
    calls.add('delete:$id');
  }

  @override
  Future<Adherence> adherence({int days = 7}) async => adh;
  @override
  Future<String?> themeDay() async => theme;
  @override
  Future<int> sweep() async {
    calls.add('sweep');
    return raised;
  }
}

Widget host(Widget w) => MaterialApp(theme: buildTheme(), home: Scaffold(body: SingleChildScrollView(child: w)));

void main() {
  group('chase', () {
    testWidgets('shows who, how and the exact text, and sends nothing itself', (t) async {
      final api = FakeApi();
      await t.pumpWidget(MaterialApp(theme: buildTheme(), home: Scaffold(body: ChaseSheet(api: api, decisionId: 'D-7'))));
      await t.pumpAndSettle();
      expect(find.text('To Alex Doe via email'), findsOneWidget);
      expect(t.widget<TextField>(find.byKey(const Key('chase-text'))).controller!.text, 'Hi Alex, draft 1.');
      expect(find.textContaining('Friday: check the date'), findsOneWidget);
      expect(api.calls, ['chase:D-7']); // only the read
    });

    testWidgets('Copy message copies what the reader left in the box, edited', (t) async {
      String? copied;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
        return null;
      });
      addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      final api = FakeApi();
      await t.pumpWidget(MaterialApp(theme: buildTheme(), home: Scaffold(body: ChaseSheet(api: api, decisionId: 'D-7'))));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('chase-text')), 'My own words.');
      await t.tap(find.byKey(const Key('chase-copy')));
      await t.pumpAndSettle();
      expect(copied, 'My own words.');
      expect(find.textContaining('Copied'), findsOneWidget);
    });

    testWidgets('Different angle asks for a rewrite then reads the new draft', (t) async {
      final api = FakeApi();
      await t.pumpWidget(MaterialApp(theme: buildTheme(), home: Scaffold(body: ChaseSheet(api: api, decisionId: 'D-7'))));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('chase-again')));
      await t.pumpAndSettle();
      expect(api.calls, ['chase:D-7', 'rechase:D-7', 'chase:D-7']);
      expect(t.widget<TextField>(find.byKey(const Key('chase-text'))).controller!.text, 'Hi Alex, draft 2.');
    });

    testWidgets('a decision with no draft available says why', (t) async {
      final api = FakeApi()..failChase = Exception('No draft yet');
      await t.pumpWidget(MaterialApp(theme: buildTheme(), home: Scaffold(body: ChaseSheet(api: api, decisionId: 'D-7'))));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('chase-error')), findsOneWidget);
    });
  });

  group('delete a date', () {
    Future<void> open(WidgetTester t, FakeApi api, List<bool> results) async {
      await t.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              key: const Key('go'),
              onPressed: () async => results.add(await confirmDeleteDate(ctx, 'd1', 'Mum birthday', api: api)),
              child: const Text('go'),
            ),
          ),
        ),
      ));
      await t.tap(find.byKey(const Key('go')));
      await t.pumpAndSettle();
    }

    testWidgets('asks to confirm, says what happens, and Keep it deletes nothing', (t) async {
      final api = FakeApi();
      final results = <bool>[];
      await open(t, api, results);
      expect(find.textContaining('Nothing else is touched'), findsOneWidget);
      await t.tap(find.text('Keep it'));
      await t.pumpAndSettle();
      expect(results, [false]);
      expect(api.calls, isEmpty);
    });

    testWidgets('confirming deletes it', (t) async {
      final api = FakeApi();
      final results = <bool>[];
      await open(t, api, results);
      await t.tap(find.byKey(const Key('date-delete-confirm')));
      await t.pumpAndSettle();
      expect(results, [true]);
      expect(api.calls, ['delete:d1']);
    });

    testWidgets('a refusal is shown and nothing is reported as deleted', (t) async {
      final api = FakeApi()..failDelete = Exception('Locked');
      final results = <bool>[];
      await open(t, api, results);
      await t.tap(find.byKey(const Key('date-delete-confirm')));
      await t.pumpAndSettle();
      expect(results, [false]);
      expect(find.textContaining('Locked'), findsOneWidget);
    });
  });

  group('adherence card', () {
    testWidgets('lists worked blocks with minutes and a percentage, and the recommendations', (t) async {
      final api = FakeApi()
        ..adh = const Adherence(days: 7, perBlock: [
          BlockAdherence(day: 'Mon', name: 'Deep work', loggedMinutes: 95.4, sessionCount: 3, adherencePct: 82),
          BlockAdherence(day: 'Tue', name: 'Admin', loggedMinutes: 30, sessionCount: 1, adherencePct: 40),
          BlockAdherence(day: 'Wed', name: 'Unused', loggedMinutes: 0, sessionCount: 0),
        ], recommendations: ['Protect Monday mornings']);
      await t.pumpWidget(host(AdherenceCard(api: api)));
      await t.pumpAndSettle();
      expect(find.text('last 7 days'), findsOneWidget);
      expect(find.text('Mon Deep work'), findsOneWidget);
      expect(find.text('95m logged'), findsOneWidget);
      expect(find.text('82% on purpose'), findsOneWidget);
      expect(find.text('40% on purpose'), findsOneWidget);
      expect(find.text('Wed Unused'), findsNothing); // not worked
      expect(find.textContaining('Protect Monday mornings'), findsOneWidget);
    });

    testWidgets('no sessions says how to get some', (t) async {
      await t.pumpWidget(host(AdherenceCard(api: FakeApi())));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('adherence-empty')), findsOneWidget);
    });

    test('parses the console shape and rejects an error body', () {
      final a = HubParity3bApi.parseAdherence({
        'days': 7,
        'perBlock': [{'day': 'Mon', 'name': 'X', 'loggedMinutes': 10, 'sessionCount': 2, 'adherencePct': 71.6}],
        'recommendations': ['a'],
      });
      expect(a.touched.single.adherencePct, 72);
      expect(() => HubParity3bApi.parseAdherence({'error': 'no data'}), throwsA(anything));
    });
  });

  group('theme of the day', () {
    testWidgets('shows the phrase when there is one', (t) async {
      await t.pumpWidget(host(ThemeOfDayLine(api: FakeApi()..theme = 'Build the boring parts first')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('theme-of-day')), findsOneWidget);
      expect(find.text('Build the boring parts first'), findsOneWidget);
    });

    testWidgets('shows nothing when there is none', (t) async {
      await t.pumpWidget(host(ThemeOfDayLine(api: FakeApi())));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('theme-of-day')), findsNothing);
    });
  });

  group('sweep', () {
    testWidgets('reports what it raised, singular and plural, and none', (t) async {
      final api = FakeApi();
      var refreshed = 0;
      await t.pumpWidget(host(SweepButton(api: api, onDone: () async => refreshed++)));
      api.raised = 3;
      await t.tap(find.byKey(const Key('sweep-button')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('3 new notices'), findsOneWidget);
      expect(refreshed, 1);
      expect(sweepMessage(1), '1 new notice');
      expect(sweepMessage(0), 'Nothing new. Everything is already noticed.');
    });
  });
}
