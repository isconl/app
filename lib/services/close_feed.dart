import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/client.dart';
import '../data/db.dart';
import '../util/current_block.dart';
import '../util/day_blocks.dart';
import '../util/fmt.dart' as fmt;

/// BI26101529: a phone notification each time a slate row is closed.
///
/// The app reads hub's `GET /api/slate/closes?since=<cursor>&wait=<s>`, which proxies slate's
/// `GET /api/feed/closes` with Sconl's own grant, so the app holds no slate token of its own. This file is
/// the logic: parsing, what to notify, the cursor, and the polling. Showing a notification is
/// [AlertService.showSlateCloses]; the Android background schedule lives beside the prefetch task.

/// One closed or landed row, as the feed sends it.
class CloseEvent {
  const CloseEvent({
    required this.id,
    required this.project,
    required this.title,
    this.note = '',
    this.session = '',
    this.machine = '',
    this.sensitive = false,
    this.landed = false,
  });

  final String id;
  final String project;
  final String title;

  /// The first line of the close note.
  final String note;
  final String session;
  final String machine;
  final bool sensitive;

  /// Landed, not yet verified live: never worded as done.
  final bool landed;

  factory CloseEvent.fromJson(Map<String, dynamic> j) => CloseEvent(
        id: fmt.s(j['id']),
        project: fmt.s(j['project']),
        title: fmt.s(j['title']),
        note: fmt.s(j['note'] ?? j['noteFirstLine'] ?? j['closeNote']).split('\n').first.trim(),
        session: fmt.s(j['session']),
        machine: fmt.s(j['machine']),
        sensitive: j['sensitive'] == true,
        landed: j['landed'] == true || fmt.s(j['kind'] ?? j['event']).toLowerCase() == 'landed',
      );
}

/// The feed's answer: the events (oldest first) and the cursor to ask from next time.
({List<CloseEvent> events, String? cursor}) parseCloses(dynamic res) {
  final m = fmt.m(res);
  final events = [
    for (final e in fmt.lm(m['events'] ?? m['closes'] ?? m['rows']))
      if (fmt.s(e['id']).isNotEmpty) CloseEvent.fromJson(e),
  ];
  final c = fmt.s(m['cursor'] ?? m['next']);
  return (events: events, cursor: c.isEmpty ? null : c);
}

/// What Sconl has chosen: the switch (on by default), projects muted, and quiet hours.
class ClosePrefs {
  ClosePrefs({this.enabled = true, Set<String>? muted, this.quietHours = true, Set<String>? seenProjects})
      : muted = muted ?? <String>{},
        seenProjects = seenProjects ?? <String>{};

  bool enabled;
  bool quietHours;
  final Set<String> muted;

  /// Every project a close has come from, so Settings can offer a mute for each.
  final Set<String> seenProjects;

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'quietHours': quietHours,
        'muted': muted.toList()..sort(),
        'seen': seenProjects.toList()..sort(),
      };

  factory ClosePrefs.fromJson(dynamic v) {
    final m = fmt.m(v);
    return ClosePrefs(
      enabled: m['enabled'] != false,
      quietHours: m['quietHours'] != false,
      muted: {for (final p in fmt.l(m['muted'])) fmt.s(p)},
      seenProjects: {for (final p in fmt.l(m['seen'])) fmt.s(p)},
    );
  }
}

/// One notification to show.
class CloseNotice {
  const CloseNotice({
    required this.id,
    required this.title,
    required this.body,
    this.lines = const [],
    this.payload,
    this.private = false,
  });

  final int id;
  final String title;
  final String body;

  /// The expanded lines of a grouped notification (Android inbox style); empty for a single one.
  final List<String> lines;
  final String? payload;

  /// Hidden on the lock screen: a sensitive row is in it.
  final bool private;

  bool get grouped => lines.isNotEmpty;
}

const slateRowPayloadPrefix = 'slate-row:';

/// Three or more in one fetch become one grouped notification.
const closeGroupThreshold = 3;

String _lineFor(CloseEvent e) {
  if (e.sensitive) return 'a sensitive row in ${e.project}';
  return '${e.id} ${e.title}';
}

/// Which notifications a batch of closes produces. Pure: [quiet] says the phone is in quiet hours.
/// Muted projects and a switched-off feed give nothing, and quiet hours suppress rather than queue.
List<CloseNotice> planCloseNotices(List<CloseEvent> events, ClosePrefs prefs, {required bool quiet}) {
  if (!prefs.enabled) return const [];
  if (quiet && prefs.quietHours) return const [];
  final shown = [for (final e in events) if (!prefs.muted.contains(e.project)) e];
  if (shown.isEmpty) return const [];
  final anySensitive = shown.any((e) => e.sensitive);
  if (shown.length >= closeGroupThreshold) {
    return [
      CloseNotice(
        id: 9300,
        title: '${shown.length} rows closed',
        body: shown.take(3).map(_lineFor).join(', '),
        lines: [for (final e in shown) (e.landed && !e.sensitive ? 'Landed (not yet verified live): ' : '') + _lineFor(e)],
        payload: '${slateRowPayloadPrefix}',
        private: anySensitive,
      ),
    ];
  }
  return [
    for (final e in shown)
      if (e.sensitive)
        CloseNotice(
          id: 9301 + shown.indexOf(e),
          title: e.landed ? 'Landed' : 'Closed',
          body: _lineFor(e),
          payload: slateRowPayloadPrefix,
          private: true,
        )
      else
        CloseNotice(
          id: 9301 + shown.indexOf(e),
          title: '${e.landed ? 'Landed' : 'Closed'}: ${e.id}',
          body: [
            e.title,
            if (e.landed) 'Landed (not yet verified live)',
            if (e.note.isNotEmpty) e.note,
          ].join('\n'),
          payload: '$slateRowPayloadPrefix${e.id}',
        ),
  ];
}

/// True while the day's Protected or Rest block is running (Africa/Nairobi), the quiet rule pulse uses.
bool inQuietBlock(DateTime now) {
  final c = nairobiClock(now);
  final n = c.hour * 60 + c.minute;
  for (final b in kDefaultDayBlocks) {
    final axis = fmt.s(b['axis']);
    if (axis != 'protected' && axis != 'rest') continue;
    final s = (b['start'] as num).toInt(), e = (b['end'] as num).toInt();
    if (s < e ? (n >= s && n < e) : (n >= s || n < e)) return true;
  }
  return false;
}

typedef CloseNotifier = Future<void> Function(List<CloseNotice> notices);

/// The running foreground feed, so Settings can change its preferences and the lifecycle hook can stop it.
CloseFeed? activeCloseFeed;

/// The cursor, the preferences and the polling. One instance per process; the background task builds its own.
class CloseFeed {
  CloseFeed({required this.api, required this.db, required this.notify, DateTime Function()? now}) : _now = now ?? DateTime.now;

  final ApiClient Function() api;
  final AppDb db;
  final CloseNotifier notify;
  final DateTime Function() _now;

  static const _cursorKey = 'close.feed.cursor.v1';
  static const _prefsKey = 'close.feed.prefs.v1';
  static const _keepIds = 200;

  String? cursor;
  final List<String> _seenIds = [];
  ClosePrefs prefs = ClosePrefs();
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final c = fmt.m((await db.getSnapshot(_cursorKey))?.$1);
      final cur = fmt.s(c['cursor']);
      cursor = cur.isEmpty ? null : cur;
      _seenIds.addAll([for (final i in fmt.l(c['ids'])) fmt.s(i)]);
      final p = (await db.getSnapshot(_prefsKey))?.$1;
      if (p != null) prefs = ClosePrefs.fromJson(p);
    } catch (_) {
      // Nothing stored yet.
    }
  }

  Future<void> savePrefs() async {
    try {
      await db.putSnapshot(_prefsKey, prefs.toJson());
    } catch (_) {}
  }

  Future<void> _saveCursor() async {
    try {
      await db.putSnapshot(_cursorKey, {'cursor': cursor ?? '', 'ids': _seenIds});
    } catch (_) {}
  }

  /// One fetch. [wait] is how many seconds hub may hold the request open for a new close (0 in the
  /// background). Returns how many notifications were shown. The very first fetch only sets the cursor, so
  /// installing the feature does not announce the whole backlog.
  Future<int> pollOnce({int wait = 0}) async {
    await load();
    final first = cursor == null;
    final since = cursor == null ? '' : '&since=${Uri.encodeQueryComponent(cursor!)}';
    final res = await api().getJson('/api/slate/closes?wait=$wait$since', cold: wait > 0);
    final parsed = parseCloses(res);
    final fresh = [for (final e in parsed.events) if (!_seenIds.contains(e.id)) e];
    var changed = false;
    for (final e in fresh) {
      if (e.project.isNotEmpty && prefs.seenProjects.add(e.project)) changed = true;
      _seenIds.add(e.id);
    }
    while (_seenIds.length > _keepIds) {
      _seenIds.removeAt(0);
    }
    if (changed) await savePrefs();
    var shown = 0;
    if (!first && fresh.isNotEmpty) {
      final notices = planCloseNotices(fresh, prefs, quiet: inQuietBlock(_now()));
      if (notices.isNotEmpty) {
        await notify(notices);
        shown = notices.length;
      }
    }
    if (parsed.cursor != null) cursor = parsed.cursor;
    await _saveCursor();
    return shown;
  }

  // ---- foreground: a long-poll loop, so a close notifies within seconds ----

  bool _running = false;
  int _failures = 0;

  bool get running => _running;

  void start() {
    if (_running) return;
    _running = true;
    unawaited(_loop());
  }

  void stop() => _running = false;

  Future<void> _loop() async {
    while (_running) {
      try {
        await load();
        if (!prefs.enabled) {
          await Future<void>.delayed(const Duration(seconds: 30));
          continue;
        }
        await pollOnce(wait: 25);
        _failures = 0;
      } on ApiException catch (e) {
        // The route is not there yet (hub or slate not deployed): look again slowly, never spin.
        _failures++;
        await Future<void>.delayed(Duration(seconds: e.status == 404 ? 300 : _backoff()));
      } catch (e) {
        _failures++;
        if (kDebugMode) debugPrint('close feed: $e');
        await Future<void>.delayed(Duration(seconds: _backoff()));
      }
    }
  }

  int _backoff() => (15 * (1 << (_failures.clamp(1, 5) - 1))).clamp(15, 300);
}
