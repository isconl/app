// BI26112301: a module's notes as anchored notes of timestamped entries, stored as markdown the server already takes.
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/data/note_doc.dart';

void main() {
  test('a note written before v2 reads as one note with one entry, dated by its save', () {
    final at = DateTime(2026, 11, 19, 8, 41);
    final doc = NoteDoc.parse('my old note\n\nsecond line', legacyAnchor: 3, legacyAt: at);
    expect(doc.notes.single.anchor, 3);
    expect(doc.notes.single.saved.single.text, 'my old note\n\nsecond line');
    expect(doc.notes.single.saved.single.createdAt, at);
    expect(doc.readable(), 'my old note\n\nsecond line', reason: 'an old note reads exactly as before');
  });

  test('serialize then parse keeps every note, anchor, quote, entry and time', () {
    final t0 = DateTime(2026, 11, 23, 8, 41);
    final doc = NoteDoc();
    final a = doc.add(anchor: 4, quote: 'Price discovery starts with "the" buyer', now: t0);
    a.entries.add(NoteEntry(id: 'e1', text: 'first\n\nwith a blank line', createdAt: t0));
    a.entries.add(NoteEntry(id: 'e2', text: 'edited later', createdAt: t0, updatedAt: t0.add(const Duration(minutes: 20))));
    final b = doc.add(now: t0);
    b.entries.add(NoteEntry(id: 'e3', text: 'change of topic', createdAt: t0, draft: true));
    doc.add(); // empty: dropped

    final text = doc.serialize();
    expect(text, startsWith(noteDocMarker));
    expect(text, contains('## Paragraph 5: Price discovery'));
    expect(text, contains('### 23 Nov 2026, 08:41'));

    final back = NoteDoc.parse(text);
    expect(back.notes.length, 2);
    expect(back.notes[0].anchor, 4);
    expect(back.notes[0].quote, "Price discovery starts with 'the' buyer");
    expect(back.notes[0].saved.map((e) => e.text), ['first\n\nwith a blank line', 'edited later']);
    expect(back.notes[0].saved[1].edited, isTrue);
    expect(back.notes[0].saved[1].stamp(now: t0), '23 Nov, 08:41 · edited 09:01');
    expect(back.notes[1].anchor, isNull);
    expect(back.notes[1].draft?.text, 'change of topic');
    expect(back.serialize(), text, reason: 'stable across round trips');
  });

  test('the readable form has headings and times but none of the app comments', () {
    final t0 = DateTime(2026, 11, 23, 8, 41);
    final doc = NoteDoc();
    doc.add(anchor: 0, quote: 'One', now: t0).entries.add(NoteEntry(id: 'e', text: 'hello', createdAt: t0));
    final r = doc.readable();
    expect(r, isNot(contains('<!--')));
    expect(r, contains('## Paragraph 1: One'));
    expect(r, contains('hello'));
  });

  test('a paragraph is found again by its first words even when its index moved', () {
    final doc = NoteDoc();
    doc.add(anchor: 4, quote: paragraphQuote('**Price** discovery starts with the buyer, not the seller.'));
    expect(doc.forParagraph(6, paragraphQuote('Price discovery starts with the buyer, not the seller.')), isNotNull);
    expect(doc.forParagraph(4, paragraphQuote('A different paragraph now.')), isNull);
  });

  test('text typed outside any entry (edited by hand on the web) is kept', () {
    final doc = NoteDoc.parse('$noteDocMarker\n\nloose words\n');
    expect(doc.notes.single.saved.single.text, 'loose words');
  });
}
