import 'package:flutter/material.dart';

import '../../theme.dart';
import 'space_header.dart';

/// BI26102802: Rail navigation inside spaces.
/// Vertical pill rail on the right edge holding up to five icons, one per destination.
/// Icon-only, active icon filled with the nav green and a pill highlight,
/// label shown on long press and to screen readers; 48 dp touch targets.
class SpaceRail extends StatelessWidget {
  const SpaceRail({
    super.key,
    required this.tabs,
    required this.currentIndex,
    required this.onSelect,
    this.keyPrefix = 'space',
  });

  final List<SpaceTab> tabs;
  final int currentIndex;
  final ValueChanged<int> onSelect;
  final String keyPrefix;

  static const double width = 52;
  static const double itemSize = 48;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('$keyPrefix-rail'),
      width: width,
      decoration: BoxDecoration(
        color: C.surface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: C.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < tabs.length; i++) _item(context, i, tabs[i]),
        ],
      ),
    );
  }

  Widget _item(BuildContext context, int index, SpaceTab tab) {
    final active = index == currentIndex;
    final slug = tab.label.toLowerCase().replaceAll(RegExp(r'\s+'), '-');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Tooltip(
        message: tab.label,
        preferBelow: false,
        verticalOffset: 28,
        child: Semantics(
          label: tab.label,
          selected: active,
          button: true,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: ValueKey('$keyPrefix-rail-tab-$slug'),
              borderRadius: BorderRadius.circular(24),
              onTap: () => onSelect(index),
              child: Container(
                width: itemSize,
                height: itemSize,
                decoration: BoxDecoration(
                  color: active ? NavTint.bg : Colors.transparent,
                  borderRadius: BorderRadius.circular(24),
                  border: active ? Border.all(color: NavTint.border) : null,
                ),
                alignment: Alignment.center,
                child: Icon(
                  tab.effectiveIcon,
                  key: ValueKey('$keyPrefix-rail-icon-$index'),
                  size: 22,
                  color: active ? NavTint.fg : C.text3,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
