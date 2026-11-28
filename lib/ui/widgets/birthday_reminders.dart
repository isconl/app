import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../../util/key_dates.dart';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// BI26111595: birthdays in the next two weeks, at the top of Hub, worked out on the phone from the key dates (so
/// they show offline and are right every day). Nothing when none is close.
class BirthdayReminders extends StatefulWidget {
  const BirthdayReminders({super.key, this.clock});
  final DateTime Function()? clock;

  @override
  State<BirthdayReminders> createState() => _BirthdayRemindersState();
}

class _BirthdayRemindersState extends State<BirthdayReminders> {
  bool _asked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_asked) return;
    _asked = true;
    // The dates are otherwise fetched only by the calendar; Hub needs them too.
    final dates = AppScope.of(context).store.dates;
    dates.hydrate().then((_) => dates.refresh());
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context).store.dates;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final today = (widget.clock ?? DateTime.now)();
        final soon = upcomingBirthdays(fmt.lm(fmt.m(store.value)['dates']), today);
        if (soon.isEmpty) return const SizedBox.shrink();
        return Padding(
          key: const Key('hub-birthdays'),
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final k in soon)
              Container(
                key: Key('hub-birthday-${k.id}'),
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: C.violet.withValues(alpha: k.daysAway <= 1 ? 0.18 : 0.08),
                  border: Border.all(color: C.violet.withValues(alpha: k.daysAway <= 1 ? 0.7 : 0.35)),
                  borderRadius: BorderRadius.circular(Sz.rMd),
                ),
                child: Row(children: [
                  const Icon(Icons.cake_rounded, size: 18, color: C.violet),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: k.daysAway == 0 ? 'Today: ' : '', style: T.w600(T.body2).copyWith(color: C.violet)),
                      TextSpan(text: "${k.title}'s birthday", style: T.w600(T.body2)),
                      if (k.what.startsWith('turns')) TextSpan(text: ' (${k.what})', style: T.body2.copyWith(color: C.text2)),
                    ])),
                  ),
                  Text(
                    k.daysAway == 0 ? 'today' : '${daysAwayWords(k.daysAway)} · ${_weekdays[k.next.weekday - 1]} ${k.dayMonth()}',
                    style: T.small.copyWith(color: C.violet, fontWeight: FontWeight.w700),
                  ),
                ]),
              ),
          ]),
        );
      },
    );
  }
}
