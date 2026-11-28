
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/study/cdm/cdm_model.dart';

void main() {
  test('a deck document becomes plain reading text, author-only blocks left out', () {
    final doc = CdmDoc.fromJson({
      'headline': 'Ohm and volt',
      'subtitle': 'A first look',
      'sections': [
        {
          'type': 'section',
          'title': 'The idea',
          'nodes': [
            {'type': 'paragraph', 'text': 'Voltage pushes current.'},
            {'type': 'list', 'items': ['First point.', {'text': 'Second point.'}]},
            {'type': 'paragraph', 'text': 'Do not read me.', 'aud': ['author']},
            {'type': 'unknown_block', 'payload': {'x': 1}},
          ],
        },
      ],
    });
    final md = cdmSpeakableMarkdown(doc);
    expect(md, contains('# Ohm and volt'));
    expect(md, contains('## The idea'));
    expect(md, contains('Voltage pushes current.'));
    expect(md, contains('Second point.'));
    expect(md, isNot(contains('Do not read me')));
    expect(md, isNot(contains('payload')));
  });
}
