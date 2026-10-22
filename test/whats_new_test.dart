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

void main() {
  group('BI26100531: when the sheet shows', () {
    test('a fresh install records the version and shows nothing', () async {
      final mem = _Memory();
      final wn = WhatsNew(mem, (_) async => fail('must not ask hub on a fresh install'));
      expect(await wn.pending('0.3.71'), isNull);
      expect(mem.value, '0.3.71');
    });

    test('the first launch after an update shows the notes once, and not again', () async {
      final mem = _Memory('0.3.70');
      final wn = WhatsNew(mem, (v) async => v == '0.3.71' ? '## Fixed\n- one' : '');
      expect(await wn.pending('0.3.71'), '## Fixed\n- one');
      await wn.markShown('0.3.71');
      expect(await wn.pending('0.3.71'), isNull);
    });

    test('an empty body shows nothing and is recorded', () async {
      final mem = _Memory('0.3.70');
      final wn = WhatsNew(mem, (_) async => '  \n');
      expect(await wn.pending('0.3.71'), isNull);
      expect(mem.value, '0.3.71');
    });

    test('a failed call shows nothing and is tried again next launch', () async {
      final mem = _Memory('0.3.70');
      var fail = true;
      final wn = WhatsNew(mem, (_) async => fail ? throw Exception('offline') : 'notes');
      expect(await wn.pending('0.3.71'), isNull);
      expect(mem.value, '0.3.70');
      fail = false;
      expect(await wn.pending('0.3.71'), 'notes');
    });

    test('the same or an older version shows nothing', () async {
      final wn = WhatsNew(_Memory('0.3.71'), (_) async => 'notes');
      expect(await wn.pending('0.3.71'), isNull);
      expect(await wn.pending('0.3.60'), isNull);
    });
  });

  group('BI26100531: notes as plain Markdown', () {
    test('headings, bullets and text; images and HTML are dropped', () {
      final lines = parseNotes('## Fixed\r\n- one ![x](https://e/x.png)\r\n\r\n<b>plain</b> line\r\n* two');
      expect(lines.map((l) => '${l.kind}:${l.text}').toList(), ['heading:Fixed', 'bullet:one', 'text:plain line', 'bullet:two']);
    });
  });

  group('BI26100531: the sheet', () {
    testWidgets('shows the title, the notes and a Close button that closes it', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                builder: (_) => const WhatsNewSheet(version: '0.3.71', notes: '## Fixed\n- one fix\n- see [the log](https://example.com/log)'),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('whats-new-title')), findsOneWidget);
      expect(find.text("What's new in 0.3.71"), findsOneWidget);
      expect(find.text('Fixed'), findsOneWidget);
      expect(find.textContaining('one fix', findRichText: true), findsOneWidget);
      await tester.tap(find.byKey(const Key('whats-new-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('whats-new-title')), findsNothing);
    });
  });
}
