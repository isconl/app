import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:isconl/data/vault_mirror.dart';
import 'package:isconl/data/vault_schema.dart';

/// Exercises vault_mirror.dart against a real (ffi, not device-channel)
/// SQLite database -- schema creation, extraction from a hub-endpoint-
/// shaped JSON body, upsert-by-ID, and the read-back shape. Deliberately
/// does NOT go through AppDb.open() (needs path_provider's platform
/// channel, not available under `flutter test`); these are the same
/// underlying calls AppDb's own methods make.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // singleInstance: false -- sqflite's default caches/reuses a connection
  // by path, and inMemoryDatabasePath is a fixed special string, so every
  // test would otherwise silently share ONE in-memory database instead of
  // getting a genuinely fresh one (caught live: a later test saw a row an
  // earlier test had inserted).
  Future<Database> freshDb() async {
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await ensureVaultMirrorTables(db);
    return db;
  }

  test('ensureVaultMirrorTables creates every declared table, idempotent on a second call', () async {
    final db = await freshDb();
    for (final table in kVaultTables.keys) {
      final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name = ?",
        [table],
      );
      expect(rows.length, 1, reason: '$table should exist');
    }
    // Idempotent: running it again must not throw.
    await ensureVaultMirrorTables(db);
  });

  test('extractVaultRows pulls the declared jsonKey and keeps only schema columns, filling missing with "-"', () {
    final response = {
      'tasks': [
        {'ID': 'T1', 'TITLE': 'Buy milk', 'STATUS': 'today', 'extraDerivedField': 'ignored'},
        {'ID': 'T2', 'TITLE': 'Walk dog'}, // STATUS and everything else missing
      ],
    };
    final rows = extractVaultRows(response, 'scope__tasks', 'tasks');
    expect(rows.length, 2);
    expect(rows[0]['ID'], 'T1');
    expect(rows[0]['TITLE'], 'Buy milk');
    expect(rows[0]['STATUS'], 'today');
    expect(rows[0].containsKey('extraDerivedField'), isFalse, reason: 'derived fields not in the schema must not be stored');
    expect(rows[1]['STATUS'], '-', reason: 'a column absent from the source row gets vault\'s own "-" placeholder');
    expect(rows[0].keys.toSet(), kVaultTables['scope__tasks']!.toSet(), reason: 'every schema column is present on every row, not just the ones the source happened to have');
  });

  test('extractVaultRows returns [] (not throwing) for an unknown table, missing jsonKey, or wrong-shaped response', () {
    expect(extractVaultRows({'tasks': []}, 'not__a__real__table', 'tasks'), isEmpty);
    expect(extractVaultRows({'somethingElse': []}, 'scope__tasks', 'tasks'), isEmpty);
    expect(extractVaultRows('not even a map', 'scope__tasks', 'tasks'), isEmpty);
    expect(extractVaultRows({'tasks': 'not a list'}, 'scope__tasks', 'tasks'), isEmpty);
  });

  test('upsertVaultRows inserts new rows and readVaultRows returns them with every schema column', () async {
    final db = await freshDb();
    await upsertVaultRows(db, 'scope__dates', [
      {'ID': 'D1', 'TITLE': 'Birthday', 'DATE': '2026-09-01', 'KIND': 'birthday', 'WHO': '-', 'RECURS': 'yearly', 'COLOR': '-', 'NOTE': '-', 'PERSON_ID': '-'},
    ]);
    final rows = await readVaultRows(db, 'scope__dates');
    expect(rows.length, 1);
    expect(rows[0]['ID'], 'D1');
    expect(rows[0]['TITLE'], 'Birthday');
  });

  test('upsertVaultRows replaces an existing row by ID rather than duplicating it', () async {
    final db = await freshDb();
    await upsertVaultRows(db, 'scope__plans', [
      {'ID': 'P1', 'TITLE': 'Original', 'HORIZON': '-', 'TAG': '-', 'STATUS': '-', 'CREATED_AT': '-', 'NOTE': '-'},
    ]);
    await upsertVaultRows(db, 'scope__plans', [
      {'ID': 'P1', 'TITLE': 'Updated', 'HORIZON': '-', 'TAG': '-', 'STATUS': '-', 'CREATED_AT': '-', 'NOTE': '-'},
    ]);
    final rows = await readVaultRows(db, 'scope__plans');
    expect(rows.length, 1, reason: 'same ID must update in place, not create a second row');
    expect(rows[0]['TITLE'], 'Updated');
  });

  test('upsertVaultRows leaves existing rows alone when the new batch is a subset (no delete-by-omission)', () async {
    final db = await freshDb();
    await upsertVaultRows(db, 'spark__ideas', [
      {'ID': 'I1', 'TITLE': 'Idea one', 'BODY': '-', 'STAGE': '-', 'TYPE': '-', 'DOMAIN': '-', 'TAGS': '-', 'IMPACT': '-', 'EFFORT': '-', 'STATUS': '-', 'SOURCE': '-', 'CREATED_AT': '-', 'UPDATED_AT': '-', 'AI_NOTE': '-', 'NOTE': '-', 'LINKS': '-'},
      {'ID': 'I2', 'TITLE': 'Idea two', 'BODY': '-', 'STAGE': '-', 'TYPE': '-', 'DOMAIN': '-', 'TAGS': '-', 'IMPACT': '-', 'EFFORT': '-', 'STATUS': '-', 'SOURCE': '-', 'CREATED_AT': '-', 'UPDATED_AT': '-', 'AI_NOTE': '-', 'NOTE': '-', 'LINKS': '-'},
    ]);
    // A later fetch that (for whatever reason -- pagination, a filter) only contains I1.
    await upsertVaultRows(db, 'spark__ideas', [
      {'ID': 'I1', 'TITLE': 'Idea one, edited', 'BODY': '-', 'STAGE': '-', 'TYPE': '-', 'DOMAIN': '-', 'TAGS': '-', 'IMPACT': '-', 'EFFORT': '-', 'STATUS': '-', 'SOURCE': '-', 'CREATED_AT': '-', 'UPDATED_AT': '-', 'AI_NOTE': '-', 'NOTE': '-', 'LINKS': '-'},
    ]);
    final rows = await readVaultRows(db, 'spark__ideas');
    expect(rows.map((r) => r['ID']).toSet(), {'I1', 'I2'}, reason: 'I2 must survive a fetch that simply didn\'t mention it');
    expect(rows.firstWhere((r) => r['ID'] == 'I1')['TITLE'], 'Idea one, edited');
  });

  test('upsertVaultRows with an empty list is a no-op, not an error', () async {
    final db = await freshDb();
    await upsertVaultRows(db, 'scope__tasks', []);
    expect(await readVaultRows(db, 'scope__tasks'), isEmpty);
  });

  test('mirrorSnapshotIntoVaultTables feeds every table declared for that snapshot key from one response (state feeds tasks and inbox, not spaces -- FN26090102)', () async {
    final db = await freshDb();
    final stateResponse = {
      'tasks': [
        {'ID': 'T1', 'TITLE': 'Task one'},
      ],
      'spaces': [
        {'ID': 'S1', 'NAME': 'Space one'},
      ],
      'feed': [
        {'ID': 'IN1', 'TITLE': 'Inbox message'},
      ],
    };
    await mirrorSnapshotIntoVaultTables(db, 'state', stateResponse);

    expect((await readVaultRows(db, 'scope__tasks')).map((r) => r['ID']), ['T1']);
    // space__spaces is no longer in kMirrorSources (FN26090102) -- spaces.dart
    // reads /api/spaces (tree endpoint), not /api/state's flat 'spaces' field.
    expect((await readVaultRows(db, 'space__spaces')), isEmpty, reason: 'space__spaces has no mirror source, state response ignored for this table');
    expect((await readVaultRows(db, 'scope__inbox')).map((r) => r['ID']), ['IN1']);
  });

  test('mirrorSnapshotIntoVaultTables is a silent no-op for a snapshot key with no declared mirror source', () async {
    final db = await freshDb();
    // 'jira' has no entry in kMirrorSources today -- must not throw.
    await mirrorSnapshotIntoVaultTables(db, 'jira', {'issues': []});
    for (final table in kVaultTables.keys) {
      expect(await readVaultRows(db, table), isEmpty);
    }
  });

  test('a column named after a SQL reserved word (GROUP, circle__people) round-trips correctly', () async {
    final db = await freshDb();
    await upsertVaultRows(db, 'circle__people', [
      {'ID': 'P1', 'NAME': 'A', 'CIRCLE': '-', 'GROUP': 'friends', 'ROLE': '-', 'MET': '-', 'CHANNEL': '-', 'LAST_TOUCH': '-', 'CADENCE_DAYS': '-', 'STATUS': '-', 'FOLDER': '-', 'NOTE': '-', 'REMEMBER': '-', 'EMAIL': '-', 'IS_SELF': '-'},
    ]);
    final rows = await readVaultRows(db, 'circle__people');
    expect(rows.single['GROUP'], 'friends');
  });

  // -- overlayVaultMirrorTables: the "UI reads the mirror" wiring itself --

  test('overlayVaultMirrorTables is a no-op (returns base untouched) for a snapshot key with no mirror source', () async {
    final db = await freshDb();
    final base = {'issues': ['not vault-shaped at all']};
    expect(await overlayVaultMirrorTables(db, 'jira', base), same(base));
  });

  test('overlayVaultMirrorTables leaves a mirrored field exactly as base had it when the table is empty (never fetched != empty)', () async {
    final db = await freshDb();
    final base = {'people': [{'ID': 'P1', 'NAME': 'real cached data'}]};
    final result = await overlayVaultMirrorTables(db, 'circle', base) as Map;
    expect(result['people'], base['people'], reason: 'an empty mirror table must not stomp real cached data with []');
  });

  test('overlayVaultMirrorTables merges by ID: hub-added/renamed fields survive, vault-schema fields refresh from the mirror', () async {
    final db = await freshDb();
    // circle's real shape: derived fields (lastTouch/dueIn/recent) the UI
    // depends on, none of which are vault schema columns.
    await upsertVaultRows(db, 'circle__people', [
      {'ID': 'P1', 'NAME': 'Alex (fresher)', 'CIRCLE': '-', 'GROUP': '-', 'ROLE': '-', 'MET': '-', 'CHANNEL': '-', 'LAST_TOUCH': '2026-08-30', 'CADENCE_DAYS': '-', 'STATUS': '-', 'FOLDER': '-', 'NOTE': '-', 'REMEMBER': '-', 'EMAIL': '-', 'IS_SELF': '-'},
    ]);
    final base = {
      'people': [
        {'ID': 'P1', 'NAME': 'Alex (stale)', 'LAST_TOUCH': '2026-08-01', 'lastTouch': '2026-08-18', 'dueIn': 3, 'touchCount': 8, 'recent': [{'ID': 'X1'}]},
      ],
    };
    final result = await overlayVaultMirrorTables(db, 'circle', base) as Map;
    final person = (result['people'] as List).single as Map;

    expect(person['NAME'], 'Alex (fresher)', reason: 'vault schema field refreshed from the mirror');
    expect(person['LAST_TOUCH'], '2026-08-30', reason: 'vault schema field refreshed from the mirror');
    expect(person['lastTouch'], '2026-08-18', reason: 'hub-derived field (not a vault column) must survive from base');
    expect(person['dueIn'], 3, reason: 'hub-derived field must survive from base');
    expect(person['touchCount'], 8, reason: 'hub-derived field must survive from base');
    expect(person['recent'], [{'ID': 'X1'}], reason: 'nested/derived field must survive from base');
  });

  test('overlayVaultMirrorTables includes a mirror-only row (accumulated from an earlier fetch, absent from this base) rather than dropping it', () async {
    final db = await freshDb();
    await upsertVaultRows(db, 'spark__ideas', [
      {'ID': 'I1', 'TITLE': 'Base has this one', 'BODY': '-', 'STAGE': '-', 'TYPE': '-', 'DOMAIN': '-', 'TAGS': '-', 'IMPACT': '-', 'EFFORT': '-', 'STATUS': '-', 'SOURCE': '-', 'CREATED_AT': '-', 'UPDATED_AT': '-', 'AI_NOTE': '-', 'NOTE': '-', 'LINKS': '-'},
      {'ID': 'I2', 'TITLE': 'Only the mirror remembers this one', 'BODY': '-', 'STAGE': '-', 'TYPE': '-', 'DOMAIN': '-', 'TAGS': '-', 'IMPACT': '-', 'EFFORT': '-', 'STATUS': '-', 'SOURCE': '-', 'CREATED_AT': '-', 'UPDATED_AT': '-', 'AI_NOTE': '-', 'NOTE': '-', 'LINKS': '-'},
    ]);
    final base = {
      'ideas': [
        {'ID': 'I1', 'TITLE': 'Base has this one'},
      ],
    };
    final result = await overlayVaultMirrorTables(db, 'ideas', base) as Map;
    final ids = (result['ideas'] as List).map((r) => (r as Map)['ID']).toSet();
    expect(ids, {'I1', 'I2'}, reason: 'a row this fetch didn\'t include but an earlier one did must still appear');
  });

  test('overlayVaultMirrorTables keeps a base-only row (mirror source hasn\'t caught up yet) rather than dropping it', () async {
    final db = await freshDb();
    await upsertVaultRows(db, 'scope__plans', [
      {'ID': 'PL1', 'TITLE': 'In the mirror', 'HORIZON': '-', 'TAG': '-', 'STATUS': '-', 'CREATED_AT': '-', 'NOTE': '-'},
    ]);
    final base = {
      'plans': [
        {'ID': 'PL1', 'TITLE': 'In the mirror', 'tasks': []},
        {'ID': 'PL2', 'TITLE': 'Not in the mirror yet', 'tasks': [{'ID': 'T9'}]},
      ],
    };
    final result = await overlayVaultMirrorTables(db, 'plans', base) as Map;
    final byId = {for (final r in (result['plans'] as List)) (r as Map)['ID']: r};
    expect(byId.keys, {'PL1', 'PL2'});
    expect(byId['PL2']!['tasks'], [{'ID': 'T9'}], reason: 'a plan\'s nested tasks (not a vault column) must survive when the row itself is base-only');
  });

  test('overlayVaultMirrorTables handles a null/non-Map base gracefully (first-ever hydrate, mirror has data, blob does not)', () async {
    final db = await freshDb();
    await upsertVaultRows(db, 'scope__dates', [
      {'ID': 'D1', 'TITLE': 'Birthday', 'DATE': '2026-09-01', 'KIND': 'birthday', 'WHO': '-', 'RECURS': '-', 'COLOR': '-', 'NOTE': '-', 'PERSON_ID': '-'},
    ]);
    final result = await overlayVaultMirrorTables(db, 'dates', null) as Map;
    expect((result['dates'] as List).single, containsPair('ID', 'D1'));
  });
}
