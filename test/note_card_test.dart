// BI26112301: the note card floats above the keyboard with its actions in sight, keeps two paragraphs' notes apart,
// and stamps each entry with its time.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/data/lesson_notes.dart';
import 'package:isconl/data/mutations.dart' show MutationResult;
import 'package:isconl/data/note_entries.dart';
import 'package:isconl/ui/widgets/note_card.dart';

class _FakeNotes implements LessonNotesRepository {
  String text = '';
  int sends = 0;

  @override
  Future<LessonNote?> getNote({required String course, required String file}) async =>
      text.isEmpty ? null : LessonNote(course: course, file: file, text: text);

  @override
  Future<void> saveDraft({required String course, required String file, required String text, int? anchor, String? title}) async =>
      this.text = text;

  @override
  Future<MutationResult> saveNote({required String course, required String file, required String text, int? anchor, String? title}) async {
    this.text = text;
    sends++;
    return MutationResult.sent();
  }

  @override
  Future<MutationResult> pushOne({required String course, required String file}) async => MutationResult.sent();

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Widget _host(Widget child, {double keyboard = 0}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: const Size(400, 800), viewInsets: EdgeInsets.only(bottom: keyboard)),
        child: Material(child: child),
      ),
    );

void main() {
  final clock = DateTime.utc(2026, 11, 26, 18, 30);

  testWidgets('with the keyboard up the card sits just above it, Save, Sync, New and All in one row', (t) async {
    t.view.physicalSize = const Size(400, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final repo = _FakeNotes();
    await t.pumpWidget(_host(NoteCard(course: 'c', file: 'm.md', title: 'Module 9', anchor: 2, quote: 'The base', repository: repo, now: () => clock), keyboard: 300));
    await t.pumpAndSettle();
    final card = t.getRect(find.byKey(const Key('note-card')));
    expect(card.bottom, lessThanOrEqualTo(800 - 300));
    expect(card.bottom, greaterThan(800 - 300 - 40), reason: 'the lower edge rides just above the keyboard');
    final ys = ['note-save', 'note-sync', 'note-new', 'note-all'].map((k) => t.getCenter(find.byKey(Key(k))).dy).toSet();
    expect(ys.length, 1, reason: 'the four actions share one row');
  });

  testWidgets('two paragraphs keep separate notes, each entry timed', (t) async {
    final repo = _FakeNotes();
    await t.pumpWidget(_host(NoteCard(course: 'c', file: 'm.md', anchor: 1, quote: 'first para', repository: repo, now: () => clock)));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('note-field')), 'note on one');
    await t.tap(find.byKey(const Key('note-save')));
    await t.pumpAndSettle();
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(_host(NoteCard(course: 'c', file: 'm.md', anchor: 4, quote: 'fourth para', repository: repo, now: () => clock)));
    await t.pumpAndSettle();
    expect(find.text('note on one'), findsNothing, reason: 'paragraph 5 starts empty');
    await t.enterText(find.byKey(const Key('note-field')), 'note on four');
    await t.tap(find.byKey(const Key('note-save')));
    await t.pumpAndSettle();
    final es = parseNoteEntries(repo.text);
    expect(es.map((e) => (e.anchor, e.text)), [(1, 'note on one'), (4, 'note on four')]);
    expect(es.every((e) => e.created == clock), isTrue);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('New note on the same paragraph adds a second entry and the first shows its time', (t) async {
    final repo = _FakeNotes()
      ..text = serializeNoteEntries([NoteEntry(id: 'a', text: 'earlier thought', anchor: 1, created: clock)]);
    await t.pumpWidget(_host(NoteCard(course: 'c', file: 'm.md', anchor: 1, repository: repo, now: () => clock)));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('note-new')));
    await t.pumpAndSettle();
    expect(find.text('earlier thought'), findsOneWidget);
    expect(find.text(noteTime(clock)), findsOneWidget);
    await t.enterText(find.byKey(const Key('note-field')), 'later thought');
    await t.tap(find.byKey(const Key('note-save')));
    await t.pumpAndSettle();
    expect(parseNoteEntries(repo.text).map((e) => e.text), ['earlier thought', 'later thought']);
    await t.pumpWidget(const SizedBox());
  });
}
