import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// Bridge to MainActivity.kt (channel "isconl/platform"). None of this
/// channel exists on web - there is no MainActivity - so every method
/// guards itself rather than throwing MissingPluginException up to callers.
class PlatformBridge {
  PlatformBridge._();
  static final PlatformBridge instance = PlatformBridge._();

  static const _channel = MethodChannel('isconl/platform');

  /// Fired when text is shared into the app while it is already running.
  void Function(String text)? onSharedText;

  void init() {
    if (kIsWeb) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'sharedText' && call.arguments is String) {
        onSharedText?.call(call.arguments as String);
      }
      return null;
    });
  }

  /// Text shared into the app via the Android share sheet (cold launch).
  Future<String?> getSharedText() async {
    if (kIsWeb) return null;
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
  /// PDF viewer, and he shares, mails or prints it from there. Always false on
  /// web, where there is no device-level file association to hand off to.
  Future<bool> openFile(String path, {String mime = 'application/pdf'}) async {
    if (kIsWeb) return false;
    final ok = await _channel.invokeMethod<bool>(
        'openFile', {'path': path, 'mime': mime});
    return ok ?? false;
  }

  /// Hand a downloaded APK to the system installer. No-op on web - see
  /// updater_stub.dart, which never calls this on that platform anyway.
  Future<void> installApk(String path) async {
    if (kIsWeb) return;
    await _channel.invokeMethod('installApk', {'path': path});
  }

  /// System image picker; returns raw bytes or null if cancelled. Null on
  /// web for now - no web-native picker wired up yet (Phase A scope).
  Future<Uint8List?> pickImage() async {
    if (kIsWeb) return null;
    try {
      return await _channel.invokeMethod<Uint8List>('pickImage');
    } catch (_) {
      return null;
    }
  }
}
