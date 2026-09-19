/// Defensive parsing + formatting helpers.
/// The vault is TSV: every value is a string and '-' is the empty sentinel.
library;

String s(dynamic v) {
  if (v == null) return '';
  final t = v.toString().trim();
  return t == '-' ? '' : t;
}

int i(dynamic v, [int fallback = 0]) {
  if (v == null) return fallback;
  if (v is int) return v;
  if (v is double) return v.round();
  return int.tryParse(v.toString().trim()) ?? fallback;
}

double d(dynamic v, [double fallback = 0]) {
  if (v == null) return fallback;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString().replaceAll(',', '').trim()) ?? fallback;
}

double? dOrNull(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  final t = v.toString().replaceAll(',', '').trim();
  if (t.isEmpty || t == '-') return null;
  return double.tryParse(t);
}

bool b(dynamic v) => v == true || v == 'true' || v == 1 || v == '1';

List<Map<String, dynamic>> lm(dynamic v) {
  if (v is! List) return const [];
  return v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
}

List<dynamic> l(dynamic v) => v is List ? v : const [];

Map<String, dynamic> m(dynamic v) =>
    v is Map ? v.cast<String, dynamic>() : const {};

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const monthsFull = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December'
];
const weekdaysFull = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
];

DateTime? parseDate(dynamic v) {
  final t = s(v);
  if (t.isEmpty) return null;
  return DateTime.tryParse(t)?.toLocal();
}

/// "2026-07-29" -> "Jul 29" (adds year if not current year).
String shortDate(dynamic v) {
  final dt = parseDate(v);
  if (dt == null) return s(v);
  final now = DateTime.now();
  final base = '${_months[dt.month - 1]} ${dt.day}';
  return dt.year == now.year ? base : '$base, ${dt.year}';
}

String weekdayDate(DateTime dt) =>
    '${_weekdays[dt.weekday - 1]}, ${_months[dt.month - 1]} ${dt.day}';

String fullDate(DateTime dt) =>
    '${weekdaysFull[dt.weekday - 1]}, ${monthsFull[dt.month - 1]} ${dt.day}, ${dt.year}';

String isoDate(DateTime dt) =>
    '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

String hhmm(DateTime dt) =>
    '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

/// Relative time: "just now", "4m ago", "2h ago", "3d ago", else short date.
String ago(dynamic v) {
  final dt = parseDate(v);
  if (dt == null) return s(v);
  final diff = DateTime.now().difference(dt);
  if (diff.inSeconds < 50) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return shortDate(v);
}

/// Days until a date: negative = overdue.
int? daysUntil(dynamic v) {
  final dt = parseDate(v);
  if (dt == null) return null;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(dt.year, dt.month, dt.day);
  return day.difference(today).inDays;
}

String dueLabel(dynamic v) {
  final days = daysUntil(v);
  if (days == null) return '';
  if (days < -1) return '${-days}d overdue';
  if (days == -1) return 'yesterday';
  if (days == 0) return 'today';
  if (days == 1) return 'tomorrow';
  if (days < 7) return 'in ${days}d';
  return shortDate(v);
}

/// Money in KES: "KES 12,340" (arithmetic display only - values come from the vault).
String money(dynamic v, {String currency = 'KES', bool compact = false}) {
  final n = dOrNull(v);
  if (n == null) return '$currency 0';
  final neg = n < 0;
  final abs = n.abs();
  String body;
  if (compact && abs >= 1000000) {
    body = '${(abs / 1000000).toStringAsFixed(1)}M';
  } else if (compact && abs >= 100000) {
    body = '${(abs / 1000).toStringAsFixed(0)}K';
  } else {
    body = thousands(abs.round());
    final cents = ((abs - abs.truncate()) * 100).round();
    if (cents > 0 && abs < 10000) {
      body = '$body.${cents.toString().padLeft(2, '0')}';
    }
  }
  return '${neg ? '-' : ''}$currency $body';
}

String thousands(int n) {
  final str = n.abs().toString();
  final buf = StringBuffer();
  for (var idx = 0; idx < str.length; idx++) {
    if (idx > 0 && (str.length - idx) % 3 == 0) buf.write(',');
    buf.write(str[idx]);
  }
  return '${n < 0 ? '-' : ''}$buf';
}

String plural(int n, String unit) => '$n $unit${n == 1 ? '' : 's'}';

/// Bytes -> "1.2 MB"
String bytesLabel(dynamic v) {
  final n = d(v);
  if (n <= 0) return '';
  if (n < 1024) return '${n.round()} B';
  if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
  return '${(n / 1024 / 1024).toStringAsFixed(1)} MB';
}

String titleCase(String v) => v.isEmpty
    ? v
    : v
        .split(RegExp(r'[\s_-]+'))
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');

String truncate(String v, int max) =>
    v.length <= max ? v : '${v.substring(0, max - 1)}…';

/// mm:ss, or h:mm:ss once past an hour. For an audio timeline, where a
/// leading '0:' on a nine-minute module is noise.
String clock(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}
