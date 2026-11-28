/// BH26101801: the Device tab's door to the device's own storage. On Android the picker is the system document picker
/// (Storage Access Framework); on desktop the host file system; in the web console the browser's file chooser (drag
/// and drop reaches the same [PickedFile] list). Saving goes through the existing saveAndOpenExport bridge.
library;

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:file_picker/file_picker.dart';

import '../ui/views/learning_export_stub.dart' if (dart.library.io) '../ui/views/learning_export_native.dart' as export_impl;
import 'hold_device_stub.dart' if (dart.library.io) 'hold_device_io.dart' as dev;
import 'hold_uploads.dart';

class PickedFile {
  const PickedFile(this.name, this.source);
  final String name;
  final UploadSource source;
}

abstract class DevicePicker {
  Future<List<PickedFile>> pick();

  /// Writes [bytes] to the device and returns whether it landed.
  Future<bool> save(String name, Uint8List bytes);
}

class SystemDevicePicker implements DevicePicker {
  const SystemDevicePicker();

  @override
  Future<List<PickedFile>> pick() async {
    final r = await FilePicker.platform.pickFiles(allowMultiple: true, withData: kIsWeb);
    if (r == null) return const [];
    final out = <PickedFile>[];
    for (final f in r.files) {
      final path = f.path;
      final src = path == null ? null : dev.sourceFromPath(path, f.size);
      if (src != null) {
        out.add(PickedFile(f.name, src));
      } else if (f.bytes != null) {
        out.add(PickedFile(f.name, BytesSource(f.bytes!)));
      }
    }
    return out;
  }

  @override
  Future<bool> save(String name, Uint8List bytes) => export_impl.saveAndOpenExport(name, bytes, mime: 'application/octet-stream');
}

/// A scripted picker for tests.
class FakeDevicePicker implements DevicePicker {
  FakeDevicePicker(this.files);
  final List<PickedFile> files;
  final Map<String, Uint8List> saved = {};

  @override
  Future<List<PickedFile>> pick() async => files;

  @override
  Future<bool> save(String name, Uint8List bytes) async {
    saved[name] = bytes;
    return true;
  }
}
