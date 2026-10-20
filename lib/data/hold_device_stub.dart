import 'hold_uploads.dart';

/// Web has no file paths: the picker hands over bytes and the caller wraps them in a [BytesSource].
UploadSource? sourceFromPath(String path, int size) => null;
