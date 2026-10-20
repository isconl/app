import 'dart:io';
import 'dart:typed_data';

import 'hold_uploads.dart';

/// A file on the phone or desktop, read in ranges so a 200 MB upload never sits in memory whole.
class PathSource implements UploadSource {
  PathSource(this.path, this.size);
  final String path;
  @override
  final int size;

  @override
  Future<Uint8List> read(int start, int length) async {
    final f = await File(path).open();
    try {
      await f.setPosition(start);
      return await f.read(length);
    } finally {
      await f.close();
    }
  }
}

UploadSource? sourceFromPath(String path, int size) => PathSource(path, size);
