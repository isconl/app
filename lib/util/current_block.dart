import 'fmt.dart' as fmt;

/// BI26101517, BI26101805: which of the day's blocks is current.
///
/// The live clock decides (Africa/Nairobi, UTC+3, wherever the phone is): the server's `now.current`
/// and the `current` flags were worked out when the snapshot was fetched, so trusting them first froze
/// the card on the block that was current at fetch time. They are used only when the blocks carry no
/// usable times. Null when no block contains the time, or when the plan is from another day, so the
/// card never falls back to the first block.

const _nairobiOffset = Duration(hours: 3);

/// `now` as a Nairobi wall clock. Pure given `now`.
DateTime nairobiClock(DateTime now) => now.toUtc().add(_nairobiOffset);

String nairobiDate(DateTime now) {
  final n = nairobiClock(now);
  return '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
}

int? clockMinutes(String? c) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch((c ?? '').trim());
  if (m == null) return null;
  final h = int.parse(m.group(1)!), mi = int.parse(m.group(2)!);
  return h > 23 || mi > 59 ? null : h * 60 + mi;
}

/// A block's start or end in minutes since midnight, from its `HH:MM` clock or from the integer minutes
/// the default schedule carries.
int? _minsOf(Map b, String clockKey, String minsKey) {
  final c = clockMinutes(fmt.s(b[clockKey]));
  if (c != null) return c;
  final raw = b[minsKey];
  return raw is num ? raw.toInt() : null;
}

int? _startOf(Map b) => _minsOf(b, 'startClock', 'start');
int? _endOf(Map b) => _minsOf(b, 'endClock', 'end');

/// True when the snapshot names a date that is not today (Nairobi). A snapshot with no date is trusted.
bool dayIsStale(Map<String, dynamic> dayData, DateTime now) {
  final d = fmt.s(dayData['date']);
  return d.isNotEmpty && d != nairobiDate(now);
}

bool _inBlock(Map b, int n) {
  final s = _startOf(b), e = _endOf(b);
  if (s == null || e == null || s == e) return false;
  return s < e ? (n >= s && n < e) : (n >= s || n < e); // Rest wraps past midnight
}

String? currentBlockId(Map<String, dynamic> dayData, DateTime now) {
  if (dayIsStale(dayData, now)) return null;
  final blocks = fmt.l(dayData['blocks']).map((b) => fmt.m(b)).toList();
  final timed = blocks.where((b) {
    final s = _startOf(b), e = _endOf(b);
    return s != null && e != null && s != e;
  }).toList();
  if (timed.isNotEmpty) {
    final c = nairobiClock(now);
    final n = c.hour * 60 + c.minute;
    for (final b in timed) {
      if (_inBlock(b, n) && fmt.s(b['id']).isNotEmpty) return fmt.s(b['id']);
    }
    return null;
  }
  // No block has a usable start and end: the server's own pick is all there is.
  final id = fmt.s(fmt.m(fmt.m(dayData['now'])['current'])['id']);
  if (id.isNotEmpty && blocks.any((b) => fmt.s(b['id']) == id)) return id;
  for (final b in blocks) {
    if (b['current'] == true && fmt.s(b['id']).isNotEmpty) return fmt.s(b['id']);
  }
  return null;
}

/// The index of the block that starts next after `now`, wrapping to the first. Used when no block is current.
int nextBlockIndex(List<Map<String, dynamic>> blocks, DateTime now) {
  if (blocks.isEmpty) return 0;
  final c = nairobiClock(now);
  final n = c.hour * 60 + c.minute;
  var best = -1;
  var bestStart = 24 * 60 + 1;
  for (var i = 0; i < blocks.length; i++) {
    final s = _startOf(blocks[i]);
    if (s != null && s > n && s < bestStart) {
      best = i;
      bestStart = s;
    }
  }
  return best >= 0 ? best : 0;
}
