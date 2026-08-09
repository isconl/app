import 'package:flutter/services.dart';

/// Bridge to MainActivity.kt (channel "isconl/platform").
class PlatformBridge {
  PlatformBridge._();
  static final PlatformBridge instance = PlatformBridge._();

  static const _channel = MethodChannel('isconl/platform');

  /// Fired when text is shared into the app while it is already running.
  void Function(String text)? onSharedText;

  void init() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'sharedText' && call.arguments is String) {
        onSharedText?.call(call.arguments as String);
      }
      return null;
    });
  }

  /// Text shared into the app via the Android share sheet (cold launch).
  Future<String?> getSharedText() async {
    try {
      return await _channel.invokeMethod<String>('getSharedText');
    } catch (_) {
      return null;
    }
  }

  /// Hand a downloaded file to whatever app on the phone opens that type.
  ///
  /// Returns false when nothing on the device can open it - which is an answer
  /// to show him, not a failure to throw. An exported module goes to the system
  /// PDF viewer, and he shares, mails or prints it from there.
  Future<bool> openFile(String path, {String mime = 'application/pdf'}) async {
    final ok = await _channel.invokeMethod<bool>(
        'openFile', {'path': path, 'mime': mime});
    return ok ?? false;
  }

  /// Hand a downloaded APK to the system installer.
  Future<void> installApk(String path) async {
    await _channel.invokeMethod('installApk', {'path': path});
  }

  /// System image picker; returns raw bytes or null if cancelled.
  Future<Uint8List?> pickImage() async {
    try {
      return await _channel.invokeMethod<Uint8List>('pickImage');
    } catch (_) {
      return null;
    }
  }
}
