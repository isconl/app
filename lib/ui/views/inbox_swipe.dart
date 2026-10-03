import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme.dart';
import '../../util/snooze.dart';

/// BI26100139: swipe right marks a thread done, swipe left snoozes it. Both
/// need 35% of the width to act and tick the haptic once at the threshold.
/// The parent removes the thread from its list in [onDone] / [onSnooze]
/// (a dismissed Dismissible may not stay in the tree) and offers the undo.
class SwipeThread extends StatefulWidget {
  const SwipeThread({
    super.key,
    required this.child,
    required this.onDone,
    required this.chooseSnooze,
    required this.onSnooze,
  });
  final Widget child;
  final VoidCallback onDone;

  /// Opens the snooze sheet; null means the user backed out and the row springs back.
  final Future<SnoozeChoice?> Function() chooseSnooze;
  final void Function(SnoozeChoice choice) onSnooze;

  @override
  State<SwipeThread> createState() => _SwipeThreadState();
}

class _SwipeThreadState extends State<SwipeThread> {
  SnoozeChoice? _chosen;
  bool _reached = false;

  Widget _bg(Color color, IconData icon, Alignment align) => Container(
        alignment: align,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(Sz.rMd)),
        child: Icon(icon, color: color),
      );

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: widget.key ?? UniqueKey(),
      dismissThresholds: const {DismissDirection.startToEnd: 0.35, DismissDirection.endToStart: 0.35},
      background: _bg(C.green, Icons.check_rounded, Alignment.centerLeft),
      secondaryBackground: _bg(C.amber, Icons.schedule_rounded, Alignment.centerRight),
      onUpdate: (d) {
        if (d.reached != _reached) {
          _reached = d.reached;
          if (_reached) HapticFeedback.selectionClick();
        }
      },
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) return true;
        _chosen = await widget.chooseSnooze();
        return _chosen != null;
      },
      onDismissed: (direction) {
        if (direction == DismissDirection.startToEnd) {
          widget.onDone();
        } else if (_chosen != null) {
          widget.onSnooze(_chosen!);
        }
      },
      child: widget.child,
    );
  }
}

/// The snooze sheet: the three choices with the time each one resolves to.
Future<SnoozeChoice?> showSnoozeSheet(BuildContext context, DateTime now) {
  return showModalBottomSheet<SnoozeChoice>(
    context: context,
    backgroundColor: C.panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Sz.rXl)),
      side: BorderSide(color: C.border),
    ),
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 8),
        for (final c in snoozeChoices(now))
          ListTile(
            dense: true,
            leading: const Icon(Icons.schedule_rounded, size: 18),
            title: Text(c.label, style: T.body2),
            trailing: Text(_clock(c.until, now), style: T.monoSmall),
            onTap: () => Navigator.pop(ctx, c),
          ),
        const SizedBox(height: 8),
      ]),
    ),
  );
}

String _clock(DateTime t, DateTime now) {
  final hm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  final same = t.year == now.year && t.month == now.month && t.day == now.day;
  return same ? hm : '${const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][t.weekday - 1]} $hm';
}

/// A snackbar for 5 seconds with Undo; a second action replaces the first.
void showUndoBar(BuildContext context, String text, VoidCallback undo) {
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: Text(text),
    duration: const Duration(seconds: 5),
    persist: false, // an action snackbar otherwise stays until dismissed
    action: SnackBarAction(label: 'Undo', onPressed: undo),
  ));
}
