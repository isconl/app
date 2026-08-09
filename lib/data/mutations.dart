import '../api/client.dart';
import '../util/fmt.dart' as fmt;
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
  Mutations(this._store, this._outbox, this._sync, this._api);

  final Store _store;
  final OutboxService _outbox;
  final SyncEngine _sync;
  final ApiClient Function() _api;

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
        return MutationResult.failed('$e');
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

  // ---------- journal ----------

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

  Future<MutationResult> lessonProgress(
          String course, String lesson, String status) =>
      _write(
        path: '/api/learning/progress',
        body: {'course': course, 'lesson': lesson, 'status': status},
        label: 'Lesson $status · $lesson',
        view: 'learning',
        refresh: _store.learning,
      );

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

  /// Reading position, as a percentage. Never queued: a resume point that
  /// arrives tomorrow would drag him back to where he was today.
  Future<MutationResult> saveLessonResume({
    required String course,
    required String lesson,
    required int scrollPct,
  }) =>
      _write(
        path: '/api/learning/resume',
        body: {'course': course, 'lesson': lesson, 'scrollPct': scrollPct},
        label: 'Resume point · $lesson',
        view: 'learning',
        queueable: false,
      );

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
}
