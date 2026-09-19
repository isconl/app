import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../theme.dart';
import 'desktop_shell.dart';
import 'shell.dart';

/// Picks the chrome: native platforms and narrow web viewports keep the
/// existing phone-shaped [Shell]; wide web viewports get [DesktopShell].
///
/// kIsWeb-gated FIRST so the desktop branch is dead code (compiler-pruned)
/// on Android/Linux/Windows - those already run on windows no narrower than
/// a phone, and there is no existing breakpoint logic anywhere in this app,
/// so a width-only trigger would silently change the shipped native UX.
class AdaptiveShell extends StatelessWidget {
  const AdaptiveShell({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return const Shell();
    return LayoutBuilder(
      builder: (context, constraints) =>
          constraints.maxWidth >= Sz.desktopMinWidth
              ? const DesktopShell()
              : const Shell(),
    );
  }
}
