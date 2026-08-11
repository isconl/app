import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme.dart';
import 'common.dart';
import 'sidebar_rail.dart' show NavItem, navGroups;

/// Ctrl/Cmd+K overlay matching dashboard/index.html's `#cmd-overlay` -
/// full-screen blurred scrim, centered search, grouped "go to" results.
Future<void> showCommandPalette(
    BuildContext context, void Function(NavItem) onSelect) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black54,
    builder: (ctx) => Align(
      alignment: const Alignment(0, -0.55),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: _CommandPalette(onSelect: onSelect),
      ),
    ),
  );
}

class _CommandPalette extends StatefulWidget {
  const _CommandPalette({required this.onSelect});
  final void Function(NavItem) onSelect;

  @override
  State<_CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<_CommandPalette> {
  final _query = TextEditingController();
  String _q = '';

  List<NavItem> get _matches {
    if (_q.trim().isEmpty) {
      return [for (final g in navGroups) ...g.items];
    }
    final q = _q.trim().toLowerCase();
    return [
      for (final g in navGroups)
        for (final item in g.items)
          if (item.label.toLowerCase().contains(q)) item,
    ];
  }

  void _choose(NavItem item) {
    Navigator.of(context).pop();
    widget.onSelect(item);
  }

  @override
  Widget build(BuildContext context) {
    final matches = _matches;
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
      },
      child: Actions(
        actions: {
          DismissIntent: CallbackAction<DismissIntent>(
              onInvoke: (_) => Navigator.of(context).pop()),
        },
        child: Focus(
          autofocus: true,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 560,
              constraints: const BoxConstraints(maxHeight: 420),
              decoration: BoxDecoration(
                color: C.panel,
                borderRadius: BorderRadius.circular(Sz.rLg),
                border: Border.all(color: C.borderMid),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0xA6000000),
                      blurRadius: 40,
                      offset: Offset(0, 8)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                    child: TextField(
                      controller: _query,
                      autofocus: true,
                      style: T.body.copyWith(color: C.text),
                      decoration: const InputDecoration(
                        hintText: 'Go to…',
                        border: InputBorder.none,
                        filled: false,
                      ),
                      onChanged: (v) => setState(() => _q = v),
                      onSubmitted: (_) {
                        if (matches.isNotEmpty) _choose(matches.first);
                      },
                    ),
                  ),
                  const Divider(height: 1),
                  Flexible(
                    child: matches.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 30),
                            child: EmptyState(
                                'No matches', 'Try a different name.'),
                          )
                        : ListView(
                            shrinkWrap: true,
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            children: [
                              const Padding(
                                padding: EdgeInsets.fromLTRB(16, 6, 16, 4),
                                child: SectionLabel('Go to',
                                    padding: EdgeInsets.zero),
                              ),
                              for (final item in matches)
                                ListTile(
                                  dense: true,
                                  leading: Icon(item.icon,
                                      size: 17, color: C.text2),
                                  title: Text(item.label,
                                      style:
                                          T.body2.copyWith(color: C.text)),
                                  onTap: () => _choose(item),
                                ),
                            ],
                          ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Text('ESC to close', style: T.tiny),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
