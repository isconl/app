import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/ui/widgets/sidebar_rail.dart';

/// navGroups is a hand-duplicated copy of shell.dart's MenuSheet taxonomy
/// (deliberately, per the hub refactor canvas - see sidebar_rail.dart's own
/// header). Hand-duplicated lists drift and typo; these are the mechanical
/// checks that would catch it.
void main() {
  final allItems = navGroups.expand((g) => g.items).toList();

  test('every nav item id is unique', () {
    final ids = allItems.map((i) => i.id).toList();
    expect(ids.toSet().length, ids.length,
        reason: 'duplicate ids: ${ids.where((id) => ids.where((x) => x == id).length > 1).toSet()}');
  });

  test('every nav group has at least one item', () {
    for (final g in navGroups) {
      expect(g.items, isNotEmpty, reason: '${g.label} has no items');
    }
  });

  test('findNavItem resolves every id declared in navGroups', () {
    for (final item in allItems) {
      expect(findNavItem(item.id).id, item.id);
    }
  });

  test('findNavItem finds settings (SidebarRail\'s Settings button depends on this)', () {
    expect(findNavItem('settings').label, 'Settings');
  });

  test('every item builder constructs without throwing', () {
    for (final item in allItems) {
      expect(() => item.builder(), returnsNormally, reason: item.id);
    }
  });

  test('taxonomy matches MenuSheet\'s (28 items: 25 shared with mobile menu + hub/tasks/alerts)', () {
    expect(allItems.length, 28);
    expect(navGroups.map((g) => g.label), [
      'Hub',
      'Channels',
      'Personal',
      'Circle',
      'Projects & Spaces',
      'System',
    ]);
  });
}
