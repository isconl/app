import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import 'common.dart';
import 'sidebar_rail.dart' show NavItem, navGroups;

/// Ctrl/Cmd+K overlay matching dashboard/index.html's `#cmd-overlay` -
/// full-screen blurred scrim, centered search, grouped "GO TO"/"GITHUB CLI"
/// suggestions, and (typed free text + Enter) a live agent answer shown
/// inline, same as the legacy palette's showCmdResult(). Go-to items are
/// search-filtered here, which the legacy version never did - a small
/// improvement kept deliberately, not a fidelity gap.
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

/// The four fixed shortcuts from index.html's `#cmd-suggestions`
/// GITHUB CLI group (data-gh values, unchanged).
const _ghShortcuts = [
  ('Repos', 'gh repo list'),
  ('Pulls', 'gh pr list'),
  ('Issues', 'gh issue list'),
  ('Notifications', 'gh api notifications'),
];

class _CommandPalette extends StatefulWidget {
  const _CommandPalette({required this.onSelect});
  final void Function(NavItem) onSelect;

  @override
  State<_CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<_CommandPalette> {
  final _query = TextEditingController();
  String _q = '';
  bool _asking = false;
  String? _result;

  List<NavItem> get _navMatches {
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

  List<(String, String)> get _ghMatches {
    if (_q.trim().isEmpty) return _ghShortcuts;
    final q = _q.trim().toLowerCase();
    return _ghShortcuts.where((s) => s.$1.toLowerCase().contains(q)).toList();
  }

  void _choose(NavItem item) {
    Navigator.of(context).pop();
    widget.onSelect(item);
  }

  Future<void> _ask(String text) async {
    if (text.trim().isEmpty || _asking) return;
    final services = AppScope.of(context);
    setState(() {
      _asking = true;
      _result = null;
    });
    try {
      final res = await services.api
          .postJson('/api/chat', {'message': text.trim()}, cold: true);
      if (!mounted) return;
      setState(() => _result = fmt.s(fmt.m(res)['response']).isEmpty
          ? 'Nothing came back, which is itself a kind of answer.'
          : fmt.s(fmt.m(res)['response']));
    } catch (e) {
      if (mounted) setState(() => _result = 'Offline or the agent errored: $e');
    } finally {
      if (mounted) setState(() => _asking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final navMatches = _navMatches;
    final ghMatches = _ghMatches;
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
              constraints: const BoxConstraints(maxHeight: 480),
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
                        hintText: "Ask iSconl anything, or type 'gh ...' "
                            'for GitHub CLI...',
                        border: InputBorder.none,
                        filled: false,
                      ),
                      onChanged: (v) => setState(() {
                        _q = v;
                        _result = null;
                      }),
                      onSubmitted: (v) {
                        if (navMatches.isNotEmpty) {
                          _choose(navMatches.first);
                        } else {
                          _ask(v);
                        }
                      },
                    ),
                  ),
                  const Divider(height: 1),
                  if (_asking)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: MiniSpinner(size: 20)),
                    )
                  else if (_result != null)
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Text(_result!,
                            style: T.body2.copyWith(color: C.text)),
                      ),
                    )
                  else
                    Flexible(
                      child: navMatches.isEmpty && ghMatches.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              child: Column(
                                children: [
                                  const EmptyState('No menu matches',
                                      'Press Enter to ask the agent instead.'),
                                  const SizedBox(height: 8),
                                  OutlinedButton.icon(
                                    onPressed: () => _ask(_q),
                                    icon: const Icon(Icons.forum_rounded, size: 15),
                                    label: Text('Ask "${_q.trim()}"'),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                              ),
                            )
                          : ListView(
                              shrinkWrap: true,
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              children: [
                                if (navMatches.isNotEmpty) ...[
                                  const Padding(
                                    padding: EdgeInsets.fromLTRB(16, 6, 16, 4),
                                    child: SectionLabel('Go to',
                                        padding: EdgeInsets.zero),
                                  ),
                                  for (final item in navMatches)
                                    ListTile(
                                      dense: true,
                                      leading: Icon(item.icon,
                                          size: 17, color: C.text2),
                                      title: Text(item.label,
                                          style: T.body2.copyWith(color: C.text)),
                                      onTap: () => _choose(item),
                                    ),
                                ],
                                if (ghMatches.isNotEmpty) ...[
                                  const Padding(
                                    padding: EdgeInsets.fromLTRB(16, 10, 16, 4),
                                    child: SectionLabel('GitHub CLI',
                                        padding: EdgeInsets.zero),
                                  ),
                                  for (final s in ghMatches)
                                    ListTile(
                                      dense: true,
                                      leading: const Icon(Icons.code_rounded,
                                          size: 17, color: C.text2),
                                      title: Text(s.$1,
                                          style: T.body2.copyWith(color: C.text)),
                                      subtitle:
                                          Text(s.$2, style: T.monoSmall),
                                      onTap: () => _ask(s.$2),
                                    ),
                                ],
                              ],
                            ),
                    ),
                  const Divider(height: 1),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Text(
                            _result != null
                                ? 'Enter to ask again · ESC to close'
                                : 'Enter to go/ask · ESC to close',
                            style: T.tiny),
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
