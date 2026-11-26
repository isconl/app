// BI26112301: several anchored, timed notes per module, kept inside the one text the server stores per module.
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/data/note_entries.dart';

void main() {
  final t1 = DateTime.utc(2026, 11, 26, 18, 30);
  final t2 = DateTime.utc(2026, 11, 26, 18, 41);

  test('a plain old note is one entry with no anchor and writes back unchanged', () {
    final es = parseNoteEntries('  my old note\nline two ');
    expect(es.single.id, 'legacy');
    expect(es.single.anchor, isNull);
    expect(serializeNoteEntries(es), 'my old note\nline two');
    expect(parseNoteEntries('   '), isEmpty);
  });

  test('entries round-trip with anchor, times and a quote holding quotes and arrows', () {
    final es = [
      NoteEntry(id: 'a', text: 'first thought', anchor: 3, quote: 'Ship the "base" --> phrase', created: t1),
      NoteEntry(id: 'b', text: 'second\n\nwith a blank line', anchor: 7, created: t1, edited: t2),
    ];
    final text = serializeNoteEntries(es);
    expect(text, contains('<!-- note id=a anchor=3 created=2026-11-26T18:30:00Z quote='));
    final back = parseNoteEntries(text);
    expect(back.map((e) => e.id), ['a', 'b']);
    expect(back[0].anchor, 3);
    expect(back[0].quote, 'Ship the "base" - -> phrase');
    expect(back[0].created, t1);
    expect(back[1].text, 'second\n\nwith a blank line');
    expect(back[1].edited, t2);
  });

  test('text written before the first marker is kept as a legacy entry', () {
    final text = 'old words\n\n${serializeNoteEntries([NoteEntry(id: 'x', text: 'new', anchor: 1, created: t1)])}';
    final es = parseNoteEntries(text);
    expect(es.map((e) => e.id), ['legacy', 'x']);
    expect(serializeNoteEntries(es), startsWith('<!-- note id=legacy -->\nold words'));
  });

  test('empty entries are dropped when written', () {
    expect(serializeNoteEntries([NoteEntry(id: 'a', text: '  ', anchor: 1, created: t1)]), '');
  });

  test('readable text shows each entry under its time, without markers', () {
    final text = serializeNoteEntries([
      NoteEntry(id: 'a', text: 'one', anchor: 0, quote: 'Hello there', created: t1),
      NoteEntry(id: 'b', text: 'two', anchor: 2, created: t1, edited: t2),
    ]);
    final r = readableNoteText(text);
    expect(r, isNot(contains('<!--')));
    expect(r, contains(noteTime(t1)));
    expect(r, contains('edited'));
    expect(r, contains('"Hello there"'));
    expect(readableNoteText('just text'), 'just text');
  });

  test('quoteOf takes the first words without tags or markdown', () {
    expect(quoteOf('**{concept} Fixed Base:** the base phrase has three parts, and each one'), 'Fixed Base: the base phrase has');
  });
}
