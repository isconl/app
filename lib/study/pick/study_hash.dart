// A small integrity hash for the study index cache (BI26101604). It guards against a damaged or half-written copy, not
// against an attacker, so a pair of 32-bit FNV-1a runs is enough and needs no extra package. Pure Dart, and safe on web
// (every intermediate stays under 2^53).
String studyHash(String text) {
  var a = 0x811c9dc5;
  var b = 0x01000193 ^ 0x5bd1e995;
  for (final unit in text.codeUnits) {
    a = ((a ^ unit) * 0x01000193) & 0xffffffff;
    b = ((b ^ (unit + 0x9e)) * 0x85ebca6b) & 0xffffffff;
  }
  return '${text.length}:${a.toRadixString(16).padLeft(8, '0')}${b.toRadixString(16).padLeft(8, '0')}';
}
