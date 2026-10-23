import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../data/db.dart';

/// BI26100141: reader comfort, remembered across modules and restarts.
/// Text size has four steps (S, M, L, XL) and line spacing two; focus mode
/// hides the bar and floating buttons while scrolling down. The size
/// multiplies the system font scale and never takes text past 2.0x.
class ReaderPrefs extends ChangeNotifier {
  ReaderPrefs._();
  static final ReaderPrefs instance = ReaderPrefs._();

  @visibleForTesting
  ReaderPrefs.forTesting();

  static const sizeLabels = ['S', 'M', 'L', 'XL'];
  static const sizeScales = [0.9, 1.0, 1.15, 1.3];
  static const maxScale = 2.0;
  static const _key = 'reader.prefs.v1';

  int sizeStep = 1;
  bool relaxed = false;
  bool focus = false;
  bool _loaded = false;

  /// Extra line height added to every reading style when spacing is relaxed.
  double get lineBoost => relaxed ? 0.2 : 0.0;

  /// The text scale to apply for a given system scale.
  double effectiveScale(double systemScale) => math.min(maxScale, systemScale * sizeScales[sizeStep]);

  Future<void> ensureLoaded(AppDb db) async {
    if (_loaded) return;
    _loaded = true;
    try {
      final v = (await db.getSnapshot(_key))?.$1;
      if (v is Map) {
        final s = v['size'];
        if (s is int && s >= 0 && s < sizeScales.length) sizeStep = s;
        relaxed = v['relaxed'] == true;
        focus = v['focus'] == true;
        notifyListeners();
      }
    } catch (_) {
      // Nothing stored: defaults.
    }
  }

  Future<void> update({int? size, bool? relaxed, bool? focus, AppDb? db}) async {
    if (size != null) sizeStep = size.clamp(0, sizeScales.length - 1);
    if (relaxed != null) this.relaxed = relaxed;
    if (focus != null) this.focus = focus;
    notifyListeners();
    if (db != null) {
      try {
        await db.putSnapshot(_key, {'size': sizeStep, 'relaxed': this.relaxed, 'focus': this.focus});
      } catch (_) {}
    }
  }
}
