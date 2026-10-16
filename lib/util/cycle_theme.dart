/// BI26101520: which word a cycle shows, and where it came from. Same order as hub's
/// resolveCycleTheme (BI26100169): the cycle's own word, then the word Compass is holding
/// (the focus word is held for three cycles, so the two cycles before this one are looked
/// at, newest first), then the default rotation.
enum CycleWordSource { override, compass, rotation }

const cycleRotation = [
  'Plant', 'Push', 'Climb', 'Reap', 'Dig', 'Weave', 'Mend', 'Scout',
  'Scale', 'Make', 'Run', 'Stock', 'Audit',
];

String rotationWord(int cycleNum) => cycleRotation[(cycleNum - 1).clamp(0, 12)];

class CycleWord {
  const CycleWord(this.word, this.source);
  final String word;
  final CycleWordSource source;
}

/// [own] is this cycle's primary word from the server, [held] the primary words of the
/// previous cycles in order, newest first (at most two are read).
CycleWord resolveCycleWord({required int cycleNum, String? own, List<String?> held = const []}) {
  if (own != null && own.isNotEmpty) return CycleWord(own, CycleWordSource.override);
  for (final w in held.take(2)) {
    if (w != null && w.isNotEmpty) return CycleWord(w, CycleWordSource.compass);
  }
  return CycleWord(rotationWord(cycleNum), CycleWordSource.rotation);
}
