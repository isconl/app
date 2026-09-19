/// PDF export needs a browser download flow on web, not a device file-open -
/// not built yet (Phase A is boot/chrome plumbing, not feature parity).
Future<bool> saveAndOpenExport(String name, List<int> bytes) async => false;
