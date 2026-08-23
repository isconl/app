import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/client.dart';
import 'db.dart';

/// One cached endpoint: exposes the last known value instantly (offline-first)
/// and refreshes it over the network when asked.
class Snapshot extends ChangeNotifier {
  Snapshot(this.key, this.path, this._db, this._api);

  final String key;
  final String path;
  final AppDb _db;
  final ApiClient Function() _api;

  dynamic value;
  DateTime? fetchedAt;
  bool loading = false;
  String? error;
  bool _hydrated = false;

  bool get hasData => value != null;

  /// Load the cached copy from SQLite (once).
  Future<void> hydrate() async {
    if (_hydrated) return;
    _hydrated = true;
    final row = await _db.getSnapshot(key);
    if (row != null && value == null) {
      value = row.$1;
      fetchedAt = row.$2;
      notifyListeners();
    }
  }

  /// Fetch a fresh copy. Serves the cache when offline; never throws.
  Future<bool> refresh({bool cold = false}) async {
    await hydrate();
    if (loading) return false;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final fresh = await _api().getJson(path, cold: cold);
      value = fresh;
      fetchedAt = DateTime.now();
      await _db.putSnapshot(key, fresh);
      loading = false;
      notifyListeners();
      return true;
    } on OfflineException {
      error = 'offline';
    } on ApiException catch (e) {
      error = e.message;
    } catch (e) {
      error = 'Unexpected: $e';
    }
    loading = false;
    notifyListeners();
    return false;
  }

  /// Optimistically patch the cached value locally (offline edits).
  Future<void> patchLocal(dynamic Function(dynamic current) fn) async {
    await hydrate();
    value = fn(value);
    fetchedAt = fetchedAt ?? DateTime.now();
    await _db.putSnapshot(key, value);
    notifyListeners();
  }

  void resetLocal() {
    value = null;
    fetchedAt = null;
    error = null;
    _hydrated = true; // don't re-hydrate the value we just wiped
    notifyListeners();
  }
}

/// Registry of all cached endpoints the app mirrors.
class Store {
  Store(this._db, this._api);

  final AppDb _db;
  final ApiClient Function() _api;
  final Map<String, Snapshot> _snapshots = {};

  Snapshot of(String key, String path) =>
      _snapshots.putIfAbsent(key, () => Snapshot(key, path, _db, _api));

  // Core
  Snapshot get state => of('state', '/api/state');
  Snapshot get dayBlock => of('dayBlock', '/api/blocks');
  Snapshot get orientation => of('orientation', '/api/orientation');
  Snapshot get notifications =>
      of('notifications', '/api/notifications?limit=200');
  Snapshot get audit => of('audit', '/api/audit');
  Snapshot get refs => of('refs', '/api/refs');
  Snapshot get tags => of('tags', '/api/tags');
  Snapshot get dataHealth => of('dataHealth', '/api/health/data');

  // Domains
  Snapshot get jira => of('jira', '/api/jira/issues');
  Snapshot get calendar => of('calendar', '/api/calendar/events');
  Snapshot get dates => of('dates', '/api/dates');
  Snapshot get finance => of('finance', '/api/finance/summary');
  Snapshot get journal => of('journal', '/api/journal');
  Snapshot get learning => of('learning', '/api/learning');
  Snapshot get circle => of('circle', '/api/circle');
  Snapshot get spaces => of('spaces', '/api/spaces');
  Snapshot get plans => of('plans', '/api/plans');
  Snapshot get projects => of('projects', '/api/projects');
  Snapshot get github => of('github', '/api/github/snapshot');
  Snapshot get ventures => of('ventures', '/api/ventures');

  // Domains the agent grew after the first native build (30 Jul - 1 Aug).
  Snapshot get ideas => of('ideas', '/api/ideas');
  Snapshot get rhythm => of('rhythm', '/api/personal/rhythm');
  Snapshot get insights => of('insights', '/api/insights');
  Snapshot get decisions => of('decisions', '/api/decisions');
  Snapshot get corporate => of('corporate', '/api/corporate');
  Snapshot get wishlist => of('wishlist', '/api/finance/wishlist');
  Snapshot get chatThreads => of('chatThreads', '/api/chat/threads');
  Snapshot get articles => of('articles', '/api/articles/list');
  Snapshot get buffer => of('buffer', '/api/buffer/desk');

  /// The hosted-infrastructure catalogue (hub's native `/services`, not the
  /// `/api/*` compat layer) -- distinct from `state['services']`'s
  /// integration-credential status map and from the unrelated axial
  /// `spaces` tree above; this is "every app/engine the owner runs."
  Snapshot get hostedServices => of('hostedServices', '/services');

  /// Per-entity caches (task detail, lessons, DIA profiles...).
  Snapshot detail(String kind, String id, String path) =>
      of('$kind:$id', path);

  /// A OneDrive folder listing. Cached per path so the file manager still opens
  /// somewhere useful with no connection.
  Snapshot folder(String folderPath) => of(
        'folder:$folderPath',
        '/api/onedrive/list?path=${Uri.encodeQueryComponent(folderPath)}',
      );

  /// Everything worth pulling in a full sync, core first.
  ///
  /// Buffer and the OneDrive listings are deliberately absent: both are live
  /// third-party calls that cost a rate-limit budget, and neither is worth
  /// spending on a background poll the user may never look at.
  List<Snapshot> get syncSet => [
        state,
        dayBlock,
        notifications,
        orientation,
        jira,
        calendar,
        dates,
        finance,
        journal,
        circle,
        learning,
        spaces,
        plans,
        projects,
        github,
        ideas,
        rhythm,
        decisions,
        audit,
        refs,
        tags,
      ];

  Future<void> clearAll() async {
    await _db.deleteSnapshots();
    for (final snap in _snapshots.values) {
      snap.resetLocal();
    }
  }
}
