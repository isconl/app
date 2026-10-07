import 'package:flutter/material.dart';

import '../services/updater.dart';
import '../util/fmt.dart' as fmt;
import 'widgets/common.dart';

/// The one way the app checks for and installs an update (4 Oct 2026).
///
/// Every "check for updates" button calls this, never [UpdateService.check]
/// on its own: a check that finds a newer build always offers to install it,
/// so a button can't again stop at "v0.3.54 available" with nothing to tap.
/// test/update_entry_points_test.dart enforces this.
Future<void> runUpdateFlow(BuildContext context, UpdateService updater) async {
  final newer = await updater.check();
  if (newer == null || !context.mounted) return;
  final size = fmt.s(updater.available?['sizeLabel']);
  final go = await confirmDialog(
      context,
      'Update to v$newer?',
      'The agent hands over the signed build'
          '${size.isEmpty ? '' : ' ($size)'} '
          'and Android installs it over this version. Your data stays.',
      action: 'Install');
  if (go) await updater.downloadAndInstall();
}
