import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/api/client.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/data/db.dart';
import 'package:isconl/data/lesson_notes.dart';
import 'package:isconl/data/modules.dart';
import 'package:isconl/data/mutations.dart';
import 'package:isconl/data/outbox.dart';
import 'package:isconl/data/store.dart';
import 'package:isconl/data/sync.dart';
import 'package:isconl/data/vault_mirror.dart';
import 'package:isconl/services/narration.dart';
import 'package:isconl/services/session.dart';
import 'package:isconl/services/sms_ingest.dart';
import 'package:isconl/services/updater.dart';
import 'package:isconl/theme.dart';
import 'package:isconl/ui/nav_menu.dart';
import 'package:isconl/ui/shell.dart';
import 'package:isconl/ui/views/learning.dart';
import 'package:isconl/ui/widgets/brand.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _TestApiClient extends ApiClient {
  _TestApiClient() : super(baseUrl: 'http://test', token: 'test');
  @override
  Future<dynamic> getJson(String path, {bool cold = false}) async => {};
  @override
  Future<dynamic> postJson(String path, Map<String, dynamic> body, {bool cold = false}) async => {'ok': true};
}

class _TestSessionService extends SessionService {
  _TestSessionService(this._api);
  final _TestApiClient _api;
  @override
  ApiClient get api => _api;
}

class _TestSyncEngine extends SyncEngine {
  _TestSyncEngine(super.store, super.outbox, super.apiOf);
  @override
  void start() {}
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<AppServices> buildTestServices() async {
    final rawDb = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        singleInstance: false,
        version: 4,
        onCreate: (db, _) async {
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
          await db.execute('''
            CREATE TABLE lesson_notes (
              course TEXT NOT NULL,
              file TEXT NOT NULL,
              text TEXT NOT NULL,
              anchor INTEGER,
              updated_at INTEGER NOT NULL,
              PRIMARY KEY (course, file)
            )''');
          await ensureVaultMirrorTables(db);
        },
      ),
    );
    final db = AppDb.forTesting(rawDb);
    final api = _TestApiClient();
    final session = _TestSessionService(api);
    ApiClient apiOf() => session.api;
    final store = Store(db, apiOf);
    final outbox = OutboxService(db, apiOf);
    final sync = _TestSyncEngine(store, outbox, apiOf);
    sync.online = false;
    final mutations = Mutations(store, outbox, sync, apiOf);
    final modules = ModuleLibrary(db, store, apiOf);
    final narrator = Narrator(apiOf);
    final sms = SmsIngest(apiOf);
    final updater = UpdateService(apiOf);
    final lessonNotes = LessonNotesRepository(apiOf: apiOf, mutations: mutations, db: db);

    return AppServices.forTesting(
      db: db,
      session: session,
      store: store,
      modules: modules,
      narrator: narrator,
      sms: sms,
      outbox: outbox,
      sync: sync,
      mutations: mutations,
      updater: updater,
      lessonNotes: lessonNotes,
    );
  }

  group('BI26092612: Mobile Study courses and modules views', () {
    testWidgets('courses view has no back-arrow IconButton and shows BrandMark, SyncIndicator, and menu', (tester) async {
      final services = (await tester.runAsync(() => buildTestServices()))!;

      await tester.pumpWidget(
        AppScope(
          services: services,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const TrackDetailScreen(
                          track: 'Systems Architecture',
                          courses: [],
                        ),
                      ),
                    );
                  },
                  child: const Text('Open Track'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Track'));
      await tester.pumpAndSettle();

      // Verify no chevron/back arrow IconButton
      expect(find.byIcon(Icons.chevron_left_rounded), findsNothing);
      expect(find.byTooltip('Back'), findsNothing);

      // Verify BrandMark is present on left
      expect(find.byType(BrandMark), findsOneWidget);

      // Verify SyncIndicator is present on right
      expect(find.byType(SyncIndicator), findsWidgets);

      // Verify hamburger menu IconButton is present
      expect(find.byIcon(Icons.menu_rounded), findsOneWidget);

      // Tapping hamburger menu opens the full-screen menu panel (BI26092617)
      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(NavMenuScreen), findsOneWidget);

      // Close menu with the X
      await tester.tap(find.byKey(const Key('nav-close')));
      await tester.pumpAndSettle();

      // Tapping the BrandMark pops the TrackDetailScreen
      await tester.tap(find.byType(BrandMark));
      await tester.pumpAndSettle();

      // We are back at the root screen
      expect(find.text('Open Track'), findsOneWidget);
      expect(find.byType(TrackDetailScreen), findsNothing);
    });

    test('moduleStatusColor: grey new, track colour opened, amber learning, green done', () {
      const track = Color(0xFF123456);
      expect(moduleStatusColor('new', track), C.text3);
      expect(moduleStatusColor('opened', track), track);
      expect(moduleStatusColor('learning', track), C.amber);
      expect(moduleStatusColor('done', track), C.green);
      expect(moduleStatusColor('', track), C.text3);
    });

    testWidgets('course cards render in SEQ/position order, with subtle numbers and tabular figures', (tester) async {
      final services = (await tester.runAsync(() => buildTestServices()))!;

      final courses = [
        {
          'ID': 'course-b',
          'TITLE': 'Distributed Systems Core',
          'SUBTITLE': 'Replication and consensus models',
          'SEQ': 2,
          'modulesTotal': 5,
          'modulesDone': 5,
        },
        {
          'ID': 'course-a',
          'TITLE': 'Unix Storage Engines',
          'SUBTITLE': 'Log-structured merge trees',
          'SEQ': 1,
          'modulesTotal': 4,
          'modulesDone': 0,
        },
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: AppScope(
            services: services,
            child: TrackDetailScreen(
              track: 'Systems Architecture',
              courses: courses,
              trackColor: const Color(0xFF2563EB),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find all CourseSummaryCard widgets
      final cards = tester.widgetList<CourseSummaryCard>(find.byType(CourseSummaryCard)).toList();
      expect(cards.length, 2);

      // Course A (SEQ 1) should be first, Course B (SEQ 2) second
      expect(cards[0].course['ID'], 'course-a');
      expect(cards[1].course['ID'], 'course-b');

      // Subtle numbers 01 and 02
      expect(find.text('01'), findsOneWidget);
      expect(find.text('02'), findsOneWidget);

      // Verify 01 is rendered before 02 vertically
      final pos01 = tester.getTopLeft(find.text('01'));
      final pos02 = tester.getTopLeft(find.text('02'));
      expect(pos01.dy, lessThan(pos02.dy));

      // Titles and subtitles
      expect(find.text('Unix Storage Engines'), findsOneWidget);
      expect(find.text('Log-structured merge trees'), findsOneWidget);
      expect(find.text('Distributed Systems Core'), findsOneWidget);
      expect(find.text('Replication and consensus models'), findsOneWidget);
    });

    testWidgets('never-opened course shows updated in meta line, opened course shows opened ago', (tester) async {
      final services = (await tester.runAsync(() => buildTestServices()))!;

      final courses = [
        {
          'ID': 'c1',
          'TITLE': 'First Never Opened',
          'position': 1,
          'modulesTotal': 4,
          'modulesDone': 0,
          'updatedAt': '2026-09-12T10:00:00Z',
        },
        {
          'ID': 'c2',
          'TITLE': 'Second Was Opened',
          'position': 2,
          'modulesTotal': 6,
          'modulesDone': 2,
          'lastOpenedAt': DateTime.now().subtract(const Duration(days: 3)).toIso8601String(),
        },
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: AppScope(
            services: services,
            child: TrackDetailScreen(
              track: 'Systems Architecture',
              courses: courses,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // c1: never opened, falls back to "updated 12 Sep"
      expect(find.text('0/4 modules · updated 12 Sep'), findsOneWidget);

      // c2: opened 3d ago
      expect(find.text('2/6 modules · opened 3d ago'), findsOneWidget);
    });

    testWidgets('first incomplete course shows Start here when unstarted, or Continue when in progress', (tester) async {
      final services = (await tester.runAsync(() => buildTestServices()))!;

      // Case 1: unstarted first incomplete course
      final unstartedCourses = [
        {
          'ID': 'c1',
          'TITLE': 'Course One Unstarted',
          'position': 1,
          'modulesTotal': 3,
          'modulesDone': 0,
        },
        {
          'ID': 'c2',
          'TITLE': 'Course Two Pending',
          'position': 2,
          'modulesTotal': 3,
          'modulesDone': 0,
        },
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: AppScope(
            services: services,
            child: TrackDetailScreen(
              track: 'Test Track',
              courses: unstartedCourses,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Only first course shows "Start here" chip
      expect(find.text('Start here'), findsOneWidget);
      expect(find.text('Continue'), findsNothing);

      // Case 2: first course is done, second course is partially done
      final partiallyDoneCourses = [
        {
          'ID': 'c1',
          'TITLE': 'Course One Finished',
          'position': 1,
          'modulesTotal': 2,
          'modulesDone': 2,
          'lessons': [
            {'status': 'done'},
            {'status': 'done'},
          ],
        },
        {
          'ID': 'c2',
          'TITLE': 'Course Two In Progress',
          'position': 2,
          'modulesTotal': 4,
          'modulesDone': 1,
          'lessons': [
            {'status': 'done'},
            {'status': 'learning'},
          ],
        },
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: AppScope(
            services: services,
            child: TrackDetailScreen(
              track: 'Test Track',
              courses: partiallyDoneCourses,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // First incomplete course is c2, and it has progress, so it shows "Continue"
      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('Start here'), findsNothing);
    });

    testWidgets('modules view has consistent app bar and logo popping', (tester) async {
      final services = (await tester.runAsync(() => buildTestServices()))!;

      await tester.pumpWidget(
        AppScope(
          services: services,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const CourseDetailScreen(
                          title: 'Kernel Internals',
                          course: {'ID': 'kernel-core', 'lessons': []},
                        ),
                      ),
                    );
                  },
                  child: const Text('Open Course'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Course'));
      await tester.pumpAndSettle();

      // No back arrow
      expect(find.byIcon(Icons.chevron_left_rounded), findsNothing);
      expect(find.byTooltip('Back'), findsNothing);

      // BrandMark, SyncIndicator, menu
      expect(find.byType(BrandMark), findsOneWidget);
      expect(find.byType(SyncIndicator), findsWidgets);
      expect(find.byIcon(Icons.menu_rounded), findsOneWidget);

      // Tapping BrandMark pops
      await tester.tap(find.byType(BrandMark));
      await tester.pumpAndSettle();

      expect(find.text('Open Course'), findsOneWidget);
      expect(find.byType(CourseDetailScreen), findsNothing);
    });

    testWidgets('module list rows render subtle number, state marker, meta line, and highlights next module', (tester) async {
      final services = (await tester.runAsync(() => buildTestServices()))!;

      final course = {
        'ID': 'db-internals',
        'TITLE': 'Database Engine Internals',
        'lessons': [
          {
            'file': '01-b-trees.md',
            'title': 'B-Tree Indexing Structure',
            'subtitle': 'Balanced node split algorithm',
            'status': 'done',
            'position': 1,
            'readTime': '8 min read',
            'updatedAt': '2026-09-20T10:00:00Z',
          },
          {
            'file': '02-wal.md',
            'title': 'Write-Ahead Log Protocol',
            'subtitle': 'Crash recovery and ARIES',
            'status': 'learning',
            'position': 2,
            'readTime': '12 min read',
            'updatedAt': '2026-09-22T10:00:00Z',
          },
          {
            'file': '03-mvcc.md',
            'title': 'Multi-Version Concurrency Control',
            'subtitle': 'Snapshot isolation and vacuuming',
            'status': 'new',
            'position': 3,
            'readTime': '10 min read',
            'updatedAt': '2026-09-23T10:00:00Z',
          },
        ],
      };

      await tester.pumpWidget(
        MaterialApp(
          home: AppScope(
            services: services,
            child: CourseDetailScreen(
              title: 'Database Engine Internals',
              course: course,
              trackColor: const Color(0xFF10B981),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Subtle numbers
      expect(find.text('01'), findsOneWidget);
      expect(find.text('02'), findsOneWidget);
      expect(find.text('03'), findsOneWidget);

      // Titles and subtitles
      expect(find.text('B-Tree Indexing Structure'), findsOneWidget);
      expect(find.text('Balanced node split algorithm'), findsOneWidget);
      expect(find.text('Write-Ahead Log Protocol'), findsOneWidget);
      expect(find.text('Crash recovery and ARIES'), findsOneWidget);
      expect(find.text('Multi-Version Concurrency Control'), findsOneWidget);
      expect(find.text('Snapshot isolation and vacuuming'), findsOneWidget);

      // Meta lines (read time + updated date)
      expect(find.text('8 min read · updated 20 Sep'), findsOneWidget);
      expect(find.text('12 min read · updated 22 Sep'), findsOneWidget);
      expect(find.text('10 min read · updated 23 Sep'), findsOneWidget);

      // BI26100137: the number carries the status, heavy weight, and there is no status dot or offline tick.
      final nums = tester.widgetList<Text>(find.byKey(const Key('module-number'))).toList();
      expect(nums.length, 3);
      expect(nums.map((n) => n.style?.fontWeight), everyElement(FontWeight.w800));
      expect(nums[0].style?.color, C.green);
      expect(nums[1].style?.color, C.amber);
      expect(nums[2].style?.color, C.text3);
      expect(find.byIcon(Icons.offline_pin_rounded), findsNothing);

      // Next module to study: module 2 is the first not 'done'
      final rows = tester.widgetList<LessonRow>(find.byType(LessonRow)).toList();
      expect(rows.length, 3);
      expect(rows[0].isNext, isFalse);
      expect(rows[1].isNext, isTrue, reason: 'first incomplete module should be marked isNext');
      expect(rows[2].isNext, isFalse);
    });

    // ── BI26100538: study lists that hide nothing and read well ────────────────────────────────
    test('BI26100538: a books course is first, then coverage order, then title; archived is separate', () {
      final courses = [
        {'ID': 'cx', 'TITLE': 'Zeta Practice', 'coverage_order': 3},
        {'ID': 'cb', 'TITLE': 'Beta Practice', 'coverage_order': 2},
        {'ID': 'topic-books', 'TITLE': 'Reading List', 'coverage_order': 9},
        {'ID': 'ca', 'TITLE': 'Alpha Practice', 'coverage_order': 2},
        {'ID': 'cz', 'TITLE': 'Archetype Books', 'archetype': 'books', 'SEQ': 50},
        {'ID': 'old', 'TITLE': 'Retired One', 'STATUS': 'archived', 'coverage_order': 0},
      ];
      final live = orderedCourses(courses.where((c) => !isArchivedCourse(c)));
      expect(live.map((c) => c['ID']), ['topic-books', 'cz', 'ca', 'cb', 'cx'],
          reason: 'books first (by coverage), then coverage order, ties by title');
      expect(orderedCourses(courses.where(isArchivedCourse)).map((c) => c['ID']), ['old']);
      // Without coverage_order, SEQ still orders, as before.
      expect(orderedCourses([{'ID': 'b', 'TITLE': 'B', 'SEQ': 2}, {'ID': 'a', 'TITLE': 'A', 'SEQ': 1}]).map((c) => c['ID']), ['a', 'b']);
    });

    testWidgets('BI26100538: an empty track still shows its card with the empty state and the courses owed', (tester) async {
      final empty = LearningGroup.fromApi({
        'id': 'identity', 'label': 'Identity & Self', 'color': '#8B5CF6', 'tile': 'square',
        'sortOrder': 1, 'courseCount': 0, 'moduleCount': 0, 'progressPct': 0, 'coursesOwed': 3,
      });
      final none = LearningGroup.fromApi({'id': 'x', 'label': 'No Owed Count', 'sortOrder': 2});
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Column(children: [
          TrackCard(group: empty, courses: const []),
          TrackCard(group: none, courses: const []),
        ])),
      ));
      expect(find.text('Identity & Self'), findsOneWidget);
      expect(find.byKey(const Key('track-empty')), findsNWidgets(2));
      expect(find.text('No courses live yet'), findsNWidgets(2));
      expect(find.text('3 courses on the way'), findsOneWidget);
      expect(find.byKey(const Key('track-owed')), findsOneWidget, reason: 'no owed line when spark reports none');
    });

    testWidgets('BI26100538: archived courses are kept, under a collapsed Archived heading, and books come first', (tester) async {
      final services = (await tester.runAsync(() => buildTestServices()))!;
      final courses = [
        {'ID': 'c-practice', 'TITLE': 'Practice Course', 'SUBTITLE': 'Doing the work', 'coverage_order': 1, 'modulesTotal': 3, 'modulesDone': 0},
        {'ID': 'c-books', 'TITLE': 'Book Shelf', 'SUBTITLE': 'What the experts wrote about this', 'archetype': 'books', 'coverage_order': 5, 'modulesTotal': 3, 'modulesDone': 0},
        {'ID': 'c-old', 'TITLE': 'Retired Course', 'STATUS': 'archived', 'modulesTotal': 2, 'modulesDone': 2},
      ];
      await tester.pumpWidget(MaterialApp(
        home: AppScope(services: services, child: TrackDetailScreen(track: 'T', courses: courses, trackColor: const Color(0xFF2563EB))),
      ));
      await tester.pumpAndSettle();
      final ids = tester.widgetList<CourseSummaryCard>(find.byType(CourseSummaryCard)).map((c) => c.course['ID']).toList();
      expect(ids, ['c-books', 'c-practice'], reason: 'the books course first; the archived one is collapsed');
      expect(find.text('Archived (1)'), findsOneWidget);
      await tester.ensureVisible(find.text('Archived (1)'));
      await tester.tap(find.text('Archived (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Retired Course'), findsOneWidget, reason: 'archived courses stay reachable');
      // Bold title over a smaller subtitle, at most two lines.
      final title = tester.widget<Text>(find.byKey(const Key('course-title')).first);
      final sub = tester.widget<Text>(find.byKey(const Key('course-subtitle')).first);
      expect(title.style!.fontWeight, FontWeight.w600);
      expect(sub.maxLines, 2);
      expect(sub.style!.fontSize!, lessThan(title.style!.fontSize!));
    });

    testWidgets('BI26100538: a track with nothing live shows an empty state, not a blank page', (tester) async {
      final services = (await tester.runAsync(() => buildTestServices()))!;
      await tester.pumpWidget(MaterialApp(
        home: AppScope(services: services, child: const TrackDetailScreen(track: 'Empty', courses: [])),
      ));
      await tester.pumpAndSettle();
      expect(find.text('No courses live yet'), findsOneWidget);
    });

    testWidgets('BI26100538: module rows show a bold heading over a smaller subheading, and chips in track colour, yellow and green', (tester) async {
      final services = (await tester.runAsync(() => buildTestServices()))!;
      const track = Color(0xFF2563EB);
      final lessons = [
        {'file': '00-a.md', 'title': 'Setting Out Clearly', 'subtitle': 'Where this module begins and why', 'status': 'opened', 'SEQ': 0},
        {'file': '01-b.md', 'title': 'The Core Idea', 'subtitle': 'One shift that carries everything', 'status': 'learning', 'SEQ': 1},
        {'file': '02-c.md', 'title': 'Run It Weekly', 'status': 'done', 'SEQ': 2},
        {'file': '03-d.md', 'title': 'Not Started Yet', 'status': 'new', 'SEQ': 3},
      ];
      await tester.pumpWidget(MaterialApp(
        home: AppScope(
          services: services,
          child: Scaffold(body: SingleChildScrollView(child: Column(children: [
            for (var i = 0; i < lessons.length; i++)
              LessonRow(courseId: 'c', lesson: lessons[i], allLessons: lessons, index: i, trackColor: track),
          ]))),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('module-title')), findsNWidgets(4));
      expect(find.byKey(const Key('module-subtitle')), findsNWidgets(2), reason: 'no filler line when a module has no subheading');
      final chips = tester.widgetList<ModuleStatusChip>(find.byType(ModuleStatusChip)).toList();
      expect(chips.map((c) => c.status), ['opened', 'learning', 'done'], reason: 'a not-yet-opened module has no chip');
      expect(statusChipColor('learning', track), C.amber);
      expect(statusChipColor('done', track), C.green);
      expect(statusChipColor('opened', track), legibleTrackColor(track, C.bg));
      expect(find.text('Opened'), findsOneWidget);
      expect(find.text('Learning'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      // Let the reading-position lookups under the unfinished rows finish before the tree goes.
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('BI26100538: the freshness line says how old the library is and goes amber past 24 hours', (tester) async {
      final now = DateTime.utc(2026, 10, 6, 12);
      Future<Text> line(DateTime syncedAt) async {
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: LibraryFreshness(syncedAt: syncedAt.toIso8601String(), now: now))));
        return tester.widget<Text>(find.byKey(const Key('library-freshness')));
      }

      final fresh = await line(now.subtract(const Duration(hours: 3)));
      expect(fresh.data, startsWith('Library updated'));
      expect(fresh.style!.color, C.text3);
      final stale = await line(now.subtract(const Duration(hours: 30)));
      expect(stale.style!.color, C.amber);
      // No time reported: nothing shown.
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: LibraryFreshness(syncedAt: null))));
      expect(find.byKey(const Key('library-freshness')), findsNothing);
    });
  });
}
