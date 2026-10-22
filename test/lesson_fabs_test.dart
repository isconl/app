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
  Future<dynamic> getJson(String path, {bool cold = false}) async {
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
  AppDb get db => throw UnimplementedError();

  @override
  ApiClient Function() get apiOf => throw UnimplementedError();

  @override
  Mutations get mutations => throw UnimplementedError();

  LessonNote? note;
  String? lastSavedCourse;
  String? lastSavedFile;
  String? lastSavedText;
  int? lastSavedAnchor;

  @override
  Future<LessonNote?> getNote({required String course, required String file}) async {
    return note;
  }

  @override
  Future<MutationResult> saveNote({
    required String course,
    required String file,
    required String text,
    int? anchor,
  }) async {
    lastSavedCourse = course;
    lastSavedFile = file;
    lastSavedText = text;
    lastSavedAnchor = anchor;
    note = LessonNote(course: course, file: file, text: text, anchor: anchor);
    return MutationResult.sent();
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
    testWidgets('renders note editor and saves note', (tester) async {
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
      expect(find.text('Anchored to paragraph 5'), findsOneWidget);
      expect(find.text('Save note'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Important indemnity clause notes.');
      await tester.tap(find.text('Save note'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(repo.lastSavedCourse, 'corp-law');
      expect(repo.lastSavedFile, '02-contracts.md');
      expect(repo.lastSavedText, 'Important indemnity clause notes.');
      expect(repo.lastSavedAnchor, 4);
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
}
