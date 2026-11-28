import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/util/markdown.dart';

/// BI26111904: no `{tag}` is ever shown raw. One sample of every tag in live use (movements, Document and Chronicle
/// sections, elements known and unknown, stray tags at the start of a heading, paragraph, list item or quote).
void main() {
  const source = '''
## {prologue} About This Part: Zero Budget Sourcing Architecture

Opening paragraph.

## {part} Part One: The Ground

**{concept} Who Decides What:** a concept body.

**{question} The Question:** an element the table did not know.

**{probe} Can You Send It?** a probe body.

## {chapter} The Turn: A Decade In Public

{scenarios} A stray paragraph tag.

- {indicators} a stray list item tag

> {rules} a stray quote tag

### {aside} A stray sub-heading tag

## {epilogue} Keep This: What The Part Teaches

Closing paragraph. Inline math stays: \$x_{n}\$.
''';

  test('stripStrayTags removes leading tags but keeps movement headings and element lines', () {
    final out = stripStrayTags(source);
    expect(out, contains('## {prologue} About This Part:'));
    expect(out, contains('**{concept} Who Decides What:**'));
    expect(out, contains('A stray paragraph tag.'));
    expect(out, isNot(contains('{scenarios}')));
    expect(out, isNot(contains('{indicators}')));
    expect(out, isNot(contains('{rules}')));
    expect(out, isNot(contains('{aside}')));
    expect(out, contains(r'x_{n}'));
  });

  testWidgets('no brace tag survives into the rendered module', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: Markdown(source)))));
    await tester.pump();
    for (final tag in ['prologue', 'part', 'chapter', 'epilogue', 'concept', 'question', 'probe', 'scenarios', 'indicators', 'rules', 'aside']) {
      expect(find.textContaining('{$tag}'), findsNothing, reason: '{$tag} shown raw');
    }
    expect(find.textContaining('Zero Budget Sourcing Architecture'), findsWidgets);
    expect(find.textContaining('A stray paragraph tag.'), findsWidgets);
  });
}
