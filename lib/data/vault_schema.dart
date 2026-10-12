/// BN26083107 (mobile database mirroring): a slice of `vault/lib/
/// default-schema.js` -- table name (matching vault's own
/// `<domain>__<collection>` naming, e.g. `scope/tasks.tsv` -> `scope__tasks`)
/// mapped to its ordered column list, for the collections this app can
/// actually reach through hub's existing `/api/*` endpoints.
///
/// NOT the full ~44-collection schema -- only the confirmed 1:1 slice
/// (an endpoint whose JSON contains one collection's raw rows, verified
/// live against the running fleet, not guessed from route names). Hub's
/// composed endpoints (`/api/state`, most business-logic engines) merge
/// several sources into one response; decomposing those further is real
/// future work, not silently claimed as done here. Extend `kVaultTables`
/// and `kMirrorSources` (vault_mirror.dart) together when adding one.
///
/// Column lists are copied from vault's `default-schema.js` verbatim (same
/// order, same names) so a row read from either side is directly
/// comparable -- do not rename/reorder without also updating the source.
library;

const Map<String, List<String>> kVaultTables = {
  'scope__tasks': [
    'ID', 'TITLE', 'STATUS', 'PRIORITY', 'PROJECT_ID', 'CARRY_FWD',
    'DUE_DATE', 'CREATED_AT', 'JIRA_KEY', 'ORIGIN', 'TAG', 'START_DATE',
    'ASSIGNEE', 'DONE_AT', 'PARENT_ID', 'WHY', 'RESOLUTION', 'DELIVERY',
    'SENT_TO', 'SENT_AT', 'SENT_VIA', 'DELIVERY_NOTE', 'SEQ', 'SEQ_WHY',
    'DELIVERABLE', 'ASSIGNED_BY', 'ORG_ID', 'SESSIONS', 'MODULE',
  ],
  'scope__inbox': [
    'ID', 'TITLE', 'BODY', 'STATUS', 'SOURCE', 'CAPTURED_AT', 'CHANNEL',
    'SENDER', 'SUBJECT', 'RECEIVED_AT', 'TAG', 'COMMENT', 'PERSON_ID',
    'DIRECTION',
  ],
  'circle__people': [
    'ID', 'NAME', 'CIRCLE', 'GROUP', 'ROLE', 'MET', 'CHANNEL', 'LAST_TOUCH',
    'CADENCE_DAYS', 'STATUS', 'FOLDER', 'NOTE', 'REMEMBER', 'EMAIL',
    'IS_SELF',
  ],
  'spark__ideas': [
    'ID', 'TITLE', 'BODY', 'STAGE', 'TYPE', 'DOMAIN', 'TAGS', 'IMPACT',
    'EFFORT', 'STATUS', 'SOURCE', 'CREATED_AT', 'UPDATED_AT', 'AI_NOTE',
    'NOTE', 'LINKS',
  ],
  'space__spaces': [
    'ID', 'PARENT_ID', 'NAME', 'LABEL', 'KIND', 'AXIS', 'ONEDRIVE_PATH',
    'TYPE', 'STATUS', 'HEALTH', 'DESCRIPTION', 'LAST_REVIEWED', 'VIEW',
  ],
  'scope__dates': [
    'ID', 'TITLE', 'DATE', 'KIND', 'WHO', 'RECURS', 'COLOR', 'NOTE',
    'PERSON_ID',
  ],
  'scope__plans': ['ID', 'TITLE', 'HORIZON', 'TAG', 'STATUS', 'CREATED_AT', 'NOTE'],
  'spark__journal': [
    'ID', 'DATE', 'MOOD', 'ENERGY', 'TAGS', 'BODY', 'AI_NOTE', 'CREATED_AT',
    'EDITED_AT',
  ],
};

/// One entry per (Store snapshot key, table) pair this app can extract from
/// that endpoint's JSON response -- `jsonKey` is the array field inside the
/// response body (confirmed live, not assumed from the route name: e.g.
/// journal's wrapper key is `entries`, not `journal`). A single snapshot
/// key can feed more than one table (`state` contains both `tasks` and
/// `spaces`).
const List<(String snapshotKey, String table, String jsonKey)> kMirrorSources = [
  ('state', 'scope__tasks', 'tasks'),
  // NOTE: space__spaces intentionally removed (FN26090102) -- spaces.dart
  // reads services.store.spaces → /api/spaces (a tree endpoint returning
  // {tree:[...]}, each node with children/descendantCount), NOT /api/state's
  // flat 'spaces' field. The table stays in kVaultTables for schema
  // completeness; a future UI using the flat rows can add a mirror source then.
  ('state', 'scope__inbox', 'feed'), // /api/state's inbox rows, reversed -- order doesn't matter for storage
  ('circle', 'circle__people', 'people'),
  ('dates', 'scope__dates', 'dates'),
  ('plans', 'scope__plans', 'plans'),
  ('journal', 'spark__journal', 'entries'),
  ('ideas', 'spark__ideas', 'ideas'),
];
