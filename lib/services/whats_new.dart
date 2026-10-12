import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'updater.dart';

/// Where the last version whose notes were shown is remembered (BI26100531).
abstract class VersionMemory {
  Future<String?> read();
  Future<void> write(String version);
}

/// The real memory: the same secure store the session uses, under one extra key. It holds a version
/// string, nothing secret, but it is already there on every platform the app runs on.
class SecureVersionMemory implements VersionMemory {
  const SecureVersionMemory();
  static const _key = 'whats_new_last_version';
  static const _storage = FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String version) => _storage.write(key: _key, value: version);
}

/// One release's notes as the bundled asset holds them.
class ReleaseNotes {
  const ReleaseNotes({required this.version, this.added = const [], this.improved = const [], this.fixed = const []});

  final String version;
  final List<String> added;
  final List<String> improved;
  final List<String> fixed;

  bool get isEmpty => added.isEmpty && improved.isEmpty && fixed.isEmpty;

  static List<String> _lines(dynamic v) => v is List ? [for (final e in v) if (e is String && e.trim().isNotEmpty) e.trim()] : const <String>[];

  static ReleaseNotes fromJson(Map<String, dynamic> j) => ReleaseNotes(
        version: '${j['version'] ?? ''}'.trim(),
        added: _lines(j['new']),
        improved: _lines(j['improved']),
        fixed: _lines(j['fixed']),
      );
}

/// `assets/whats_new.json`, written at build time from the commit trailers (tool/whats_new.dart): this release
/// first, then the last ten releases' notes. Newest first.
List<ReleaseNotes> parseWhatsNewAsset(String json) {
  final root = jsonDecode(json);
  if (root is! Map) return const [];
  final m = root.cast<String, dynamic>();
  final hist = m['history'];
  return [
    ReleaseNotes.fromJson(m),
    if (hist is List)
      for (final h in hist)
        if (h is Map) ReleaseNotes.fromJson(h.cast<String, dynamic>()),
  ];
}

/// One titled list in the sheet.
class NoteGroup {
  const NoteGroup(this.label, this.items);
  final String label;
  final List<String> items;
}

/// What the sheet shows: a heading and the New, Improved and Fixed lists, merged across every release the
/// phone has not seen yet.
class WhatsNewNotes {
  const WhatsNewNotes({required this.heading, required this.groups});
  final String heading;
  final List<NoteGroup> groups;
}

/// Decides whether to show the "What's new" sheet, once, after an update. Offline, from the notes bundled in the
/// APK: nothing is fetched.
///
/// A fresh install has nothing to compare, so it records the installed version and shows nothing. A launch on a
/// newer version than the one last shown merges the notes of every release after it, up to the installed one, so
/// a phone that skipped versions sees everything it missed. With no notes in range nothing is shown. A read that
/// fails shows nothing and is not recorded, so the next launch tries again.
class WhatsNew {
  WhatsNew(this._memory, this._load);

  final VersionMemory _memory;
  final Future<String> Function() _load;

  /// The notes to show for [installed], or null. Call [markShown] once the sheet has been shown.
  Future<WhatsNewNotes?> pending(String installed) async {
    if (installed.isEmpty) return null;
    final last = await _memory.read();
    if (last == null || last.isEmpty) {
      await _memory.write(installed);
      return null;
    }
    if (UpdateService.compareVersions(installed, last) <= 0) {
      if (last != installed) await _memory.write(installed);
      return null;
    }
    final List<ReleaseNotes> all;
    try {
      all = parseWhatsNewAsset(await _load());
    } catch (_) {
      return null;
    }
    final inRange = all
        .where((r) => !r.isEmpty && UpdateService.compareVersions(r.version, last) > 0 && UpdateService.compareVersions(r.version, installed) <= 0)
        .toList()
      ..sort((a, b) => UpdateService.compareVersions(a.version, b.version));
    if (inRange.isEmpty) {
      await _memory.write(installed);
      return null;
    }
    List<String> merge(List<String> Function(ReleaseNotes) pick) {
      final out = <String>[];
      for (final r in inRange) {
        for (final line in pick(r)) {
          if (!out.contains(line)) out.add(line);
        }
      }
      return out;
    }

    final groups = [
      NoteGroup('New', merge((r) => r.added)),
      NoteGroup('Improved', merge((r) => r.improved)),
      NoteGroup('Fixed', merge((r) => r.fixed)),
    ].where((g) => g.items.isNotEmpty).toList();
    final single = inRange.length == 1 && inRange.first.version == installed;
    return WhatsNewNotes(heading: single ? "What's new in $installed" : 'Since $last', groups: groups);
  }

  Future<void> markShown(String installed) => _memory.write(installed);

  /// The production wiring: the notes bundled in this build.
  static WhatsNew bundled() => WhatsNew(const SecureVersionMemory(), () => rootBundle.loadString('assets/whats_new.json'));
}
