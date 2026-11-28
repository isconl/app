import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/util/cycle_theme.dart';

void main() {
  test('the cycle own word wins', () {
    final r = resolveCycleWord(cycleNum: 5, own: 'Mend', held: ['Leverage']);
    expect(r.word, 'Mend');
    expect(r.source, CycleWordSource.override);
  });

  test('without an own word, the word compass holds shows, newest cycle first', () {
    final r = resolveCycleWord(cycleNum: 5, held: [null, 'Leverage']);
    expect(r.word, 'Leverage');
    expect(r.source, CycleWordSource.compass);
    expect(resolveCycleWord(cycleNum: 5, held: ['Climb', 'Leverage']).word, 'Climb');
  });

  test('with nothing chosen, the rotation word shows, marked as rotation', () {
    final r = resolveCycleWord(cycleNum: 5, held: [null, '']);
    expect(r.word, 'Dig');
    expect(r.source, CycleWordSource.rotation);
  });

  test('only two earlier cycles are read', () {
    expect(resolveCycleWord(cycleNum: 6, held: [null, null, 'Old']).source, CycleWordSource.rotation);
  });
}
