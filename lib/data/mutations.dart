import '../api/client.dart';
import '../util/fmt.dart' as fmt;
import 'db.dart';
import 'outbox.dart';
import 'store.dart';
import 'sync.dart';

/// Result of a write attempt.
class MutationResult {
  MutationResult.sent([this.payload]) : queued = false, error = null;
  MutationResult.queued() : queued = true, error = null, payload = null;
  MutationResult.failed(this.error) : queued = false, payload = null;
  final bool queued;
  final String? error;
  final dynamic payload;
  bool get ok => error == null;
}

/// Every write the app can make, with one policy:
///  - online  -> straight to the server, then refresh the touched snapshot
///  - offline -> queue in the outbox (plus an optimistic local patch where
///               it is safe), delivered on reconnect
///  - GATE-sensitive writes (deletes, Jira writes, /api/act confirmations)
///    are online-only: the constitution forbids optimistic state on those.
class Mutations {
  Mutations(this._store, this._outbox, this._sync, this._api, [this._db]);

  final Store _store;
  final OutboxService _outbox;
  final SyncEngine _sync;
  final ApiClient Function() _api;
  final AppDb? _db;

  bool get online => _sync.online;

  Future<MutationResult> _write({
    required String path,
    required Map<String, dynamic> body,
    required String label,
    required String view,
    Snapshot? refresh,
    Future<void> Function()? optimistic,
    bool queueable = true,
  }) async {
    if (online) {
      try {
        final res = await _api().postJson(path, body);
        if (refresh != null) refresh.refresh();
        return MutationResult.sent(res);
      } on OfflineException {
        // fall through to queue
      } on ApiException catch (e) {
        return MutationResult.failed(e.message);
      } catch (e) {
        if (!queueable) return MutationResult.failed('$e');
        // fall through to queue on connection/network error when queueable
      }
    }
    if (!queueable) {
      return MutationResult.failed(
          'This action needs the live server - you are offline.');
    }
    await _outbox.enqueue(path: path, body: body, label: label, view: view);
    if (optimistic != null) await optimistic();
    return MutationResult.queued();
  }

  // ---------- tasks ----------

  Future<MutationResult> addTask({
    required String title,
    String priority = 'medium',
    String status = 'today',
    String due = '',
    String tag = '',
  }) {
    final body = {
      'title': title,
      'priority': priority,
      'status': status,
      if (due.isNotEmpty) 'due_date': due,
      if (tag.isNotEmpty) 'tag': tag,
      'syncJira': false,
    };
    return _write(
      path: '/api/tasks',
      body: body,
      label: 'Add task · ${fmt.truncate(title, 40)}',
      view: 'tasks',
      refresh: _store.state,
      optimistic: () => _store.state.patchLocal((current) {
        final map = fmt.m(current);
        final tasks = List<Map<String, dynamic>>.from(fmt.lm(map['tasks']));
        tasks.insert(0, {
          'ID': 'QUEUED',
          'TITLE': title,
          'STATUS': status,
          'PRIORITY': priority,
          'DUE_DATE': due.isEmpty ? '-' : due,
          'TAG': tag.isEmpty ? '-' : tag,
          'PARENT_ID': '-',
          'JIRA_KEY': '-',
          'CREATED_AT': DateTime.now().toIso8601String(),
        });
        return {...map, 'tasks': tasks};
      }),
    );
  }

  Future<MutationResult> completeTask(Map<String, dynamic> task,
      {String target = 'done'}) {
    final id = fmt.s(task['ID']);
    return _write(
      path: '/api/tasks/done',
      body: {'taskId': id, 'target': target},
      label: 'Complete · ${fmt.truncate(fmt.s(task['TITLE']), 40)}',
      view: 'tasks',
      refresh: _store.state,
      optimistic: () => _store.state.patchLocal((current) {
        final map = fmt.m(current);
        final tasks = fmt.lm(map['tasks']).map((t) {
          if (fmt.s(t['ID']) == id) return {...t, 'STATUS': target};
          return t;
        }).toList();
        return {...map, 'tasks': tasks};
      }),
    );
  }

  Future<MutationResult> updateTask(String taskId, Map<String, dynamic> fields,
      {String label = ''}) {
    return _write(
      path: '/api/tasks/update',
      body: {'taskId': taskId, ...fields},
      label: label.isEmpty ? 'Update task $taskId' : label,
      view: 'tasks',
      refresh: _store.state,
      optimistic: () => _store.state.patchLocal((current) {
        final map = fmt.m(current);
        final tasks = fmt.lm(map['tasks']).map((t) {
          if (fmt.s(t['ID']) == taskId) {
            final patch = <String, dynamic>{};
            fields.forEach((k, v) => patch[k.toUpperCase()] = v);
            return {...t, ...patch};
          }
          return t;
        }).toList();
        return {...map, 'tasks': tasks};
      }),
    );
  }

  /// Destructive - online only.
  Future<MutationResult> deleteTask(String taskId) => _write(
        path: '/api/tasks/delete',
        body: {'taskId': taskId},
        label: 'Delete task $taskId',
        view: 'tasks',
        refresh: _store.state,
        queueable: false,
      );

  // ---------- day block actions (BI26092628) ----------

  dynamic _patchDayTask(
    dynamic current,
    String taskId,
    Map<String, dynamic> Function(Map<String, dynamic> task) taskModifier,
  ) {
    final map = fmt.m(current);
    final rawBlocks = fmt.l(map['blocks']);
    if (rawBlocks.isEmpty) return current;
    var found = false;
    final blocks = rawBlocks.map((rawB) {
      final b = Map<String, dynamic>.from(fmt.m(rawB));
      final rawTasks = fmt.l(b['tasks']);
      if (rawTasks.isEmpty) return b;
      final tasks = rawTasks.map((rawT) {
        final t = Map<String, dynamic>.from(fmt.m(rawT));
        if (fmt.s(t['id']).toLowerCase() == taskId.toLowerCase() ||
            fmt.s(t['ID']).toLowerCase() == taskId.toLowerCase()) {
          found = true;
          return taskModifier(t);
        }
        return t;
      }).toList();
      b['tasks'] = tasks;
      return b;
    }).toList();
    if (!found) return current;
    return {...map, 'blocks': blocks};
  }

  dynamic _removeDayTask(dynamic current, String taskId,
      {void Function(Map<String, dynamic> task)? onFound}) {
    final map = fmt.m(current);
    final rawBlocks = fmt.l(map['blocks']);
    if (rawBlocks.isEmpty) return current;
    final blocks = rawBlocks.map((rawB) {
      final b = Map<String, dynamic>.from(fmt.m(rawB));
      final rawTasks = fmt.l(b['tasks']);
      if (rawTasks.isEmpty) return b;
      final tasks = <Map<String, dynamic>>[];
      for (final rawT in rawTasks) {
        final t = Map<String, dynamic>.from(fmt.m(rawT));
        if (fmt.s(t['id']).toLowerCase() == taskId.toLowerCase() ||
            fmt.s(t['ID']).toLowerCase() == taskId.toLowerCase()) {
          onFound?.call(t);
        } else {
          tasks.add(t);
        }
      }
      b['tasks'] = tasks;
      return b;
    }).toList();
    return {...map, 'blocks': blocks};
  }

  Future<MutationResult> dayPin(String taskId, {String? blockId}) {
    return _write(
      path: '/api/day/pin',
      body: {
        'taskId': taskId,
        'id': taskId,
        'blockId': ?blockId,
      },
      label: 'Pin task · $taskId',
      view: 'hub',
      refresh: _store.day,
      optimistic: () => _store.day.patchLocal((current) {
        return _patchDayTask(current, taskId, (t) {
          final isPinned = t['pinned'] == true || t['PINNED'] == true;
          return {
            ...t,
            'pinned': !isPinned,
            'PINNED': !isPinned,
          };
        });
      }),
    );
  }

  Future<MutationResult> dayMove(String taskId,
      {String? blockId, String? targetBlockId}) {
    return _write(
      path: '/api/day/move',
      body: {
        'taskId': taskId,
        'id': taskId,
        'blockId': ?blockId,
        'targetBlockId': ?targetBlockId,
      },
      label: 'Move task · $taskId',
      view: 'hub',
      refresh: _store.day,
      optimistic: () => _store.day.patchLocal((current) {
        Map<String, dynamic>? movingTask;
        final mapWithout =
            _removeDayTask(current, taskId, onFound: (t) => movingTask = t);
        if (movingTask == null) return current;
        final map = fmt.m(mapWithout);
        final rawBlocks = fmt.l(map['blocks']);
        if (rawBlocks.isEmpty) return mapWithout;
        final blocks =
            rawBlocks.map((b) => Map<String, dynamic>.from(fmt.m(b))).toList();

        int destIdx = -1;
        if (targetBlockId != null) {
          destIdx = blocks.indexWhere((b) => fmt.s(b['id']) == targetBlockId);
        }
        if (destIdx == -1) {
          final currIdx = blocks.indexWhere((b) => fmt.s(b['id']) == blockId);
          if (currIdx != -1) {
            for (var i = 1; i < blocks.length; i++) {
              final candidate = (currIdx + i) % blocks.length;
              if (blocks[candidate]['placeable'] == true) {
                destIdx = candidate;
                break;
              }
            }
          }
        }
        if (destIdx == -1) {
          destIdx = blocks.indexWhere((b) => b['placeable'] == true);
        }
        if (destIdx != -1) {
          final destTasks =
              List<Map<String, dynamic>>.from(fmt.l(blocks[destIdx]['tasks']));
          destTasks.add(movingTask!);
          blocks[destIdx]['tasks'] = destTasks;
        }
        return {...map, 'blocks': blocks};
      }),
    );
  }

  Future<MutationResult> dayDefer(String taskId, {String? blockId}) {
    return _write(
      path: '/api/day/defer',
      body: {
        'taskId': taskId,
        'id': taskId,
        'blockId': ?blockId,
      },
      label: 'Defer task · $taskId',
      view: 'hub',
      refresh: _store.day,
      optimistic: () => _store.day.patchLocal((current) {
        return _removeDayTask(current, taskId);
      }),
    );
  }

  Future<MutationResult> dayStart(String taskId, {String? blockId}) {
    return _write(
      path: '/api/day/start',
      body: {
        'taskId': taskId,
        'id': taskId,
        'blockId': ?blockId,
      },
      label: 'Start task · $taskId',
      view: 'hub',
      refresh: _store.day,
      optimistic: () => _store.day.patchLocal((current) {
        return _patchDayTask(current, taskId, (t) {
          final isStarted = t['started'] == true || t['STARTED'] == true;
          return {
            ...t,
            'started': !isStarted,
            'STARTED': !isStarted,
            'startedAt': !isStarted ? DateTime.now().toIso8601String() : null,
          };
        });
      }),
    );
  }

  Future<MutationResult> dayDone(String taskId, {String? blockId}) {
    return _write(
      path: '/api/day/done',
      body: {
        'taskId': taskId,
        'id': taskId,
        'blockId': ?blockId,
      },
      label: 'Done task · $taskId',
      view: 'hub',
      refresh: _store.day,
      optimistic: () async {
        await _store.day.patchLocal((current) {
          return _removeDayTask(current, taskId);
        });
        await _store.state.patchLocal((current) {
          final map = fmt.m(current);
          final tasks = fmt.lm(map['tasks']).map((t) {
            if (fmt.s(t['ID']) == taskId || fmt.s(t['id']) == taskId) {
              return {...t, 'STATUS': 'done'};
            }
            return t;
          }).toList();
          return {...map, 'tasks': tasks};
        });
      },
    );
  }

  // ---------- capture ----------

  Future<MutationResult> addInbox({
    required String body,
    String title = '',
    String channel = 'mobile',
    String sender = '',
  }) {
    return _write(
      path: '/api/inbox/add',
      body: {
        'body': body,
        if (title.isNotEmpty) 'title': title,
        'channel': channel,
        if (sender.isNotEmpty) 'sender': sender,
        'source': 'apk',
      },
      label: 'Capture · ${fmt.truncate(title.isEmpty ? body : title, 40)}',
      view: 'inbox',
      refresh: _store.state,
    );
  }

  /// BI26100309: snooze a thread's messages together on the server (the shared SNOOZE_UNTIL), or clear it with a null [until].
  /// Offline it is queued, so a snooze made on a train reaches the web console when the phone is back.
  Future<MutationResult> inboxSnooze(List<String> ids, DateTime? until) => _write(
        path: '/api/inbox/snooze',
        body: {'ids': ids, 'until': until?.toUtc().toIso8601String()},
        label: until == null ? 'Inbox unsnooze' : 'Inbox snooze',
        view: 'inbox',
        refresh: _store.state,
      );

  Future<MutationResult> inboxUpdate(String id,
          {String? status, String? tag, String? comment}) =>
      _write(
        path: '/api/inbox/update',
        body: {
          'id': id,
          'status': ?status,
          'tag': ?tag,
          'comment': ?comment,
        },
        label: 'Inbox update · $id',
        view: 'inbox',
        refresh: _store.state,
      );

  /// BI26092641: attach an Unknown handle (kind + value) to an existing person.
  Future<MutationResult> inboxLinkUnknown({required String kind, required String value, required String personId}) => _write(
        path: '/api/inbox/unknown/link',
        body: {'kind': kind, 'value': value, 'personId': personId},
        label: 'Link $value',
        view: 'inbox',
        refresh: _store.state,
        queueable: false,
      );

  /// BI26092641: create a person from an Unknown handle. Explicit only, never automatic.
  Future<MutationResult> inboxCreateUnknown({required String kind, required String value, required String name}) => _write(
        path: '/api/inbox/unknown/create',
        body: {'kind': kind, 'value': value, 'name': name},
        label: 'Create $name',
        view: 'inbox',
        refresh: _store.state,
        queueable: false,
      );

  // ---------- journal ----------

  /// BI26092651: change an entry's Codex fields (visibility, practices). The server mints the Codex id the first time
  /// an entry leaves private. Queued offline like every write; the change reaches the server, and the id is minted,
  /// when the outbox next syncs.
  Future<MutationResult> updateJournal(String id, Map<String, dynamic> fields) =>
      _write(
        path: '/api/journal/update',
        body: {'id': id, ...fields},
        label: 'Journal update',
        view: 'journal',
        refresh: _store.journal,
      );

  Future<MutationResult> addJournal({
    required String body,
    int? mood,
    int? energy,
    String tags = '',
  }) {
    return _write(
      path: '/api/journal/add',
      body: {
        'body': body,
        'mood': ?mood,
        'energy': ?energy,
        if (tags.isNotEmpty) 'tags': tags,
      },
      label: 'Journal entry',
      view: 'journal',
      refresh: _store.journal,
      optimistic: () => _store.journal.patchLocal((current) {
        final map = fmt.m(current);
        final entries = List<Map<String, dynamic>>.from(fmt.lm(map['entries']));
        entries.insert(0, {
          'ID': 'QUEUED',
          'DATE': fmt.isoDate(DateTime.now()),
          'MOOD': mood?.toString() ?? '-',
          'ENERGY': energy?.toString() ?? '-',
          'TAGS': tags.isEmpty ? '-' : tags,
          'BODY': body,
          'AI_NOTE': '-',
          'CREATED_AT': DateTime.now().toIso8601String(),
        });
        return {...map, 'entries': entries};
      }),
    );
  }

  // ---------- finance ----------

  Future<MutationResult> addTransaction(Map<String, dynamic> tx) => _write(
        path: '/api/finance/tx',
        body: tx,
        label:
            'Transaction · ${fmt.s(tx['type'])} ${fmt.money(tx['amount'])}',
        view: 'finance',
        refresh: _store.finance,
      );

  Future<MutationResult> fileReceipt({
    required String base64Content,
    required String name,
    required String contentType,
  }) =>
      _write(
        path: '/api/finance/receipt',
        body: {
          'content': base64Content,
          'name': name,
          'contentType': contentType,
        },
        label: 'Receipt · $name',
        view: 'finance',
        refresh: _store.finance,
      );

  /// A pasted message - an M-Pesa text, a bank alert, a paybill confirmation -
  /// distilled into a transaction. The server re-parses the text itself (the
  /// ledger takes its numbers from the message, never from the client) via the
  /// same moneytalk parser the inbox scan uses, writes an idempotent row keyed
  /// on the transaction code, and pushes finance/transactions.tsv online. The
  /// payload is {success, written, skipped, rows}; offline it queues and the
  /// distillation happens on reconnect, so the record still lands online.
  Future<MutationResult> distillMessage(String text) => _write(
        path: '/api/finance/messages/commit',
        body: {
          'rows': [
            {'text': text},
          ],
        },
        label: 'Distil a pasted message',
        view: 'finance',
        refresh: _store.finance,
      );

  // ---------- circle ----------

  Future<MutationResult> logTouch({
    required String personId,
    String channel = '',
    String summary = '',
    String next = '',
  }) =>
      _write(
        path: '/api/circle/touch',
        body: {
          'personId': personId,
          if (channel.isNotEmpty) 'channel': channel,
          if (summary.isNotEmpty) 'summary': summary,
          if (next.isNotEmpty) 'next': next,
        },
        label: 'Touch · $personId',
        view: 'circle',
        refresh: _store.circle,
      );

  // ---------- calendar / dates ----------

  Future<MutationResult> addEvent(Map<String, dynamic> event) => _write(
        path: '/api/calendar/events',
        body: event,
        label: 'Event · ${fmt.truncate(fmt.s(event['title']), 40)}',
        view: 'calendar',
        refresh: _store.calendar,
      );

  Future<MutationResult> addDate(Map<String, dynamic> date) => _write(
        path: '/api/dates/add',
        body: date,
        label: 'Date · ${fmt.truncate(fmt.s(date['title']), 40)}',
        view: 'calendar',
        refresh: _store.dates,
      );

  // ---------- plans ----------

  Future<MutationResult> addPlan(
          {required String title, String horizon = 'cycle', String note = ''}) =>
      _write(
        path: '/api/plans/add',
        body: {
          'title': title,
          'horizon': horizon,
          if (note.isNotEmpty) 'note': note,
        },
        label: 'Plan · ${fmt.truncate(title, 40)}',
        view: 'planning',
        refresh: _store.plans,
      );

  // ---------- notifications ----------

  Future<MutationResult> markSeen({List<String>? ids, bool all = false}) =>
      _write(
        path: '/api/notifications/seen',
        body: all ? {'all': true} : {'ids': ids ?? []},
        label: all ? 'Mark all alerts seen' : 'Mark alerts seen',
        view: 'notifications',
        refresh: _store.notifications,
        optimistic: () => _store.notifications.patchLocal((current) {
          final map = fmt.m(current);
          final items = fmt.lm(map['notifications']).map((n) {
            final hit = all || (ids?.contains(fmt.s(n['ID'])) ?? false);
            return hit ? {...n, 'STATUS': 'seen'} : n;
          }).toList();
          return {...map, 'notifications': items};
        }),
      );

  // ---------- learning ----------

  /// BI26092613: Local-first module progress update.
  /// Saves locally to SQLite db, applies optimistic patch, and queues in outbox.
  Future<MutationResult> lessonProgress(
    String course,
    String lesson,
    String status, {
    bool force = false,
  }) async {
    final normStatus = status.toLowerCase().trim();
    await _db?.saveLessonStatusLocal(
      course: course,
      file: lesson,
      status: normStatus,
      force: force,
    );
    return _write(
      path: '/api/learning/progress',
      body: {'course': course, 'lesson': lesson, 'status': normStatus},
      label: 'Lesson $normStatus · $lesson',
      view: 'learning',
      refresh: _store.learning,
      queueable: true,
      optimistic: () => _store.learning.patchLocal((current) {
        final map = fmt.m(current);
        final courses = List<Map<String, dynamic>>.from(fmt.lm(map['courses']));
        var updated = false;
        for (var i = 0; i < courses.length; i++) {
          final c = Map<String, dynamic>.from(courses[i]);
          final cId = fmt.s(c['ID']).isNotEmpty ? fmt.s(c['ID']) : fmt.s(c['id']);
          if (cId == course) {
            final lessons = List<Map<String, dynamic>>.from(fmt.lm(c['lessons']));
            for (var j = 0; j < lessons.length; j++) {
              final l = Map<String, dynamic>.from(lessons[j]);
              if (fmt.s(l['file']) == lesson) {
                final cur = fmt.s(l['status']);
                if (force || AppDb.statusRank(normStatus) >= AppDb.statusRank(cur)) {
                  l['status'] = normStatus;
                  lessons[j] = l;
                  c['lessons'] = lessons;
                  courses[i] = c;
                  updated = true;
                }
                break;
              }
            }
            if (updated) break;
          }
        }
        return updated ? {...map, 'courses': courses} : current;
      }),
    );
  }

  // ---------- ideas (Spark) ----------

  /// Capture is the whole point of having this on a phone: an idea arrives
  /// away from the desk or it is lost. Queues offline like a journal entry.
  Future<MutationResult> addIdea({
    required String title,
    String body = '',
    String domain = '',
    String tags = '',
    String type = 'personal',
  }) =>
      _write(
        path: '/api/ideas/add',
        body: {
          'title': title,
          if (body.isNotEmpty) 'body': body,
          if (domain.isNotEmpty) 'domain': domain,
          if (tags.isNotEmpty) 'tags': tags,
          'type': type,
          'source': 'apk',
        },
        label: 'Idea · ${fmt.truncate(title, 40)}',
        view: 'ideas',
        refresh: _store.ideas,
        optimistic: () => _store.ideas.patchLocal((current) {
          final map = fmt.m(current);
          final ideas = List<Map<String, dynamic>>.from(fmt.lm(map['ideas']));
          ideas.insert(0, {
            'ID': 'QUEUED',
            'TITLE': title,
            'BODY': body.isEmpty ? '-' : body,
            'DOMAIN': domain.isEmpty ? '-' : domain,
            'TAGS': tags.isEmpty ? '-' : tags,
            'TYPE': type,
            'STAGE': 'spark',
            'STATUS': 'open',
            'IMPACT': '-',
            'EFFORT': '-',
            'CREATED_AT': DateTime.now().toIso8601String(),
          });
          return {...map, 'ideas': ideas};
        }),
      );

  Future<MutationResult> updateIdea(String id, Map<String, dynamic> fields) =>
      _write(
        path: '/api/ideas/update',
        body: {'id': id, ...fields},
        label: 'Idea update · $id',
        view: 'ideas',
        refresh: _store.ideas,
      );

  // ---------- rhythm ----------

  /// Ticking a habit is the most offline-tolerant write in the app: it is a
  /// boolean against a date, so a late delivery still lands on the right day.
  Future<MutationResult> toggleHabit({
    required String date,
    required String habitId,
    required bool done,
  }) =>
      _write(
        path: '/api/personal/rhythm',
        body: {
          'toggleHabit': {'date': date, 'habitId': habitId, 'done': done},
        },
        label: '${done ? 'Did' : 'Cleared'} $habitId · $date',
        view: 'rhythm',
        refresh: _store.rhythm,
        optimistic: () => _store.rhythm.patchLocal((current) {
          final map = fmt.m(current);
          final logs = Map<String, dynamic>.from(fmt.m(map['logs']));
          final day = Map<String, dynamic>.from(fmt.m(logs[date]));
          day[habitId] = done;
          logs[date] = day;
          return {...map, 'logs': logs};
        }),
      );

  /// BI26092515: replace the habit list (add or edit a keystone habit). The
  /// server refuses a second NEW habit per focus word per cycle with a 400 and
  /// a plain message, which surfaces here as `res.error`. `stage` and
  /// `cycleKey` are derived by the server on read and are never sent back.
  Future<MutationResult> saveHabits(List<Map<String, dynamic>> habits) =>
      _write(
        path: '/api/personal/rhythm',
        body: {
          'habits': [
            for (final h in habits)
              {...h}
                ..remove('stage')
                ..remove('cycleKey'),
          ],
        },
        label: 'Habits',
        view: 'rhythm',
        refresh: _store.rhythm,
      );

  // ---------- finance: wishlist ----------

  Future<MutationResult> saveWishlistItem(Map<String, dynamic> item) => _write(
        path: '/api/finance/wishlist',
        body: item,
        label: 'Wishlist · ${fmt.truncate(fmt.s(item['name']), 40)}',
        view: 'finance',
        refresh: _store.wishlist,
      );

  // ---------- learning ----------

  /// Margin notes on a lesson. The tutor reads these and the agent reads them
  /// when revising a course, so they are worth capturing from the phone
  /// mid-read. Server keys are `file` and `text` (see /api/learning/notes).
  Future<MutationResult> saveLessonNote({
    required String course,
    required String file,
    required String text,
  }) =>
      _write(
        path: '/api/learning/notes',
        body: {'course': course, 'file': file, 'text': text},
        label: 'Note · $file',
        view: 'learning',
      );

  /// BI26092613: Reading position, saved locally and queued in outbox.
  Future<MutationResult> saveLessonResume({
    required String course,
    required String lesson,
    required int scrollPct,
    double? fraction,
    int? block,
    String? movement,
  }) async {
    await _db?.saveLessonResumeLocal(
      course: course,
      file: lesson,
      scrollPct: scrollPct,
      fraction: fraction,
    );
    return _write(
      path: '/api/learning/resume',
      body: {
        'course': course,
        'lesson': lesson,
        'scrollPct': scrollPct,
        'fraction': ?fraction,
        'block': ?block,
        'movement': ?movement,
      },
      label: 'Resume point · $lesson',
      view: 'learning',
      queueable: true,
    );
  }

  // ---------- decisions ----------

  /// The decision log is the org's record, so it is never written optimistically
  /// and never queued: a decision that "probably landed" is worse than none.
  Future<MutationResult> updateDecision(String id, Map<String, dynamic> fields) =>
      _write(
        path: '/api/decisions/update',
        body: {'id': id, ...fields},
        label: 'Decision $id',
        view: 'decisions',
        refresh: _store.decisions,
        queueable: false,
      );

  // ---------- online-only passthroughs ----------

  /// Natural-language command. Returns the raw /api/act response;
  /// caller must handle needsConfirmation (GATE) by re-posting with confirm.
  Future<dynamic> act(Map<String, dynamic> body) async {
    if (!online) {
      throw OfflineException();
    }
    return _api().postJson('/api/act', body);
  }

  Future<dynamic> post(String path, Map<String, dynamic> body) async {
    if (!online) throw OfflineException();
    return _api().postJson(path, body);
  }

  // ---------- module lifecycle (BI26100110) ----------

  /// The dry-run manifest for retiring or restoring one module: what changes and how many learners have progress on
  /// it. Needs the live server (offline throws [OfflineException]); nothing changes on the server.
  Future<Map<String, dynamic>> moduleManifestPreview({required String op, required String moduleId}) async {
    if (!online) throw OfflineException();
    final r = await _api().postJson('/api/learning/module/manifest', {'op': op, 'modules': [moduleId], 'why': 'preview', 'dryRun': true});
    return fmt.m(r);
  }

  /// Retire or restore one module. Online it goes straight to the server, which decides (hub forwards the caller's
  /// own token, so a session that is not Sconl's is refused); offline it is queued in the outbox and applies when the
  /// phone reconnects. A refusal comes back as the server's own reason.
  Future<MutationResult> moduleLifecycle({required String op, required String moduleId, required String why}) async {
    final r = await _write(
      path: '/api/learning/module/manifest',
      body: {'op': op, 'modules': [moduleId], 'why': why, 'dryRun': false},
      label: op == 'retire' ? 'Retire module' : 'Restore module',
      view: 'learning',
      refresh: _store.learning,
    );
    if (r.queued || !r.ok) return r;
    final d = fmt.m(r.payload);
    if (d['ok'] == true && d['applied'] == true) return r;
    final why2 = (d['errors'] is List ? (d['errors'] as List).map((e) => fmt.s(e)).join(' ') : '').trim();
    return MutationResult.failed(why2.isNotEmpty ? why2 : (fmt.s(d['error']).isNotEmpty ? fmt.s(d['error']) : 'It did not apply.'));
  }
}
