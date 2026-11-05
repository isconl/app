import '../app_scope.dart';
import '../util/day_close.dart';
import '../util/fmt.dart' as fmt;
import 'alerts.dart';

/// BI26100143: (re)schedules the end-of-day notifications from the saved
/// review time and the counts the app holds right now. Safe to call often:
/// each call replaces the previous schedule.
Future<void> replanDayClose(AppServices s, {DateTime? now}) async {
  try {
    final p = DayClosePrefs.instance;
    await p.ensureLoaded(s.db);
    if (!p.enabled) {
      await AlertService.instance.cancelDayClose();
      return;
    }
    final n = now ?? DateTime.now();
    final tasks = fmt.lm(fmt.m(s.store.state.value)['tasks']);
    await AlertService.instance.scheduleDayClose(
      reviewTimes(n, hour: p.hour, minute: p.minute, skipWeekends: p.skipWeekends),
      dayCloseText(doneToday(tasks, n).length, stillOpen(tasks, n).length),
    );
  } catch (_) {
    // Notifications are a convenience: a failure to schedule never blocks the app.
  }
}
