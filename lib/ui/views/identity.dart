import 'package:flutter/material.dart';

import '../../theme.dart';
import '../shell.dart' show SecondaryScreen;
import '../widgets/common.dart';
import 'spaces.dart';

/// BI26100207: Personal › Identity. The three archetype spaces moved here from the
/// Spaces section, as on the web console on 16 Sep 2026 (UI label canon row 10).
/// Routes, keys and data are unchanged: each entry opens the same [SpacesView] it
/// always did, and "All spaces" stays one tap away.
class IdentityView extends StatelessWidget {
  const IdentityView({super.key});

  /// The web console's order, with its own hints.
  static const archetypes = <({String label, String axis, String hint, IconData icon})>[
    (label: 'Visionary', axis: 'VIS', hint: 'People, decisions, the record', icon: Icons.visibility_rounded),
    (label: 'Innovator', axis: 'INN', hint: 'Systems built and engineered', icon: Icons.engineering_rounded),
    (label: 'Creator', axis: 'CRE', hint: 'Work made to be seen and used', icon: Icons.palette_rounded),
  ];

  void _open(BuildContext context, String title, Widget child) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => SecondaryScreen(title: title, child: child)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      // The same margins SnapshotView gives every other view.
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 96),
      children: [
        const SectionLabel('Archetypes'),
        for (final a in archetypes)
          Padding(
            padding: const EdgeInsets.only(bottom: Sz.gap),
            child: Panel(
              key: ValueKey('identity-${a.axis}'),
              onTap: () => _open(context, a.label, SpacesView(axis: a.axis)),
              child: Row(children: [
                Icon(a.icon, color: C.greenBright, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(a.label, style: T.w600(T.body.copyWith(color: C.text))),
                    const SizedBox(height: 2),
                    Text(a.hint, style: T.small.copyWith(color: C.text3)),
                  ]),
                ),
                const Icon(Icons.chevron_right_rounded, color: C.text3),
              ]),
            ),
          ),
        const SectionLabel('Everything'),
        Panel(
          key: const ValueKey('identity-all'),
          onTap: () => _open(context, 'Spaces', const SpacesView()),
          child: Row(children: [
            const Icon(Icons.hub_rounded, color: C.cyan, size: 22),
            const SizedBox(width: 12),
            Expanded(child: Text('All spaces', style: T.w600(T.body.copyWith(color: C.text)))),
            const Icon(Icons.chevron_right_rounded, color: C.text3),
          ]),
        ),
      ],
    );
  }
}
