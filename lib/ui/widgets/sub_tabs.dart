import 'package:flutter/material.dart';

import '../../theme.dart';

/// BI26101519: the one sub-page tab style, lifted from the Codex view so every sub-page reads the same:
/// a flat Material tab bar with a green underline, the selected label bright green, the others dim, and a
/// hairline under the row. Never a filled or blue control.
///
/// [SubTabsBar] is the bar alone, for a view that keeps its own state (the calendar's mode).
/// [SubTabs] is the bar plus the body, one child per label.
TabBar subTabBar({
  required String keyPrefix,
  required List<String> labels,
  TabController? controller,
  ValueChanged<int>? onTap,
  bool scrollable = false,
}) =>
    TabBar(
      key: ValueKey('$keyPrefix-tabs'),
      controller: controller,
      isScrollable: scrollable,
      tabAlignment: scrollable ? TabAlignment.start : null,
      indicatorColor: C.greenBright,
      labelColor: C.greenBright,
      unselectedLabelColor: C.text3,
      dividerColor: C.border,
      onTap: onTap,
      tabs: [for (final l in labels) Tab(key: ValueKey('$keyPrefix-tab-${l.toLowerCase()}'), text: l)],
    );

class SubTabsBar extends StatefulWidget {
  const SubTabsBar({
    super.key,
    required this.keyPrefix,
    required this.labels,
    required this.index,
    required this.onSelect,
  });

  final String keyPrefix;
  final List<String> labels;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  State<SubTabsBar> createState() => _SubTabsBarState();
}

class _SubTabsBarState extends State<SubTabsBar> with SingleTickerProviderStateMixin {
  late final TabController _c = TabController(length: widget.labels.length, vsync: this, initialIndex: widget.index);

  @override
  void didUpdateWidget(covariant SubTabsBar old) {
    super.didUpdateWidget(old);
    if (_c.index != widget.index) _c.animateTo(widget.index);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: subTabBar(keyPrefix: widget.keyPrefix, labels: widget.labels, controller: _c, onTap: widget.onSelect),
      );
}

class SubTabs extends StatefulWidget {
  const SubTabs({
    super.key,
    required this.keyPrefix,
    required this.labels,
    required this.children,
    this.initialIndex = 0,
    this.onChanged,
    this.header,
  });

  final String keyPrefix;
  final List<String> labels;
  final List<Widget> children;
  final int initialIndex;
  final ValueChanged<int>? onChanged;

  /// Shown above the tab bar.
  final Widget? header;

  @override
  State<SubTabs> createState() => _SubTabsState();
}

class _SubTabsState extends State<SubTabs> with SingleTickerProviderStateMixin {
  late final TabController _c = TabController(
    length: widget.labels.length,
    vsync: this,
    initialIndex: widget.initialIndex.clamp(0, widget.labels.length - 1),
  );

  @override
  void initState() {
    super.initState();
    _c.addListener(() {
      if (!_c.indexIsChanging) widget.onChanged?.call(_c.index);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.header != null) widget.header!,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: subTabBar(keyPrefix: widget.keyPrefix, labels: widget.labels, controller: _c),
          ),
          const SizedBox(height: Sz.gap),
          Expanded(
            child: TabBarView(
              controller: _c,
              physics: const NeverScrollableScrollPhysics(),
              children: widget.children,
            ),
          ),
        ],
      );
}
