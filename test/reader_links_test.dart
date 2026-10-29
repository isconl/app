// BI26102805: links in lessons work. Every link form of standard §8.2 and §8.3 reaches its handler, and a module
// link finds a 4.x module by the number inside its file name (the cause of "links do nothing": only files starting
// with the number matched, and 4.x files carry it inside the name).
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/util/markdown.dart';

const _lesson = '''## {master} Going Deeper: Reading The Numbers

A paragraph with [[link:the next module|module:applied-financial-intelligence/02]] in it.

**{link} See Also:** [[link:the section on yields|module:applied-financial-intelligence/03#grasp-1]]

Read [[link:the KRA guide|https://www.kra.go.ke/]] for the rules.
''';

TextSpan? _span(WidgetTester t, String text) {
  TextSpan? found;
  for (final r in t.widgetList<RichText>(find.byType(RichText))) {
    r.text.visitChildren((s) {
      if (s is TextSpan && s.text == text) {
        found = s;
        return false;
      }
      return true;
    });
    if (found != null) break;
  }
  return found;
}

void main() {
  group('ModuleLink.matchesFile', () {
    test('a 4.x file is found by the module number inside its name', () {
      final link = ModuleLink.parse('module:applied-financial-intelligence/02')!;
      expect(link.matchesFile('20261006_wealth_finance_applied_financial_intelligence_module_02_money_that_doubles_v4_0_0.md'), isTrue);
      expect(link.matchesFile('20261006_wealth_finance_applied_financial_intelligence_module_01_assets_that_pay_v4_0_0.md'), isFalse);
      expect(link.matchesFile('20261006_wealth_finance_applied_financial_intelligence_module_12_later_v4_0_0.md'), isFalse);
      expect(link.matchesFile('20261006_wealth_finance_applied_financial_intelligence_module_20_later_v4_0_0.md'), isFalse);
    });

    test('an older file is still found by the number it starts with', () {
      final link = ModuleLink.parse('module:finance/02')!;
      expect(link.matchesFile('02_compounding.md'), isTrue);
      expect(link.matchesFile('020_other.md'), isFalse);
      expect(link.matchesFile('12_other.md'), isFalse);
    });

    test('the anchor form parses its section', () {
      final link = ModuleLink.parse('module:applied-financial-intelligence/03#grasp-1')!;
      expect((link.course, link.index, link.anchor), ('applied-financial-intelligence', '03', 'grasp-1'));
    });
  });

  testWidgets('a module link in a paragraph and in a {link} line reaches the handler with its course, number and anchor',
      (t) async {
    final tapped = <ModuleLink>[];
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Markdown(_lesson, variant: MarkdownVariant.reading, onModuleLink: tapped.add),
        ),
      ),
    ));
    final para = _span(t, 'the next module');
    expect(para, isNotNull);
    (para!.recognizer! as TapGestureRecognizer).onTap!();
    final line = _span(t, 'the section on yields');
    expect(line, isNotNull, reason: 'the {link} element is a quiet line whose link still works');
    (line!.recognizer! as TapGestureRecognizer).onTap!();
    expect(tapped.map((l) => l.toString()), [
      'module:applied-financial-intelligence/02',
      'module:applied-financial-intelligence/03#grasp-1',
    ]);
  });

  testWidgets('a web link is a tappable link with its address, never a jargon popup', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: Markdown(_lesson, variant: MarkdownVariant.reading))),
    ));
    final web = _span(t, 'the KRA guide');
    expect(web, isNotNull);
    expect(web!.recognizer, isA<TapGestureRecognizer>());
    expect(web.style?.decoration, TextDecoration.underline);
  });
}
