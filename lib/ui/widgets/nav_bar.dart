import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme.dart';

/// The bottom navigation bar.
///
/// Behaviour ARCHITECT asked for, taken from the google_nav_bar reference:
/// inactive items are icons alone, and the selected item expands into a
/// rounded pill carrying icon and label together. The row re-flows as the
/// pill grows and shrinks, so the movement reads as one gesture rather than
/// five independent widgets blinking.
///
/// Rendered in our own system rather than the package's: green brand accent
/// on the panel ground, `C.greenBg` pill, `C.greenBright` content, Inter at
/// the label scale already used everywhere else. No dependency added.
///
/// Two kinds of item live in the same row:
///  - **tabs** hold the pill for as long as they are selected
///  - **actions** (Ask, Menu) open a sheet, so they flash the pill for the
///    length of the animation and release it. That flash is the press
///    acknowledgement; without it a tap on Ask feels unregistered on a slow
///    sheet.
class PillNavItem {
  const PillNavItem({
    required this.icon,
    required this.label,
    this.isTab = true,
    this.restingColor,
    this.badge,
  });

  final IconData icon;
  final String label;

  /// Tabs keep the pill. Actions flash it and let go.
  final bool isTab;

  /// Overrides the muted resting colour. Ask uses it so the one item that is
  /// always worth reaching for stays findable without being loud.
  final Color? restingColor;

  /// Painted over the top-right of the icon. Alerts uses it for the unseen
  /// count.
  final Widget? badge;
}

class PillNavBar extends StatefulWidget {
  const PillNavBar({
    super.key,
    required this.items,
    required this.index,
    required this.onSelect,
  });

  final List<PillNavItem> items;

  /// Index of the selected tab, or -1 when none of the items is a tab.
  final int index;

  final void Function(int index) onSelect;

  @override
  State<PillNavBar> createState() => _PillNavBarState();
}

class _PillNavBarState extends State<PillNavBar> {
  static const _duration = Duration(milliseconds: 220);
  static const _curve = Curves.easeOutCubic;

  /// Index of a non-tab item currently flashing its pill, or null.
  int? _flash;

  void _tap(int i) {
    HapticFeedback.selectionClick();
    if (!widget.items[i].isTab) {
      setState(() => _flash = i);
      Future.delayed(_duration * 1.6, () {
        if (mounted && _flash == i) setState(() => _flash = null);
      });
    }
    widget.onSelect(i);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xEB0D1117),
        border: Border(top: BorderSide(color: C.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (var i = 0; i < widget.items.length; i++)
                _NavPill(
                  item: widget.items[i],
                  active: widget.items[i].isTab
                      ? widget.index == i
                      : _flash == i,
                  duration: _duration,
                  curve: _curve,
                  onTap: () => _tap(i),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavPill extends StatelessWidget {
  const _NavPill({
    required this.item,
    required this.active,
    required this.duration,
    required this.curve,
    required this.onTap,
  });

  final PillNavItem item;
  final bool active;
  final Duration duration;
  final Curve curve;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final resting = item.restingColor ?? C.text3;
    final tint = active ? C.greenBright : resting;

    Widget icon = Icon(item.icon, size: 21, color: tint);
    if (item.badge != null) {
      icon = Stack(
        clipBehavior: Clip.none,
        children: [
          icon,
          Positioned(right: -7, top: -4, child: item.badge!),
        ],
      );
    }

    return Semantics(
      button: true,
      selected: active,
      label: item.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        splashColor: C.greenBg2,
        highlightColor: Colors.transparent,
        child: AnimatedContainer(
          duration: duration,
          curve: curve,
          padding: EdgeInsets.symmetric(
            horizontal: active ? 14 : 11,
            vertical: 9,
          ),
          decoration: BoxDecoration(
            color: active ? C.greenBg : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon,
              // AnimatedSize on the label is what produces the slide: the
              // pill's width is driven by its child, so growing the text from
              // zero width carries the whole pill open with it.
              AnimatedSize(
                duration: duration,
                curve: curve,
                alignment: Alignment.centerLeft,
                child: active
                    ? Padding(
                        padding: const EdgeInsets.only(left: 8, right: 1),
                        child: Text(
                          item.label,
                          maxLines: 1,
                          softWrap: false,
                          style: T.tiny.copyWith(
                            fontSize: 11.5,
                            color: C.greenBright,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    : const SizedBox(height: 0, width: 0),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
