import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/data/modules.dart';

/// The rule under test: a downloaded module stays downloaded until its content
/// changes. Every case here is a way that rule could quietly stop holding.
void main() {
  group('ModuleStatus', () {
    test('absent means nothing to read offline', () {
      const s = ModuleStatus(ModuleState.absent);
      expect(s.downloaded, isFalse);
      expect(s.needsRefresh, isTrue);
    });

    test('current needs no network', () {
      const s = ModuleStatus(ModuleState.current, rev: 'abc123');
      expect(s.downloaded, isTrue);
      expect(s.needsRefresh, isFalse);
    });

    test('stale is readable but wants a refresh', () {
      const s = ModuleStatus(ModuleState.stale, rev: 'old');
      expect(s.downloaded, isTrue, reason: 'stale must never read as absent');
      expect(s.needsRefresh, isTrue);
    });

    // Bodies downloaded before the agent published revisions cannot be
    // compared. They must stay readable rather than be discarded or re-pulled
    // on every open.
    test('unversioned is kept and not refetched', () {
      const s = ModuleStatus(ModuleState.unversioned);
      expect(s.downloaded, isTrue);
      expect(s.needsRefresh, isFalse);
    });
  });

  group('keys', () {
    test('module key and snapshot key agree on the id', () {
      expect(ModuleLibrary.keyOf('viva-tasks', '16-module.md'),
          'viva-tasks/16-module.md');
      expect(ModuleLibrary.snapshotKey('viva-tasks', '16-module.md'),
          'lesson:viva-tasks/16-module.md');
      // The library rebuilds its index by stripping the 'lesson:' prefix, so
      // these two must stay in lockstep or every downloaded module reads as
      // absent after a restart.
      expect(
        ModuleLibrary.snapshotKey('viva-tasks', '16-module.md')
            .substring('lesson:'.length),
        ModuleLibrary.keyOf('viva-tasks', '16-module.md'),
      );
    });
  });
}
