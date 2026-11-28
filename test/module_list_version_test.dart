// BI26110592: the list row's standard. The register's blank `-` came through as every module's version.
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/util/module_standard.dart';

void main() {
  const file = '20261006_medicine_surgery_med_human_anatomy_module_00_the_eleven_systems_v4_0_0.md';

  test('the blank placeholder falls back to the version in the file name', () {
    expect(moduleListVersion('-', file), '4.0.0');
    expect(standardTagFor(version: moduleListVersion('-', file)).unknown, isFalse);
  });
  test('an empty version falls back too', () {
    expect(moduleListVersion('', file), '4.0.0');
    expect(moduleListVersion(null, file), '4.0.0');
  });
  test('a real served version wins', () {
    expect(moduleListVersion('4.5.0', file), '4.5.0');
    expect(moduleListVersion('v4.5.0', file), 'v4.5.0');
  });
  test('with no version anywhere it stays unknown, honestly', () {
    expect(moduleListVersion('-', '02_mindset.md'), isNull);
    expect(standardTagFor(version: moduleListVersion('-', '02_mindset.md')).unknown, isTrue);
  });
}
