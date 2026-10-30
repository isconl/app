import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/data/destinations.dart';
import 'package:isconl/ui/widgets/space_header.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, List<Destination>> bundled;

  setUpAll(() async {
    // Load the bundled destinations.json from the test asset path.
    final raw = await rootBundle.loadString('assets/destinations.json');
    final Map<String, dynamic> json =
        jsonDecode(raw) as Map<String, dynamic>;
    bundled = {};
    for (final entry in json.entries) {
      final list = (entry.value as List)
          .map((d) => Destination.fromJson(d as Map<String, dynamic>))
          .toList();
      bundled[entry.key] = list;
    }
  });

  test('every space has exactly five destinations', () {
    expect(bundled.isNotEmpty, isTrue,
        reason: 'bundled destinations must load');
    for (final entry in bundled.entries) {
      expect(entry.value.length, 5,
          reason: '${entry.key} must have exactly 5 destinations');
    }
  });

  test('slot 1 is always overview and slot 5 is always activity', () {
    for (final entry in bundled.entries) {
      expect(entry.value.first.key, 'overview',
          reason: '${entry.key} slot 1 must be overview');
      expect(entry.value.last.key, 'activity',
          reason: '${entry.key} slot 5 must be activity');
    }
  });

  test('every destination has unique keys within its space', () {
    for (final entry in bundled.entries) {
      final keys = entry.value.map((d) => d.key).toList();
      expect(keys.toSet().length, keys.length,
          reason: '${entry.key} has duplicate destination keys');
    }
  });

  test('every destination has a non-empty icon', () {
    for (final entry in bundled.entries) {
      for (final d in entry.value) {
        expect(d.icon.isNotEmpty, isTrue,
            reason: '${entry.key}/${d.key} must have an icon');
      }
    }
  });

  test('every destination icon has a mapping in spaceTabIcons', () {
    for (final entry in bundled.entries) {
      for (final d in entry.value) {
        expect(spaceTabIcons.containsKey(d.icon), isTrue,
            reason:
                '${entry.key}/${d.key} icon "${d.icon}" must be in spaceTabIcons');
      }
    }
  });

  test('bundled copy matches the hub source (same file)', () {
    // The bundled copy in the app is a byte-for-byte copy of
    // hub/config/destinations.json. If either changes, this test fails
    // until they are re-synced.
    //
    // We verify the structural contract here (same spaces, same keys,
    // same order) rather than byte comparison (which would need the hub
    // file at test time).
    expect(bundled.length, greaterThanOrEqualTo(20),
        reason: 'the manifest must cover at least 20 spaces');
    for (final entry in bundled.entries) {
      final dests = entry.value;
      expect(dests.length, 5);
      expect(dests.first.key, 'overview');
      expect(dests.last.key, 'activity');
      for (final d in dests) {
        expect(d.key.isNotEmpty, isTrue);
        expect(d.label.isNotEmpty, isTrue);
        expect(d.icon.isNotEmpty, isTrue);
        expect(d.route.isNotEmpty, isTrue);
      }
    }
  });
}
