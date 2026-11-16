import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../widgets/dashboard/dashboard.dart';
import 'personal_dash_model.dart';

/// Asks the device to confirm it is Sconl. Replaced in tests.
typedef Unlock = Future<bool> Function();

Future<bool> deviceUnlock() async {
  try {
    final auth = LocalAuthentication();
    return await auth.authenticate(
      localizedReason: 'Show holdings',
      options: const AuthenticationOptions(stickyAuth: true),
    );
  } on PlatformException {
    return false;
  } catch (_) {
    return false;
  }
}

/// BI26100130: the Personal landing as a dashboard. Holdings are T3 data: the
/// tile is masked, asks the device to unlock on every reveal, and re-masks
/// when the screen is left or the app goes to the background. The revealed
/// figure lives only in this widget's state and is never cached unmasked.
class PersonalDashboard extends StatelessWidget {
  const PersonalDashboard({
    super.key,
    required this.blocks,
    required this.habits,
    required this.netWorth,
    required this.currency,
    this.unlock = deviceUnlock,
    this.onOpenSub,
  });
  final BlocksProgress blocks;
  final List<HabitTrend> habits;

  /// The protected net figure from the finance endpoint, or null when not loaded.
  final dynamic netWorth;
  final String currency;
  final Unlock unlock;
  final void Function(int sub)? onOpenSub;

  @override
  Widget build(BuildContext context) {
    return DashboardGrid(items: [
      DashItem(
        DashTile(
          label: 'Today\'s blocks',
          child: Row(children: [
            RingGauge(
              arcs: [RingArc(blocks.done.toDouble(), C.green)],
              total: blocks.total.toDouble(),
              center: '${blocks.done}/${blocks.total}',
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(blocks.currentName.isEmpty ? 'Between blocks' : blocks.currentName, style: T.title, maxLines: 2),
            ),
          ]),
        ),
        span: 2,
      ),
      for (final h in habits)
        DashItem(StatTile(
          label: h.name,
          value: '${h.streak}',
          unit: h.streak == 1 ? 'day' : 'days',
          trend: h.last14,
        )),
      if (habits.isEmpty) const DashItem(StatTile(label: 'Habit streaks', value: null)),
      const DashItem(StatTile(label: 'Study this week', value: null)),
      const DashItem(StatTile(label: 'Journal this week', value: null)),
      DashItem(
        HoldingsTile(netWorth: netWorth, currency: currency, unlock: unlock, onTap: onOpenSub == null ? null : () => onOpenSub!(2)),
        span: 2,
      ),
    ]);
  }
}

class HoldingsTile extends StatefulWidget {
  const HoldingsTile({super.key, required this.netWorth, required this.currency, required this.unlock, this.onTap});
  final dynamic netWorth;
  final String currency;
  final Unlock unlock;
  final VoidCallback? onTap;

  @override
  State<HoldingsTile> createState() => _HoldingsTileState();
}

class _HoldingsTileState extends State<HoldingsTile> with WidgetsBindingObserver {
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _shown) setState(() => _shown = false);
  }

  Future<void> _reveal() async {
    if (_shown) {
      setState(() => _shown = false);
      return;
    }
    final ok = await widget.unlock();
    if (mounted && ok) setState(() => _shown = true);
  }

  @override
  Widget build(BuildContext context) {
    final has = widget.netWorth != null;
    return DashTile(
      label: 'Holdings',
      onTap: has ? _reveal : null,
      child: !has
          ? const DashEmpty()
          : Text(
              _shown ? fmt.money(widget.netWorth, currency: widget.currency, compact: true) : 'Tap to reveal',
              style: _shown ? T.headline.copyWith(fontSize: 26, fontFeatures: kTabular) : T.small.copyWith(color: C.text3),
            ),
    );
  }
}
