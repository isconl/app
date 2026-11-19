import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guard (4 Oct 2026): every update button goes through runUpdateFlow, which
/// always offers to install a newer build. A bare UpdateService.check() in the
/// UI is how the Systems dashboard came to say "v0.3.54 available" and stop.
void main() {
  test('no UI code calls the updater check() directly', () {
    final offenders = <String>[];
    final ui = Directory('lib/ui');
    for (final f in ui.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.endsWith('update_flow.dart')) continue;
      final src = f.readAsStringSync();
      if (RegExp(r'(updater|\bu)\.check\(\)').hasMatch(src)) offenders.add(f.path);
    }
    expect(offenders, isEmpty,
        reason: 'call runUpdateFlow(context, updater) instead: ${offenders.join(', ')}');
  });
}
