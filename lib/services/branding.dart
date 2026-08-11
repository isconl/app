import 'package:flutter/foundation.dart';

import 'branding_stub.dart' if (dart.library.io) 'branding_native.dart' as impl;
import 'platform.dart';

/// User-supplied in-app logo (Settings -> Appearance).
///
/// The Android launcher icon itself is baked at build time: drop a square
/// PNG at branding/icon.png in the repo and CI regenerates every mipmap
/// from it (tool/icon_gen.js). This service only handles the logo shown
/// inside the app chrome, which can change at runtime.
class BrandingService extends ChangeNotifier {
  BrandingService._();
  static final BrandingService instance = BrandingService._();

  Uint8List? logoBytes;

  Future<void> load() async {
    try {
      final bytes = await impl.loadLogo();
      if (bytes != null) {
        logoBytes = bytes;
        notifyListeners();
      }
    } catch (_) {}
  }

  /// Pick an image from the device and adopt it as the in-app logo.
  Future<bool> pickAndSet() async {
    final bytes = await PlatformBridge.instance.pickImage();
    if (bytes == null || bytes.isEmpty) return false;
    if (bytes.length > 2 * 1024 * 1024) return false; // keep it sane
    await impl.saveLogo(bytes);
    logoBytes = bytes;
    notifyListeners();
    return true;
  }

  Future<void> reset() async {
    try {
      await impl.deleteLogo();
    } catch (_) {}
    logoBytes = null;
    notifyListeners();
  }
}
