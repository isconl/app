import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/client.dart';
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

/// Decides whether to show the "What's new" sheet, once, after an update.
///
/// A fresh install has nothing to compare, so it records the installed version and shows nothing. A launch
/// on a newer version than the one last shown asks hub for that version's release notes
/// (`GET /api/apk/notes?version=`); an empty body or a failed call shows nothing and never blocks startup.
/// A failed call is not recorded, so the next launch tries again.
class WhatsNew {
  WhatsNew(this._memory, this._fetchNotes);

  final VersionMemory _memory;
  final Future<String> Function(String version) _fetchNotes;

  /// The notes to show for [installed], or null. Call [markShown] once the sheet has been shown.
  Future<String?> pending(String installed) async {
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
    final String notes;
    try {
      notes = (await _fetchNotes(installed)).trim();
    } catch (_) {
      return null;
    }
    if (notes.isEmpty) {
      await _memory.write(installed);
      return null;
    }
    return notes;
  }

  Future<void> markShown(String installed) => _memory.write(installed);

  /// The production wiring: notes come from hub through the session's own API client.
  static WhatsNew forApi(ApiClient Function() api) => WhatsNew(const SecureVersionMemory(), (version) async {
        final res = await api().getJson('/api/apk/notes?version=${Uri.encodeQueryComponent(version)}', cold: true);
        return res is Map ? (res['notes'] ?? '').toString() : '';
      });
}

/// One line of release notes, parsed from Markdown without HTML or images.
class NoteLine {
  const NoteLine(this.kind, this.text);

  /// `heading`, `bullet` or `text`.
  final String kind;
  final String text;
}

/// Plain Markdown to lines: `#` headings, `-` or `*` bullets, everything else as text. Images are
/// dropped, raw HTML tags are stripped, and blank lines separate nothing.
List<NoteLine> parseNotes(String markdown) {
  final out = <NoteLine>[];
  for (final raw in markdown.replaceAll('\r\n', '\n').split('\n')) {
    var line = raw.trimRight();
    if (line.trim().isEmpty) continue;
    line = line.replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), '').replaceAll(RegExp(r'<[^>]+>'), '');
    if (line.trim().isEmpty) continue;
    final h = RegExp(r'^\s{0,3}#{1,6}\s+(.*)$').firstMatch(line);
    if (h != null) {
      out.add(NoteLine('heading', h.group(1)!.trim()));
      continue;
    }
    final b = RegExp(r'^\s*[-*]\s+(.*)$').firstMatch(line);
    if (b != null) {
      out.add(NoteLine('bullet', b.group(1)!.trim()));
      continue;
    }
    out.add(NoteLine('text', line.trim()));
  }
  return out;
}
