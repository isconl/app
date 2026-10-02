import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

Future<File> _logoFile() async {
  final dir = await getApplicationDocumentsDirectory();
  return File('${dir.path}/brand-logo.png');
}

Future<Uint8List?> loadLogo() async {
  final file = await _logoFile();
  if (!file.existsSync()) return null;
  return file.readAsBytes();
}

Future<void> saveLogo(Uint8List bytes) async {
  final file = await _logoFile();
  await file.writeAsBytes(bytes, flush: true);
}

Future<void> deleteLogo() async {
  final file = await _logoFile();
  if (file.existsSync()) await file.delete();
}
