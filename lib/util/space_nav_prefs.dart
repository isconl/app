import 'package:flutter/foundation.dart';

import '../data/db.dart';

/// BI26102802: Space navigation mode setting: Rail (vertical pill rail on right edge)
/// or Tabs (horizontal tab bar under search).
/// Default is Rail, switchable back without a restart.
enum SpaceNavMode {
  rail,
  tabs;

  static SpaceNavMode parse(String? value) {
    if (value == 'tabs') return SpaceNavMode.tabs;
    return SpaceNavMode.rail;
  }
}

class SpaceNavPrefs extends ChangeNotifier {
  SpaceNavPrefs._();
  static final SpaceNavPrefs instance = SpaceNavPrefs._();

  @visibleForTesting
  SpaceNavPrefs.forTesting({SpaceNavMode initialMode = SpaceNavMode.rail}) : _mode = initialMode;

  static const _key = 'spacenav.mode.v1';

  SpaceNavMode _mode = SpaceNavMode.rail;
  SpaceNavMode get mode => _mode;
  bool _loaded = false;

  bool get isRail => _mode == SpaceNavMode.rail;
  bool get isTabs => _mode == SpaceNavMode.tabs;

  Future<void> ensureLoaded(AppDb db) async {
    if (_loaded) return;
    _loaded = true;
    try {
      final v = (await db.getSnapshot(_key))?.$1;
      if (v is Map && v['mode'] != null) {
        _mode = SpaceNavMode.parse(v['mode'] as String?);
        notifyListeners();
      }
    } catch (_) {
      // Default to rail.
    }
  }

  Future<void> setMode(SpaceNavMode newMode, [AppDb? db]) async {
    if (_mode == newMode) return;
    _mode = newMode;
    notifyListeners();
    if (db != null) {
      try {
        await db.putSnapshot(_key, {'mode': newMode == SpaceNavMode.tabs ? 'tabs' : 'rail'});
      } catch (_) {}
    }
  }
}
