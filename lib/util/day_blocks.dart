/// BN26091024: pulled out of context_ring_card.dart's `_calculateDayNow()`
/// so the Planner grid (calendar.dart) can share the exact same fallback
/// schedule instead of re-typing a second copy that could drift -- this is
/// the same 12-row default `/api/blocks` itself falls back to server-side
/// when nothing has been customized yet.
const List<Map<String, dynamic>> kDefaultDayBlocks = [
  {'start': 300, 'end': 360, 'name': 'Protected', 'axis': 'protected', 'third': 'Ground', 'slots': 0, 'placeable': false},
  {'start': 360, 'end': 420, 'name': 'Academia', 'axis': 'learning', 'third': 'Ground', 'slots': 1, 'placeable': true},
  {'start': 420, 'end': 480, 'name': 'Flex', 'axis': 'flex', 'third': 'Ground', 'slots': 0, 'placeable': false},
  {'start': 480, 'end': 600, 'name': 'Innovator', 'axis': 'innovator', 'third': 'Work', 'slots': 4, 'placeable': true},
  {'start': 600, 'end': 660, 'name': 'Flex', 'axis': 'flex', 'third': 'Work', 'slots': 0, 'placeable': false},
  {'start': 660, 'end': 780, 'name': 'Visionary', 'axis': 'visionary', 'third': 'Work', 'slots': 4, 'placeable': true},
  {'start': 780, 'end': 840, 'name': 'Lunch', 'axis': 'lunch', 'third': 'Work', 'slots': 0, 'placeable': false},
  {'start': 840, 'end': 960, 'name': 'Creator', 'axis': 'creator', 'third': 'Work', 'slots': 4, 'placeable': true},
  {'start': 960, 'end': 1020, 'name': 'Connection', 'axis': 'connection', 'third': 'Work', 'slots': 2, 'placeable': true},
  {'start': 1020, 'end': 1080, 'name': 'Flex', 'axis': 'flex', 'third': 'Ground', 'slots': 0, 'placeable': false},
  {'start': 1080, 'end': 1260, 'name': 'Hearth', 'axis': 'home', 'third': 'Ground', 'slots': 0, 'placeable': false},
  {'start': 1260, 'end': 300, 'name': 'Rest', 'axis': 'rest', 'third': 'Rest', 'slots': 0, 'placeable': false},
];

/// Ported from the web's `BLOCK_TONE` map (`app.js` ~9252) -- same fallback
/// hex values, minus the CSS-custom-property override layer web supports
/// (Settings' per-axis color config isn't read on mobile yet).
const Map<String, int> kAxisToneHex = {
  'protected': 0xFF8B9EEC,
  'learning': 0xFF3FB6D3,
  'flex': 0xFF7C828D,
  'innovator': 0xFF22B573,
  'visionary': 0xFF4A7FE8,
  'lunch': 0xFFD9A441,
  'creator': 0xFFF2792A,
  'connection': 0xFFEA5A9E,
  'home': 0xFF4A9C86,
  'rest': 0xFF43458F,
};
