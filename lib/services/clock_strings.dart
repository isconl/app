/// BI26101408: the clock card's words in English and Swahili (voice rules, WRITING-VOICE.md). The language follows the
/// device: `sw` gets Swahili, anything else English.
class ClockStrings {
  const ClockStrings._(this._m);
  final Map<String, String> _m;

  static const en = ClockStrings._({
    'title': 'Work hours',
    'in': 'Clock in',
    'break': 'Take a break',
    'back': 'Back',
    'out': 'Clock out',
    'net': 'Worked today',
    'breaks': 'Breaks',
    'fix': 'Fix a time',
    'fixTitle': 'Fix a time',
    'pick': 'Which entry',
    'newTime': 'New time (optional)',
    'reason': 'Why (required)',
    'save': 'Save',
    'cancel': 'Cancel',
    'reasonNeeded': 'Say why before saving.',
    'noEntries': 'No entries to fix yet.',
    'queued': 'Saved. It will send when you are online.',
  });

  static const sw = ClockStrings._({
    'title': 'Saa za kazi',
    'in': 'Anza kazi',
    'break': 'Chukua mapumziko',
    'back': 'Nimerudi',
    'out': 'Maliza kazi',
    'net': 'Umefanya kazi leo',
    'breaks': 'Mapumziko',
    'fix': 'Sahihisha saa',
    'fixTitle': 'Sahihisha saa',
    'pick': 'Ingizo gani',
    'newTime': 'Saa mpya (si lazima)',
    'reason': 'Sababu (lazima)',
    'save': 'Hifadhi',
    'cancel': 'Ghairi',
    'reasonNeeded': 'Andika sababu kabla ya kuhifadhi.',
    'noEntries': 'Hakuna maingizo ya kusahihisha bado.',
    'queued': 'Imehifadhiwa. Itatumwa ukiwa mtandaoni.',
  });

  static ClockStrings forLanguage(String code) => code.toLowerCase() == 'sw' ? sw : en;

  String operator [](String key) => _m[key] ?? en._m[key] ?? key;

  /// `2 h 05 min`, or `2 saa 05 dak` in Swahili.
  String duration(int minutes) {
    final h = minutes ~/ 60, m = (minutes % 60).toString().padLeft(2, '0');
    return identical(this, sw) ? '$h saa $m dak' : '$h h $m min';
  }
}
