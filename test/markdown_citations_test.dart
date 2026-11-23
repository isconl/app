import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/util/markdown.dart';

/// BI26112305: a bare URL in a reference line reads as a short, tappable citation, never the raw address.
void main() {
  testWidgets('a bare URL renders as a citation with the site name, trailing full stop kept as text', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Markdown('Udland, M. (2026). *Capex set to reach 725 billion*. Yahoo Finance. https://www.finance.yahoo.com/markets/article/x-224901707.html.'),
        ),
      ),
    ));
    final text = tester.widgetList<RichText>(find.byType(RichText)).map((r) => r.text.toPlainText()).join('\n');
    expect(text, contains('[finance.yahoo.com]'));
    expect(text, isNot(contains('https://')));
    expect(text, contains('Yahoo Finance.'));
  });

  testWidgets('a markdown link is untouched by the citation rule', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: Markdown('See [the report](https://example.org/r) for detail.'))),
    ));
    final text = tester.widgetList<RichText>(find.byType(RichText)).map((r) => r.text.toPlainText()).join('\n');
    expect(text, contains('the report'));
    expect(text, isNot(contains('[example.org]')));
  });
}
