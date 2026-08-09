import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../api/client.dart';
import 'platform.dart';

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
  Future<bool> downloadAndInstall() async {
    final api = _apiProvider();
    busy = true;
    progress = 0;
    state = 'Downloading v${latestVersion ?? ''}...';
    notifyListeners();

    File? partial;
    try {
      var base = api.baseUrl.trim();
      if (base.endsWith('/')) base = base.substring(0, base.length - 1);

      final req = http.Request('GET', Uri.parse('$base/api/apk/download'));
      if (api.token.isNotEmpty) {
        req.headers['Authorization'] = 'Bearer ${api.token}';
      }
      // Render can be asleep and the file is tens of megabytes: this is the one
      // request in the app that should not be held to the usual budget.
      final res = await http.Client().send(req).timeout(
            const Duration(minutes: 10),
          );

      if (res.statusCode == 404) {
        state = 'The agent has no build to give (or the session expired).';
        return false;
      }
      if (res.statusCode >= 400) {
        state = 'Download failed (${res.statusCode}).';
        return false;
      }

      final total = res.contentLength ?? 0;
      final dir = await getApplicationCacheDirectory();
      final updates = Directory('${dir.path}/updates');
      if (!updates.existsSync()) updates.createSync(recursive: true);

      // A half-written APK must never reach the installer, so it is assembled
      // under a .part name and only renamed once the last byte has landed.
      partial = File('${updates.path}/isconl-update.apk.part');
      if (partial.existsSync()) partial.deleteSync();
      final sink = partial.openWrite();
      var received = 0;
      await for (final chunk in res.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          progress = received / total;
          notifyListeners();
        }
      }
      await sink.flush();
      await sink.close();

      if (total > 0 && received != total) {
        state = 'Download was cut short - not installing a partial build.';
        try { partial.deleteSync(); } catch (_) {}
        return false;
      }

      final file = File('${updates.path}/isconl-update.apk');
      if (file.existsSync()) file.deleteSync();
      await partial.rename(file.path);
      partial = null;

      state = 'Handing to installer...';
      notifyListeners();
      await PlatformBridge.instance.installApk(file.path);
      state = 'Installer launched.';
      return true;
    } on OfflineException {
      state = 'Offline - cannot download.';
      return false;
    } catch (e) {
      state = 'Update failed: $e';
      return false;
    } finally {
      if (partial != null) {
        try { partial.deleteSync(); } catch (_) {}
      }
      busy = false;
      notifyListeners();
    }
  }

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
