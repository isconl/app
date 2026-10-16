/// BI26101601: which course standard a module was written to, and how it compares with the current one.
///
/// The module's own frontmatter `version:` names the standard (3.1.0 is written to standard 3.1). Only
/// major.minor matter; the patch is ignored.

/// The `version:` of the YAML frontmatter, or null. A leading HTML comment or blank lines before the
/// opening `---` are allowed, the same shape the reader's speakable() and the module checker tolerate.
String? frontmatterVersion(String content) {
  var src = content.replaceAll('\r\n', '\n').replaceFirst('﻿', '');
  src = src.replaceFirst(RegExp(r'^(\s*<!--[\s\S]*?-->)+'), '');
  final block = RegExp(r'^\s*---\n([\s\S]*?)\n---[ \t]*(\n|$)').firstMatch(src);
  if (block == null) return null;
  final v = RegExp(r'^version:\s*["\x27]?(\d+(?:\.\d+){0,2})', multiLine: true).firstMatch(block.group(1)!);
  return v?.group(1);
}

/// `3.1.0` or `4.5` as (major, minor), or null when it is not a version.
({int major, int minor})? parseStandard(String? v) {
  final m = RegExp(r'^\s*v?(\d+)\.(\d+)').firstMatch(v ?? '');
  return m == null ? null : (major: int.parse(m.group(1)!), minor: int.parse(m.group(2)!));
}

/// Negative when [a] is an older standard than [b], zero when the same, positive when newer.
int compareStandard(({int major, int minor}) a, ({int major, int minor}) b) =>
    a.major != b.major ? a.major.compareTo(b.major) : a.minor.compareTo(b.minor);

class StandardTag {
  const StandardTag(this.text, {this.older = false, this.unknown = false});
  final String text;

  /// Below the current standard: shown amber.
  final bool older;

  /// The module carries no readable version: shown amber.
  final bool unknown;

  bool get amber => older || unknown;
}

/// The tag line for a module. [version] is the module's own, [current] the served current standard (null
/// until it is known, in which case nothing is called older).
StandardTag standardTagFor({String? version, String? current}) {
  final mod = parseStandard(version);
  if (mod == null) return const StandardTag('standard unknown', unknown: true);
  final label = 'standard ${mod.major}.${mod.minor}';
  final cur = parseStandard(current);
  if (cur != null && compareStandard(mod, cur) < 0) return StandardTag('$label · older standard', older: true);
  return StandardTag(label);
}

const olderStandardSentence = 'This module was written to an older course standard and is queued for an update.';
