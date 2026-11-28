import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/ui/widgets/space_header.dart';
import 'package:isconl/ui/widgets/space_manifest.dart';

void main() {
  group('spaceDestinations manifest', () {
    test('every space in manifest has exactly five destinations with Overview first and Activity last', () {
      expect(spaceDestinations.isNotEmpty, isTrue);
      for (final entry in spaceDestinations.entries) {
        expect(entry.value.length, 5, reason: '${entry.key} must have exactly 5 destinations');
        expect(entry.value.first, 'Overview', reason: '${entry.key} slot 1 must be Overview');
        expect(entry.value.last, 'Activity', reason: '${entry.key} slot 5 must be Activity');
      }
    });

    test('every manifest destination label has a corresponding icon in spaceTabIcons', () {
      for (final entry in spaceDestinations.entries) {
        for (final label in entry.value) {
          expect(spaceTabIcons.containsKey(label), isTrue,
              reason: 'label "$label" in space "${entry.key}" must have an icon in spaceTabIcons');
        }
      }
    });
  });

  group('fiveDestinations mapper', () {
    test('maps calendar tabs onto five slots and adds PlannedDestination for Activity', () {
      final tabs = [
        const SpaceTab('Overview', SizedBox()),
        const SpaceTab('Equicycle', SizedBox()),
        const SpaceTab('Month', SizedBox()),
        const SpaceTab('Planner', SizedBox()),
      ];
      final mapped = fiveDestinations('calendar', tabs);
      expect(mapped.length, 5);
      expect([for (final t in mapped) t.label], ['Overview', 'Equicycle', 'Month', 'Planner', 'Activity']);
      expect(isPlannedDestination(mapped[0]), isFalse);
      expect(isPlannedDestination(mapped[1]), isFalse);
      expect(isPlannedDestination(mapped[2]), isFalse);
      expect(isPlannedDestination(mapped[3]), isFalse);
      expect(isPlannedDestination(mapped[4]), isTrue);
    });

    test('handles renames such as hub Now -> Overview', () {
      final tabs = [
        const SpaceTab('Now', SizedBox()),
        const SpaceTab('Today', SizedBox()),
        const SpaceTab('Services', SizedBox()),
      ];
      final mapped = fiveDestinations('hub', tabs);
      expect(mapped.length, 5);
      expect(mapped[0].label, 'Overview');
      expect(isPlannedDestination(mapped[0]), isFalse);
      expect(mapped[1].label, 'Today');
      expect(isPlannedDestination(mapped[1]), isFalse);
      expect(mapped[2].label, 'Notices');
      expect(isPlannedDestination(mapped[2]), isTrue);
      expect(mapped[3].label, 'Services');
      expect(isPlannedDestination(mapped[3]), isFalse);
      expect(mapped[4].label, 'Activity');
      expect(isPlannedDestination(mapped[4]), isTrue);
    });

    test('unknown space preserves its tabs unchanged', () {
      final tabs = [
        const SpaceTab('Custom1', SizedBox()),
        const SpaceTab('Custom2', SizedBox()),
      ];
      final mapped = fiveDestinations('unknown_space_xyz', tabs);
      expect(mapped, same(tabs));
    });

    test('firstRealDestination returns index of first non-planned destination', () {
      final tabs = [
        const SpaceTab('Overview', PlannedDestination(label: 'Overview', about: '')),
        const SpaceTab('WorkingTab', SizedBox()),
        const SpaceTab('Activity', PlannedDestination(label: 'Activity', about: '')),
      ];
      expect(firstRealDestination(tabs), 1);
    });
  });
}
