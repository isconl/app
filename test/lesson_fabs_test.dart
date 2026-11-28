import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/api/client.dart';
import 'package:isconl/data/db.dart';
import 'package:isconl/data/lesson_notes.dart';
import 'package:isconl/data/mutations.dart';
import 'package:isconl/data/outbox.dart';
import 'package:isconl/data/store.dart';
import 'package:isconl/data/sync.dart';
import 'package:isconl/theme.dart';
import 'package:isconl/ui/widgets/brand.dart';
import 'package:isconl/ui/views/learning.dart';
import 'package:isconl/ui/widgets/common.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeApiClient extends ApiClient {
  FakeApiClient() : super(baseUrl: 'http://test', token: 'test');

  final Map<String, Map<String, dynamic>> _storage = {};

  @override
  Future<dynamic> getJson(String path, {bool cold = false, bool stored = true}) async {
    final uri = Uri.parse(path);
    final course = uri.queryParameters['course'] ?? '';
    final file = uri.queryParameters['file'] ?? '';
    final key = '$course/$file';
    return _storage[key] ?? <String, dynamic>{'text': ''};
  }

  @override
  Future<dynamic> postJson(String path, Map<String, dynamic> body, {bool cold = false}) async {
    final course = body['course']?.toString() ?? '';
    final file = body['file']?.toString() ?? '';
    final key = '$course/$file';
    _storage[key] = {
      'text': body['text'] ?? '',
      'anchor': body['anchor'],
    };
    return <String, dynamic>{'ok': true};
  }
}

class FakeLessonNotesRepository implements LessonNotesRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  LessonNote? note;
  String? lastSavedCourse;
  String? lastSavedFile;
  String? lastSavedText;
  int? lastSavedAnchor;
  int drafts = 0;

  @override
  Future<LessonNote?> getNote({required String course, required String file}) async {
    return note;
  }

  @override
  Future<void> saveDraft({
    required String course,
    required String file,
    required String text,
    int? anchor,
    String? title,
  }) async {
    drafts++;
    lastSavedText = text;
  }

  @override
  Future<MutationResult> pushOne({required String course, required String file}) async =>
      MutationResult.sent();

  @override
  Future<MutationResult> saveNote({
    required String course,
    required String file,
    required String text,
    int? anchor,
    String? title,
  }) async {
    lastSavedCourse = course;
    lastSavedFile = file;
    lastSavedText = text;
    lastSavedAnchor = anchor;
    note = LessonNote(course: course, file: file, text: text, anchor: anchor);
    return MutationResult.sent();
  }
}

/// BI26111402: answers by path, to prove how the outbox treats each kind of answer.
class ScriptedApi extends FakeApiClient {
  ScriptedApi(this.answers);
  final Map<String, Object> answers; // path -> ApiException/OfflineException to throw, or anything to succeed
  final List<String> posted = [];
  @override
  Future<dynamic> postJson(String path, Map<String, dynamic> body, {bool cold = false}) async {
    posted.add(path);
    final a = answers[path];
    if (a is Exception) throw a;
    return <String, dynamic>{'ok': true};
  }
}

/// A server that can be switched off, to prove notes wait on the phone.
class FlakyNotesApi extends FakeApiClient {
  bool down = false;
  int posts = 0;
  @override
  Future<dynamic> getJson(String path, {bool cold = false, bool stored = true}) async {
    if (down) throw OfflineException();
    return super.getJson(path, cold: cold, stored: stored);
  }

  @override
  Future<dynamic> postJson(String path, Map<String, dynamic> body, {bool cold = false}) async {
    if (down) throw ApiException(502, 'Bad gateway');
    posts++;
    return super.postJson(path, body, cold: cold);
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<AppDb> freshDb() async {
    final rawDb = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        singleInstance: false,
        version: 4,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE lesson_notes (
              course TEXT NOT NULL,
              file TEXT NOT NULL,
              text TEXT NOT NULL,
              anchor INTEGER,
              updated_at INTEGER NOT NULL,
              PRIMARY KEY (course, file)
            )''');
          await db.execute('''
            CREATE TABLE snapshots (
              key TEXT PRIMARY KEY,
              json TEXT NOT NULL,
              fetched_at INTEGER NOT NULL
            )''');
          await db.execute('''
            CREATE TABLE outbox (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              method TEXT NOT NULL,
              path TEXT NOT NULL,
              body TEXT NOT NULL,
              label TEXT NOT NULL,
              view TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              status TEXT NOT NULL DEFAULT 'pending',
              error TEXT
            )''');
        },
      ),
    );
    return AppDb.forTesting(rawDb);
  }

  group('BI26092614: CircleFab widget', () {
    testWidgets('CircleFab renders as a green circle', (tester) async {
      var tapped = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          floatingActionButton: CircleFab(
            icon: const Icon(Icons.forum_rounded),
            tooltip: 'Chat',
            onPressed: () => tapped = true,
          ),
        ),
      ));

      final fabFinder = find.byType(FloatingActionButton);
      expect(fabFinder, findsOneWidget);

      final fab = tester.widget<FloatingActionButton>(fabFinder);
      expect(fab.backgroundColor, C.green);
      expect(fab.foregroundColor, C.textInverse);

      expect(fab.shape, isA<CircleBorder>());

      await tester.tap(fabFinder);
      expect(tapped, isTrue);
    });

    testWidgets('CircleFab supports custom colors and tooltip', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          floatingActionButton: CircleFab(
            icon: const Icon(Icons.edit_note_rounded),
            backgroundColor: C.surface,
            foregroundColor: C.text,
            tooltip: 'Custom tooltip',
            onPressed: () {},
          ),
        ),
      ));

      final fab = tester.widget<FloatingActionButton>(find.byType(FloatingActionButton));
      expect(fab.backgroundColor, C.surface);
      expect(fab.foregroundColor, C.text);
      expect(fab.tooltip, 'Custom tooltip');
    });
  });

  group('BI26100122: floating buttons', () {
    testWidgets('the theme default is a green circle, so a raw FloatingActionButton cannot drift', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: Scaffold(floatingActionButton: FloatingActionButton(onPressed: () {}, child: const Icon(Icons.add))),
      ));
      final theme = Theme.of(tester.element(find.byType(FloatingActionButton))).floatingActionButtonTheme;
      expect(theme.shape, isA<CircleBorder>());
      expect(theme.backgroundColor, C.green);
    });

    testWidgets('the mono mark paints in the colour it is given at the size it is given', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Center(child: MonoBrandMark(color: C.textInverse, size: 24)))));
      expect(tester.getSize(find.byType(MonoBrandMark)), const Size(24, 24));
      expect(find.byType(CustomPaint), findsWidgets);
    });
  });

  group('BI26092614: LessonNotesRepository SQLite & mutations', () {
    test('save then read round-trips note text and block anchor', () async {
      final db = await freshDb();
      final fakeApi = FakeApiClient();
      final store = Store(db, () => fakeApi);
      final outbox = OutboxService(db, () => fakeApi);
      final sync = SyncEngine(store, outbox, () => fakeApi);
      final mutations = Mutations(store, outbox, sync, () => fakeApi);
      final repo = LessonNotesRepository(apiOf: () => fakeApi, mutations: mutations, db: db);

      await repo.saveNote(
        course: 'med-anatomy',
        file: '00-orientation.md',
        text: 'Crucial distinction on cranial nerves.',
        anchor: 3,
      );

      final note = await repo.getNote(
        course: 'med-anatomy',
        file: '00-orientation.md',
      );

      expect(note, isNotNull);
      expect(note!.course, 'med-anatomy');
      expect(note.file, '00-orientation.md');
      expect(note.text, 'Crucial distinction on cranial nerves.');
      expect(note.anchor, 3);
    });

    test('saving second time replaces previous note for the same lesson', () async {
      final db = await freshDb();
      final fakeApi = FakeApiClient();
      final store = Store(db, () => fakeApi);
      final outbox = OutboxService(db, () => fakeApi);
      final sync = SyncEngine(store, outbox, () => fakeApi);
      final mutations = Mutations(store, outbox, sync, () => fakeApi);
      final repo = LessonNotesRepository(apiOf: () => fakeApi, mutations: mutations, db: db);

      await repo.saveNote(
        course: 'med-anatomy',
        file: '00-orientation.md',
        text: 'Initial note',
        anchor: 1,
      );

      await repo.saveNote(
        course: 'med-anatomy',
        file: '00-orientation.md',
        text: 'Updated note with new anchor',
        anchor: 5,
      );

      final note = await repo.getNote(
        course: 'med-anatomy',
        file: '00-orientation.md',
      );

      expect(note, isNotNull);
      expect(note!.text, 'Updated note with new anchor');
      expect(note.anchor, 5);
    });
  });

  group('BI26092614: LessonNotes UI widget', () {
    testWidgets('renders note editor, autosaves, and saves on the button', (tester) async {
      final repo = FakeLessonNotesRepository();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LessonNotes(
              course: 'corp-law',
              file: '02-contracts.md',
              anchor: 4,
              inSheet: true,
              repository: repo,
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('NOTES'), findsOneWidget);
      expect(find.textContaining('Anchored to paragraph 5'), findsOneWidget);
      expect(find.text('Save and close'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Important indemnity clause notes.');
      await tester.pump(const Duration(milliseconds: 800));
      expect(repo.drafts, 1, reason: 'a pause in typing saves on the phone');
      expect(find.text('Saved on this phone'), findsOneWidget);

      await tester.tap(find.byKey(const Key('note-save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(repo.lastSavedCourse, 'corp-law');
      expect(repo.lastSavedFile, '02-contracts.md');
      expect(repo.lastSavedText, 'Important indemnity clause notes.');
      expect(repo.lastSavedAnchor, 4);
      expect(find.textContaining('Synced'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('BI26111402: notes wait on the phone and sync themselves', () {
    Future<(LessonNotesRepository, FlakyNotesApi, AppDb)> setup() async {
      final db = await freshDb();
      final api = FlakyNotesApi();
      final store = Store(db, () => api);
      final outbox = OutboxService(db, () => api);
      final sync = SyncEngine(store, outbox, () => api);
      final mutations = Mutations(store, outbox, sync, () => api);
      return (LessonNotesRepository(apiOf: () => api, mutations: mutations, db: db), api, db);
    }

    test('a note saved while the server is down is kept, then pushAll sends it', () async {
      final (repo, api, _) = await setup();
      api.down = true;
      final r = await repo.saveNote(course: 'c', file: 'm1.md', text: 'idea one');
      expect(r.ok, isTrue);
      expect(r.queued, isTrue);
      expect(repo.waiting, 1);

      api.down = false;
      expect(await repo.pushAll(), 1);
      expect(repo.waiting, 0);
      final n = await repo.getNote(course: 'c', file: 'm1.md');
      expect(n!.text, 'idea one');
      expect(n.sync, NoteSync.synced);
      expect(await repo.pushAll(), 0, reason: 'nothing is sent twice');
    });

    test('an unsent edit on the phone is never replaced by the older server copy', () async {
      final (repo, api, _) = await setup();
      await repo.saveNote(course: 'c', file: 'm1.md', text: 'old');
      api.down = true;
      await repo.saveNote(course: 'c', file: 'm1.md', text: 'newer, unsent');
      api.down = false;
      final n = await repo.getNote(course: 'c', file: 'm1.md');
      expect(n!.text, 'newer, unsent');
    });

    test('notes written before the update (no synced_at) are pushed once', () async {
      final (repo, api, db) = await setup();
      await db.saveLessonNoteLocal(course: 'c', file: 'a.md', text: 'from this morning');
      await db.saveLessonNoteLocal(course: 'c', file: 'b.md', text: '');
      expect(await repo.pushAll(), 1, reason: 'the empty never-sent note is skipped');
      expect(api.posts, 1);
    });

    test('export lists every note under its course', () async {
      final (repo, _, _) = await setup();
      await repo.saveNote(course: 'c', file: '20261114_x_module_03_three_messages_v4_8_0.md', text: 'ask Joel');
      final md = await repo.exportMarkdown(now: DateTime(2026, 11, 14));
      expect(md, contains('# Study notes, 2026-11-14'));
      expect(md, contains('## c'));
      expect(md, contains('Module 3: three messages'));
      expect(md, contains('ask Joel'));
    });
  });

  group('BI26092614: Reader FAB Stack and Scroll-to-Top visibility', () {
    testWidgets('Scroll-to-top FAB appears only after scrolling past threshold', (tester) async {
      final scroll = ScrollController();

      await tester.pumpWidget(MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            final showScrollTop = scroll.hasClients && scroll.offset > 400;
            scroll.addListener(() {
              final show = scroll.hasClients && scroll.offset > 400;
              if (show != showScrollTop) setState(() {});
            });

            return Scaffold(
              floatingActionButton: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleFab(
                    heroTag: 'fab_notes',
                    tooltip: 'Notes',
                    icon: const Icon(Icons.edit_note_rounded),
                    onPressed: () {},
                  ),
                  if (showScrollTop)
                    CircleFab(
                      heroTag: 'fab_top',
                      tooltip: 'Scroll to top',
                      icon: const Icon(Icons.vertical_align_top_rounded),
                      onPressed: () => scroll.jumpTo(0),
                    ),
                ],
              ),
              body: ListView.builder(
                controller: scroll,
                itemCount: 50,
                itemExtent: 50,
                itemBuilder: (ctx, i) => Text('Item $i'),
              ),
            );
          },
        ),
      ));

      expect(find.byIcon(Icons.edit_note_rounded), findsOneWidget);
      expect(find.byIcon(Icons.vertical_align_top_rounded), findsNothing);

      // Scroll past threshold
      scroll.jumpTo(500);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.vertical_align_top_rounded), findsOneWidget);

      // Tap scroll to top
      await tester.tap(find.byIcon(Icons.vertical_align_top_rounded));
      await tester.pumpAndSettle();

      expect(scroll.offset, 0.0);
      expect(find.byIcon(Icons.vertical_align_top_rounded), findsNothing);
    });
  });

  group('BI26111402: the outbox tells a refusal from no answer', () {
    test('a refusal hub answered is failed and skipped; no answer keeps the rest waiting in order', () async {
      final db = await freshDb();
      final api = ScriptedApi({
        '/api/jira/x': ApiException(503, 'engine not on this fleet', answered: true),
        '/api/tasks': ApiException(502, 'Server error 502'),
      });
      final outbox = OutboxService(db, () => api);
      await outbox.enqueue(path: '/api/jira/x', body: {}, label: 'a', view: 'v');
      await outbox.enqueue(path: '/api/ok', body: {}, label: 'b', view: 'v');
      await outbox.enqueue(path: '/api/tasks', body: {}, label: 'c', view: 'v');
      await outbox.enqueue(path: '/api/ok2', body: {}, label: 'd', view: 'v');

      expect(await outbox.drain(), 1);
      expect(api.posted, ['/api/jira/x', '/api/ok', '/api/tasks'], reason: 'stops at the first missing answer');
      expect(outbox.failed, 1, reason: 'the refusal is visible');
      expect(outbox.pending, 2, reason: 'refusals are not counted as waiting');

      api.answers.remove('/api/tasks');
      api.posted.clear();
      expect(await outbox.drain(), 2);
      expect(api.posted, ['/api/tasks', '/api/ok2'], reason: 'the refusal is not retried on its own');
      expect(outbox.pending, 0);
      expect(outbox.failed, 1);
    });

    test('refusals from before the update get exactly one more try', () async {
      final db = await freshDb();
      final api = ScriptedApi({});
      final outbox = OutboxService(db, () => api);
      await outbox.enqueue(path: '/api/old', body: {}, label: 'old', view: 'v');
      final id = (await db.pendingOutbox()).first['id'] as int;
      await db.markOutbox(id, 'failed', 'Server error 502');
      expect(await outbox.drain(), 1);
      await outbox.enqueue(path: '/api/no', body: {}, label: 'no', view: 'v');
      api.answers['/api/no'] = ApiException(400, 'bad');
      await outbox.drain();
      api.answers.remove('/api/no');
      expect(await outbox.drain(), 0, reason: 'the one-off retry does not repeat');
    });

    test('transient means no answer: an answered 5xx is not transient', () {
      expect(ApiException(503, 'x', answered: true).transient, isFalse);
      expect(ApiException(502, 'x').transient, isTrue);
      expect(ApiException(429, 'x').transient, isTrue);
      expect(ApiException(404, 'x').transient, isFalse);
    });
  });
}
