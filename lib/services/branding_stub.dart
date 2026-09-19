import 'dart:typed_data';

/// Web has no writable app-documents directory. A custom logo stays
/// in-memory for the tab's lifetime instead of persisting across reloads -
/// reasonable degradation, not a missing feature worth blocking on.
Uint8List? _sessionLogo;

Future<Uint8List?> loadLogo() async => _sessionLogo;

Future<void> saveLogo(Uint8List bytes) async {
  _sessionLogo = bytes;
}

Future<void> deleteLogo() async {
  _sessionLogo = null;
}
