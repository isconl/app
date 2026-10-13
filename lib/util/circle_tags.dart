/// BI26100507: the Circle tag format and the counts the tag screens show before a change.
///
/// A person's TAGS is one comma-separated cell, the same format circle's people.js reads and writes
/// (parseTags and serializeTags there); `-` is the empty sentinel. A tag exists only where it is attached
/// to someone, so the tag list is built from the people.
library;

import 'fmt.dart' as fmt;

List<String> parseTags(Object? raw) => fmt
    .s(raw)
    .split(',')
    .map((t) => t.trim())
    .where((t) => t.isNotEmpty && t != '-')
    .toList();

String serializeTags(List<String> tags) {
  final seen = <String>{};
  final uniq = [for (final t in tags.map((t) => t.trim())) if (t.isNotEmpty && seen.add(t)) t];
  return uniq.isEmpty ? '-' : uniq.join(', ');
}

/// Every tag in use with how many people carry it, most used first, then by name.
List<({String tag, int count})> tagCounts(List<Map<String, dynamic>> people) {
  final counts = <String, int>{};
  for (final p in people) {
    for (final t in parseTags(p['TAGS'])) {
      counts[t] = (counts[t] ?? 0) + 1;
    }
  }
  final out = [for (final e in counts.entries) (tag: e.key, count: e.value)];
  out.sort((a, b) => b.count != a.count ? b.count.compareTo(a.count) : a.tag.compareTo(b.tag));
  return out;
}

/// How many people a rename, merge or delete would change: everyone carrying any of [tags], counted once.
int peopleWithAnyTag(List<Map<String, dynamic>> people, Iterable<String> tags) {
  final set = tags.toSet();
  return people.where((p) => parseTags(p['TAGS']).any(set.contains)).length;
}

/// A tag name as circle stores it: tabs, newlines and commas would break the cell, so they become spaces.
String cleanTag(String raw) => raw.replaceAll(RegExp(r'[\t\r\n,]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
