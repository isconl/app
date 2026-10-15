import 'dart:async';

import 'package:flutter/foundation.dart';

import '../app_scope.dart';
import '../util/fmt.dart' as fmt;
import 'home_widget.dart';

/// BI26100138: keeps the home-screen widget current while the app is used. Whenever the day plan or the task list
/// changes, a fresh snapshot goes to the native side (at most once every few seconds). When the app is closed the
/// widget keeps showing the last snapshot with its "as of" time, so it reads as stale rather than wrong.
class WidgetSync extends ChangeNotifier {
  WidgetSync(this._s);
  final AppServices _s;

  static const _key = 'widget.settings.v1';
  bool _hideNext = false;
  bool _started = false;
  Timer? _debounce;

  bool get hideNext => _hideNext;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      final saved = (await _s.db.getSnapshot(_key))?.$1;
      _hideNext = fmt.m(saved)['hideNext'] == true;
    } catch (_) {}
    _s.store.day.addListener(_schedule);
    _s.store.state.addListener(_schedule);
    _schedule();
  }

  Future<void> setHideNext(bool v) async {
    _hideNext = v;
    notifyListeners();
    try {
      await _s.db.putSnapshot(_key, {'hideNext': v});
    } catch (_) {}
    HomeWidgetBridge.instance.forget();
    _schedule();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 3), _push);
  }

  Future<void> _push() async {
    final day = fmt.m(_s.store.day.value);
    final tasks = fmt.lm(fmt.m(_s.store.state.value)['tasks']);
    await HomeWidgetBridge.instance.push(buildWidgetSnapshot(day: day, tasks: tasks, now: DateTime.now(), hideNext: _hideNext));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _s.store.day.removeListener(_schedule);
    _s.store.state.removeListener(_schedule);
    super.dispose();
  }
}

/// The running sync, so Settings can reach it. Null until the signed-in app has started it, and always on web.
WidgetSync? activeWidgetSync;
