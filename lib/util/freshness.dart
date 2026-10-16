/// BI26101521: how old a Hub card's data is, and whether that is too old.
///
/// Every card reads a cached `Snapshot` that knows when it was fetched. Two things make a card stale: the fetch is
/// older than the card's budget, or the data's own date says the source has stopped changing (a plan dated another
/// day, a newest record older than seven days) even though the fetch was fresh.

/// How long a snapshot may go without a fetch before its card says so. One map, so a new card is one line.
const Map<String, Duration> freshnessBudgets = {
  'day': Duration(minutes: 15),
  'checkpoint': Duration(minutes: 30),
  'signals': Duration(minutes: 30),
  'orientation': Duration(minutes: 30),
  'vitals': Duration(minutes: 60),
  'finance': Duration(hours: 24),
  'october': Duration(hours: 24),
};

const Duration defaultFreshnessBudget = Duration(hours: 6);

/// A source whose newest record is older than this counts as stale whatever the fetch time.
const Duration sourceStaleAfter = Duration(days: 7);

Duration freshnessBudgetFor(String key) => freshnessBudgets[key] ?? defaultFreshnessBudget;

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _two(int n) => n.toString().padLeft(2, '0');

String _clock(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

String _day(DateTime t) => '${t.day} ${_months[t.month - 1]}';

/// `12 min`, `3 h`, `2 d`: the age in the largest whole unit.
String ageWords(Duration d) {
  if (d.inMinutes < 60) return '${d.inMinutes.clamp(0, 59)} min';
  if (d.inHours < 24) return '${d.inHours} h';
  return '${d.inDays} d';
}

class AsOf {
  const AsOf(this.text, {this.stale = false});

  /// "as of 20:31", "stale: 3 h" or "source last changed 25 Sep".
  final String text;
  final bool stale;
}

/// The line for a card. [fetchedAt] null means nothing has been fetched yet (null result: show no line).
/// [sourceDate] is the data's own date when the payload carries one; [now] is injected for tests.
AsOf? asOfFor({
  required String key,
  required DateTime? fetchedAt,
  DateTime? sourceDate,
  required DateTime now,
}) {
  if (fetchedAt == null) return null;
  final age = now.difference(fetchedAt);
  final budget = freshnessBudgetFor(key);
  if (sourceDate != null) {
    final sourceAge = now.difference(sourceDate);
    final otherDay = key == 'day' && (sourceDate.year != now.year || sourceDate.month != now.month || sourceDate.day != now.day);
    if (otherDay || sourceAge > sourceStaleAfter) {
      return AsOf('source last changed ${_day(sourceDate)}', stale: true);
    }
  }
  if (age > budget) return AsOf('stale: ${ageWords(age)}', stale: true);
  final sameDay = fetchedAt.year == now.year && fetchedAt.month == now.month && fetchedAt.day == now.day;
  return AsOf(sameDay ? 'as of ${_clock(fetchedAt)}' : 'as of ${_day(fetchedAt)} ${_clock(fetchedAt)}');
}

/// An ISO date or timestamp from a payload, or null.
DateTime? parseSourceDate(Object? v) {
  final s = '${v ?? ''}'.trim();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s)?.toLocal();
}
