import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../api/client.dart';
import 'updater_stub.dart' if (dart.library.io) 'updater_native.dart' as impl;

/// Self-update, served by the agent.
///
/// This used to talk to the GitHub API directly, which meant the phone had to
/// carry a fine-grained PAT for a private repo - a second long-lived credential
/// on the most losable device, for the sole purpose of downloading a file the
/// agent could already hand over. It now asks the agent instead:
///
///   GET /api/apk/latest    what build exists
///   GET /api/apk/download  the signed binary itself
///
/// Both are gated by the session the app already holds, so there is no second
/// credential to store, rotate or leak. The server does the GitHub talking with
/// the token that already lives in the vault.
class UpdateService extends ChangeNotifier {
  UpdateService(this._apiProvider);

  final ApiClient Function() _apiProvider;

  String installedVersion = '';
  String? latestVersion;
  String? state; // human status line
  bool busy = false;
  double progress = 0;

  /// Metadata for the build the agent is offering, once [check] has run.
  Map<String, dynamic>? available;

  Future<void> loadInstalled() async {
    final info = await PackageInfo.fromPlatform();
    installedVersion = info.version;
    notifyListeners();
  }

  /// Returns the newer version string, or null when up to date or unreachable.
  Future<String?> check() async {
    busy = true;
    state = 'Asking the agent what build exists...';
    notifyListeners();
    try {
      final res = await _apiProvider().getJson('/api/apk/latest', cold: true);
      final map = res is Map ? res.cast<String, dynamic>() : <String, dynamic>{};

      if (map['available'] != true) {
        state = (map['error'] as String?) ?? 'No build published yet.';
        available = null;
        return null;
      }

      available = map;
      latestVersion = (map['version'] ?? '').toString();
      if (compareVersions(latestVersion!, installedVersion) <= 0) {
        state = 'Up to date (v$installedVersion).';
        return null;
      }
      final size = (map['sizeLabel'] ?? '').toString();
      state = 'v$latestVersion available${size.isEmpty ? '' : ' · $size'}.';
      return latestVersion;
    } on OfflineException {
      state = 'Offline - cannot check for updates.';
      return null;
    } on ApiException catch (e) {
      state = 'Check failed: ${e.message}';
      return null;
    } catch (e) {
      state = 'Check failed: $e';
      return null;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Download the agent's copy of the APK and hand it to the system installer.
  /// Native-only past this point (see updater_stub.dart for the web branch).
  Future<bool> downloadAndInstall() async {
    busy = true;
    progress = 0;
    state = 'Downloading v${latestVersion ?? ''}...';
    notifyListeners();
    try {
      return await impl.downloadAndInstall(this, _apiProvider());
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Lets updater_native.dart notify listeners after mutating [state]/
  /// [progress] directly - notifyListeners itself is @protected.
  void bump() => notifyListeners();

  /// Semver-ish compare: positive when [a] is newer than [b].
  static int compareVersions(String a, String b) {
    List<int> parts(String v) => v
        .split('.')
        .map((x) => int.tryParse(x.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();
    final pa = parts(a), pb = parts(b);
    for (var idx = 0; idx < 3; idx++) {
      final da = idx < pa.length ? pa[idx] : 0;
      final db = idx < pb.length ? pb[idx] : 0;
      if (da != db) return da - db;
    }
    return 0;
  }
}
