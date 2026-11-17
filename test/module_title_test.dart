import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/ui/views/learning.dart' show safeModuleTitle;

/// BI26100404: a module title is never "---".
void main() {
  test('a real title is kept', () {
    expect(safeModuleTitle('Planning Twelve Weeks', 'a.md'), 'Planning Twelve Weeks');
  });

  test('--- and empty titles fall back to the humanised file name', () {
    const f = '20261001_corporate_mandate_reading_ceo_direction_module_06_v3_1_0.md';
    expect(safeModuleTitle('---', f), 'Corporate mandate reading ceo direction module 06');
    expect(safeModuleTitle('--- title: x', f), 'Corporate mandate reading ceo direction module 06');
    expect(safeModuleTitle('', '03-leverage-and-capital.md'), 'Leverage and capital');
    expect(safeModuleTitle('  ', 'x.md'), 'X');
  });
}
