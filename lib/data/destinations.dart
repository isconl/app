import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../api/client.dart';
import 'store.dart';

/// One manifest of space destinations, served once, drawn twice.
///
/// Every iSconl space has exactly five destinations:
///   slot 1 = Overview, slot 5 = Activity.
///
/// The manifest is fetched from GET /api/nav/destinations (cached via
/// Snapshot like every other GET), with a bundled copy of the same file
/// (assets/destinations.json) as the offline fallback.
class Destination {
  const Destination({
    required this.key,
    required this.label,
    required this.icon,
    required this.route,
  });

  final String key;
  final String label;
  final String icon;
  final String route;

  factory Destination.fromJson(Map<String, dynamic> j) => Destination(
        key: j['key'] as String? ?? '',
        label: j['label'] as String? ?? '',
        icon: j['icon'] as String? ?? '',
        route: j['route'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'key': key,
        'label': label,
        'icon': icon,
        'route': route,
      };
}

/// Loads and caches the five-destinations-per-space manifest.
class DestinationsManifest {
  DestinationsManifest(this._store);

  final Store _store;

  /// Parsed spaces: view -> list of 5 Destination.
  Map<String, List<Destination>> _spaces = {};

  /// The bundled fallback, loaded once.
  Map<String, List<Destination>>? _bundled;

  /// The five destinations for [viewKey], or null if the space is unknown.
  List<Destination>? operator [](String viewKey) => _spaces[viewKey];

  /// All known view keys.
  Iterable<String> get views => _spaces.keys;

  /// Whether the manifest has been loaded.
  bool get loaded => _spaces.isNotEmpty;

  /// Load from the server (Snapshot cache), falling back to the bundled asset.
  Future<void> load() async {
    // Try server/snapshot first.
    final snap = _store.destinations;
    await snap.hydrate();
    if (snap.value != null) {
      _parseServerValue(snap.value);
    }
    if (_spaces.isEmpty) {
      await _loadBundled();
    }
    // Refresh from server in background.
    snap.refresh().then((_) {
      if (snap.value != null) _parseServerValue(snap.value);
    });
  }

  void _parseServerValue(dynamic v) {
    try {
      final Map<String, dynamic> raw;
      if (v is Map<String, dynamic> && v.containsKey('spaces')) {
        raw = (v['spaces'] as Map).cast<String, dynamic>();
      } else if (v is Map<String, dynamic>) {
        raw = v;
      } else {
        return;
      }
      final parsed = <String, List<Destination>>{};
      for (final entry in raw.entries) {
        final list = (entry.value as List)
            .map((d) => Destination.fromJson(d as Map<String, dynamic>))
            .toList();
        if (list.length == 5) {
          parsed[entry.key] = list;
        }
      }
      if (parsed.isNotEmpty) _spaces = parsed;
    } catch (_) {
      // Malformed data: keep existing.
    }
  }

  Future<void> _loadBundled() async {
    if (_bundled != null) {
      _spaces = _bundled!;
      return;
    }
    try {
      final raw = await rootBundle.loadString('assets/destinations.json');
      final Map<String, dynamic> json = jsonDecode(raw) as Map<String, dynamic>;
      final parsed = <String, List<Destination>>{};
      for (final entry in json.entries) {
        final list = (entry.value as List)
            .map((d) => Destination.fromJson(d as Map<String, dynamic>))
            .toList();
        if (list.length == 5) {
          parsed[entry.key] = list;
        }
      }
      _bundled = parsed;
      if (parsed.isNotEmpty) _spaces = parsed;
    } catch (_) {
      // Bundled asset missing or malformed: the UI will use its own fallback.
    }
  }

  /// Load the bundled copy only (for tests or comparison).
  Future<Map<String, List<Destination>>> loadBundledOnly() async {
    if (_bundled != null) return _bundled!;
    await _loadBundled();
    return _bundled ?? {};
  }
}
