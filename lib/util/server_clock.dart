/// BI26101801: the time the Hub clock shows.
///
/// The phone's clock is network-synced by Android, so it is the base. On top of it, each regular hub response carries an
/// HTTP `Date` header; comparing it with the phone's clock (the request's round trip halved) shows whether the phone has
/// drifted. The offset is applied only when it is over [applyOverSeconds] and the round trip was under one second, and it
/// is dropped after 24 hours. A later quiet measurement (a small offset) clears it. No extra network call is made.
class ServerClock {
  ServerClock({DateTime Function()? deviceNow}) : _deviceNow = deviceNow ?? DateTime.now;

  static final ServerClock instance = ServerClock();

  static const applyOverSeconds = 2;
  static const maxRoundTrip = Duration(seconds: 1);
  static const keepFor = Duration(hours: 24);

  final DateTime Function() _deviceNow;
  Duration? _offset;
  DateTime? _measuredAt;

  /// The offset in force right now, or null when the device time is used unchanged.
  Duration? get offset {
    final at = _measuredAt;
    if (_offset == null || at == null) return null;
    if (_deviceNow().difference(at) > keepFor) return null;
    return _offset;
  }

  /// The best current time: the device clock plus the offset, when there is one.
  DateTime now() {
    final d = _deviceNow();
    final o = offset;
    return o == null ? d : d.add(o);
  }

  /// One response seen: [sent] and [received] are the device times around the request, [dateHeader] the `Date` header.
  void observe(DateTime sent, DateTime received, String? dateHeader) {
    final server = parseHttpDate(dateHeader);
    if (server == null) return;
    final rt = received.difference(sent);
    if (rt.isNegative || rt >= maxRoundTrip) return; // a slow answer says nothing about the clock
    final midpoint = sent.add(Duration(microseconds: rt.inMicroseconds ~/ 2));
    // The header is whole seconds, truncated: the server's real time is within the following second.
    final diff = server.add(const Duration(milliseconds: 500)).difference(midpoint);
    if (diff.abs() > const Duration(seconds: applyOverSeconds)) {
      _offset = diff;
      _measuredAt = received;
    } else {
      _offset = null; // the phone agrees with the server: show it unchanged
      _measuredAt = null;
    }
  }

  void reset() {
    _offset = null;
    _measuredAt = null;
  }
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// An RFC 7231 date such as `Sun, 18 Oct 2026 05:41:07 GMT`, as a UTC [DateTime]; null when it is anything else.
DateTime? parseHttpDate(String? v) {
  if (v == null) return null;
  final m = RegExp(r'^[A-Za-z]{3}, (\d{1,2}) ([A-Za-z]{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$').firstMatch(v.trim());
  if (m == null) return null;
  final mon = _months.indexOf(m.group(2)!);
  if (mon < 0) return null;
  return DateTime.utc(int.parse(m.group(3)!), mon + 1, int.parse(m.group(1)!), int.parse(m.group(4)!), int.parse(m.group(5)!), int.parse(m.group(6)!));
}
