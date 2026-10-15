import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/console/audio_backends.dart';

void main() {
  test('where there is no media service the background setup answers false and never throws', () async {
    // The test host is not Android, so this is the "init cannot happen" path: startup carries on, playback stays foreground.
    expect(await ensureBackgroundAudio(), isFalse);
    expect(await ensureBackgroundAudio(), isFalse);
  });
}
