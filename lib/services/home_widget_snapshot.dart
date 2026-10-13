/// BI26100138: what the Android home-screen widget shows, worked out here in Dart where it can be tested.
///
/// The widget never calls the network and never runs Dart. The app hands it one small snapshot: the day's
/// blocks as minutes past midnight, and the next few items with absolute times. The native side
/// (TodayWidget.kt) then picks the current block and the next item by the clock alone, so the widget stays
/// right between app launches and only the content waits for the next sync.
///
/// Privacy: nothing from finance or health (the T3 domains) and no message content reaches the snapshot.
/// Items are events and the tasks placed in the day's blocks, and any item marked T3 or filed under a T3
/// domain is dropped here, before it leaves the app.
library;

import '../util/fmt.dart' as fmt;

/// The most items handed to the widget; it only ever shows one, the rest are there for when time moves on.
const int kWidgetMaxItems = 12;

/// How long an event stays "next" after it starts, since most calendar entries carry a start and no end.
const Duration kEventGrace = Duration(minutes: 30);

const Set<String> _t3Domains = {'finance', 'money', 'health', 'medical', 'body'};

/// The snapshot as JSON-ready data. [day] is the `/api/blocks` value, [calendar] the `/api/calendar/events`
/// value, either may be null when nothing has synced yet.
Map<String, dynamic> buildWidgetSnapshot({
  required Object? day,
  required Object? calendar,
  required DateTime now,
  bool hideTitles = false,
}) {
  final blocks = <Map<String, dynamic>>[];
  final items = <Map<String, dynamic>>[];
  final midnight = DateTime(now.year, now.month, now.day);

  for (final raw in fmt.l(fmt.m(day)['blocks'])) {
    final b = fmt.m(raw);
    final start = _minutes(b, 'startClock', 'start');
    final end = _minutes(b, 'endClock', 'end');
    if (start == null || end == null) continue;
    final name = fmt.s(b['name']).isEmpty ? 'Block' : fmt.s(b['name']);
    blocks.add({'name': name, 'start': start, 'end': end});

    // A task placed in a block is due when the block opens, and stays current until it closes.
    var at = midnight.add(Duration(minutes: start));
    var until = midnight.add(Duration(minutes: end <= start ? end + 1440 : end));
    if (until.isBefore(now)) {
      at = at.add(const Duration(days: 1));
      until = until.add(const Duration(days: 1));
    }
    for (final t in fmt.l(b['tasks'])) {
      final task = fmt.m(t);
      if (_isT3(task) || _isDone(task)) continue;
      final title = fmt.s(task['title'] ?? task['TITLE']).trim();
      if (title.isEmpty) continue;
      items.add(_item('task', title, at, until));
    }
  }

  for (final raw in fmt.l(fmt.m(calendar)['events'])) {
    final e = fmt.m(raw);
    if (_isT3(e)) continue;
    final at = _eventStart(fmt.s(e['date']), fmt.s(e['time']));
    if (at == null) continue;
    final until = at.add(kEventGrace);
    if (!until.isAfter(now) || at.isAfter(now.add(const Duration(days: 2)))) continue;
    final title = fmt.s(e['title']).trim();
    if (title.isEmpty) continue;
    items.add(_item('event', title, at, until));
  }

  items.removeWhere((i) => (i['until'] as int) <= now.millisecondsSinceEpoch);
  items.sort((a, b) => (a['at'] as int).compareTo(b['at'] as int));

  return {
    'v': 1,
    'written': now.millisecondsSinceEpoch,
    'hideTitles': hideTitles,
    'blocks': blocks,
    'items': [
      for (final i in items.take(kWidgetMaxItems))
        if (hideTitles) {...i, 'title': i['kind'] == 'event' ? 'Event' : 'Task'} else i,
    ],
  };
}

Map<String, dynamic> _item(String kind, String title, DateTime at, DateTime until) => {
      'kind': kind,
      'title': title.length > 80 ? '${title.substring(0, 79)}…' : title,
      'at': at.millisecondsSinceEpoch,
      'until': until.millisecondsSinceEpoch,
    };

/// Minutes past midnight from an `HH:MM` clock field, or from a plain minutes field (the built-in default
/// blocks carry minutes).
int? _minutes(Map<String, dynamic> b, String clockKey, String minutesKey) {
  final clock = _clock(fmt.s(b[clockKey]));
  if (clock != null) return clock;
  final v = b[minutesKey];
  if (v is num && v >= 0 && v <= 1440) return v.toInt() % 1440;
  return _clock(fmt.s(v));
}

int? _clock(String s) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(s.trim());
  if (m == null) return null;
  final h = int.parse(m.group(1)!), min = int.parse(m.group(2)!);
  if (h > 24 || min > 59) return null;
  return (h * 60 + min) % 1440;
}

DateTime? _eventStart(String date, String time) {
  final d = DateTime.tryParse(date);
  if (d == null) return null;
  final mins = _clock(time);
  // An all-day event has no time; it counts from the start of its day.
  return DateTime(d.year, d.month, d.day).add(Duration(minutes: mins ?? 0));
}

bool _isDone(Map<String, dynamic> t) {
  final status = fmt.s(t['status'] ?? t['STATUS']).toLowerCase();
  return t['done'] == true || status == 'done' || status == 'closed';
}

bool _isT3(Map<String, dynamic> item) {
  for (final key in const ['tier', 'TIER', 'sensitivity']) {
    if (fmt.s(item[key]).toUpperCase() == 'T3') return true;
  }
  for (final key in const ['axis', 'domain', 'category', 'calendar', 'project']) {
    if (_t3Domains.contains(fmt.s(item[key]).toLowerCase())) return true;
  }
  return item['sensitive'] == true || item['private'] == true;
}
