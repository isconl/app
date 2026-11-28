import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/services/whats_new.dart';
import 'package:isconl/ui/whats_new_sheet.dart';

class _Memory implements VersionMemory {
  _Memory([this.value]);
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String version) async => value = version;
}

/// The asset text for a build at [version] with [current] notes and [history] entries (newest first).
String asset(String version, {List<String> added = const [], List<String> improved = const [], List<String> fixed = const [], List<Map<String, dynamic>> history = const []}) {
  String list(List<String> l) => '[${l.map((s) => '"$s"').join(',')}]';
  final h = history.map((e) => '{"version":"${e['version']}","new":${list((e['new'] as List?)?.cast<String>() ?? const [])},"improved":${list((e['improved'] as List?)?.cast<String>() ?? const [])},"fixed":${list((e['fixed'] as List?)?.cast<String>() ?? const [])}}').join(',');
  return '{"version":"$version","new":${list(added)},"improved":${list(improved)},"fixed":${list(fixed)},"history":[$h]}';
}

void main() {
  group('BI26101213: when the sheet shows, from the notes bundled in the build', () {
    test('a fresh install records the version and shows nothing, without reading the asset', () async {
      final mem = _Memory();
      final wn = WhatsNew(mem, () async => fail('must not read the asset on a fresh install'));
      expect(await wn.pending('0.3.71'), isNull);
      expect(mem.value, '0.3.71');
    });

    test('the first launch after an update shows this release once, and not again', () async {
      final mem = _Memory('0.3.70');
      final wn = WhatsNew(mem, () async => asset('0.3.71', added: ['A new thing.'], fixed: ['A fix.']));
      final n = (await wn.pending('0.3.71'))!;
      expect(n.heading, "What's new in 0.3.71");
      expect(n.groups.map((g) => g.label).toList(), ['New', 'Fixed']);
      expect(n.groups.first.items, ['A new thing.']);
      await wn.markShown('0.3.71');
      expect(await wn.pending('0.3.71'), isNull);
    });

    test('a phone that skipped versions sees the notes of every release it missed, merged, as Since the last one it saw', () async {
      final mem = _Memory('0.3.70');
      final wn = WhatsNew(
        mem,
        () async => asset('0.3.74', added: ['Four.'], history: [
          {'version': '0.3.73', 'new': ['Three.', 'Four.']},
          {'version': '0.3.72', 'improved': ['Two.']},
          {'version': '0.3.71', 'fixed': ['One.']},
          {'version': '0.3.70', 'new': ['Already seen.']},
        ]),
      );
      final n = (await wn.pending('0.3.74'))!;
      expect(n.heading, 'Since 0.3.70');
      final by = {for (final g in n.groups) g.label: g.items};
      expect(by['New'], ['Three.', 'Four.'], reason: 'oldest first, the repeat of Four. dropped');
      expect(by['Improved'], ['Two.']);
      expect(by['Fixed'], ['One.']);
      expect(by.values.expand((x) => x), isNot(contains('Already seen.')));
    });

    test('a release with no notes shows nothing and is recorded', () async {
      final mem = _Memory('0.3.70');
      final wn = WhatsNew(mem, () async => asset('0.3.71'));
      expect(await wn.pending('0.3.71'), isNull);
      expect(mem.value, '0.3.71');
    });

    test('an unreadable asset shows nothing and is tried again next launch', () async {
      final mem = _Memory('0.3.70');
      var broken = true;
      final wn = WhatsNew(mem, () async => broken ? throw Exception('missing') : asset('0.3.71', added: ['Back.']));
      expect(await wn.pending('0.3.71'), isNull);
      expect(mem.value, '0.3.70');
      broken = false;
      expect((await wn.pending('0.3.71'))!.groups.single.items, ['Back.']);
      expect(await WhatsNew(_Memory('0.3.70'), () async => 'not json').pending('0.3.71'), isNull);
    });

    test('the same or an older version shows nothing', () async {
      final wn = WhatsNew(_Memory('0.3.71'), () async => asset('0.3.71', added: ['x']));
      expect(await wn.pending('0.3.71'), isNull);
      expect(await wn.pending('0.3.60'), isNull);
    });

    test('the placeholder asset the repo carries (version 0.0.0, no notes) shows nothing', () async {
      final wn = WhatsNew(_Memory('0.3.70'), () async => '{"version":"0.0.0","new":[],"improved":[],"fixed":[],"history":[]}');
      expect(await wn.pending('0.3.71'), isNull);
    });
  });

  group('BI26101213: the sheet', () {
    testWidgets('shows the heading, each group with its lines, and a Close button that closes it', (tester) async {
      const notes = WhatsNewNotes(heading: "What's new in 0.3.71", groups: [
        NoteGroup('New', ['A new screen.']),
        NoteGroup('Fixed', ['A crash on start.', 'A wrong colour.']),
      ]);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showModalBottomSheet<void>(context: context, builder: (_) => const WhatsNewSheet(notes: notes)),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text("What's new in 0.3.71"), findsOneWidget);
      expect(find.byKey(const Key('whats-new-group-New')), findsOneWidget);
      expect(find.byKey(const Key('whats-new-group-Fixed')), findsOneWidget);
      expect(find.byKey(const Key('whats-new-group-Improved')), findsNothing);
      expect(find.text('A new screen.'), findsOneWidget);
      expect(find.text('A wrong colour.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('whats-new-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('whats-new-title')), findsNothing);
    });
  });
}
