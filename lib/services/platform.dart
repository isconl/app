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

  /// BI26100138: fired when the home-screen widget or an app shortcut opens the app while it is running:
  /// "capture", "voice" or "today".
  void Function(String action)? onLaunchAction;

  void init() {
    if (kIsWeb) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'sharedText' && call.arguments is String) {
        onSharedText?.call(call.arguments as String);
      }
      if (call.method == 'launchAction' && call.arguments is String) {
        onLaunchAction?.call(call.arguments as String);
      }
      return null;
    });
  }

  /// The widget or shortcut action that cold-launched the app, once; null for an ordinary launch.
  Future<String?> getLaunchAction() async {
    if (kIsWeb) return null;
    try {
      return await _channel.invokeMethod<String>('getLaunchAction');
    } catch (_) {
      return null;
    }
  }

  /// BI26100138: hands the home-screen widget its snapshot (see home_widget_snapshot.dart) and redraws it.
  Future<void> updateWidget(String json) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<void>('updateWidget', {'json': json});
    } catch (_) {
      // An older build without the widget: nothing to update.
    }
  }

  /// Sends the app to the background, for a capture started from the widget that is now saved.
  Future<void> moveToBack() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<void>('moveToBack');
    } catch (_) {}
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
  /// Returns "installing", or "needs_permission" when Android first has to
  /// allow installs from iSconl (Settings is opened, and the install resumes by
  /// itself when Sconl returns).
  Future<String> installApk(String path) async {
    if (kIsWeb) return 'unsupported';
    final r = await _channel.invokeMethod<Object>('installApk', {'path': path});
    return r is String ? r : 'installing';
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
