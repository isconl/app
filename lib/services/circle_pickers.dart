import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

/// A file the reader chose, read into memory.
class PickedBytes {
  const PickedBytes(this.name, this.bytes, {this.contentType = ''});
  final String name;
  final Uint8List bytes;
  final String contentType;
}

/// The chat export size hub accepts: one chat, not everything.
const maxChatBytes = 12 * 1024 * 1024;

/// A chat export (.zip or .txt) from the file picker, or null when none was chosen.
Future<PickedBytes?> pickChatExport() async {
  final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['zip', 'txt'], withData: true);
  final f = r?.files.single;
  if (f == null || f.bytes == null) return null;
  return PickedBytes(f.name, f.bytes!);
}

/// A photo or video from the camera roll, or null.
Future<PickedBytes?> pickMedia() async {
  final x = await ImagePicker().pickMedia();
  if (x == null) return null;
  return PickedBytes(x.name, await x.readAsBytes(), contentType: x.mimeType ?? '');
}
