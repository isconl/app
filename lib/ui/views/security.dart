import 'package:flutter/material.dart';

import '../widgets/common.dart';

/// BN26090606: mobile stub, mirrors the webconsole's own renderSecurity()
/// placeholder exactly -- not yet scoped (`PS26090501`, plan.md). Flagship
/// item once designed: dead-hand remote wipe of data from any logged-in
/// device. Needs its own design pass before this space has real content on
/// either platform.
class SecurityView extends StatelessWidget {
  const SecurityView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(14, 10, 14, 96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Panel(
            child: EmptyState(
              'Coming later',
              'Flagship item: dead-hand remote wipe of data from any '
                  'logged-in device. Needs its own design pass before this '
                  'space has real content.',
              icon: Icons.shield_outlined,
            ),
          ),
        ],
      ),
    );
  }
}
