import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../services/platform.dart';

/// Writes [bytes] to a temp exports dir under [name] and asks the OS to open
/// it. Returns true if something on the device opened the file.
Future<bool> saveAndOpenExport(String name, List<int> bytes) async {
  final tmp = await getTemporaryDirectory();
  final dir = Directory('${tmp.path}/exports');
  if (!await dir.exists()) await dir.create(recursive: true);
  final out = File('${dir.path}/$name');
  await out.writeAsBytes(bytes, flush: true);
  return PlatformBridge.instance.openFile(out.path);
}
