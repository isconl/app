import 'package:flutter/foundation.dart';

/// BI26101811: one signal for "the cycle theme changed". Compass (cycle_mix.dart, compass_home.dart) calls [changed]
/// after a save or a queue; every screen that shows the theme (the calendar) listens and fetches it again from
/// `/api/cycle-theme`, the one store the web console also reads. Without it the calendar fetched the theme once per cycle
/// and kept showing the old word until the app restarted.
class CycleThemeBus extends ChangeNotifier {
  CycleThemeBus._();
  static final CycleThemeBus instance = CycleThemeBus._();

  int version = 0;

  void changed() {
    version++;
    notifyListeners();
  }
}
