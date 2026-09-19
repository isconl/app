import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../api/client.dart';
import 'platform.dart';
import 'updater.dart';

/// Native half of [UpdateService.downloadAndInstall] - downloads to a temp
/// file and hands it to the platform installer. Not reachable on web (see
/// updater_stub.dart), so this file may assume dart:io is real.
Future<bool> downloadAndInstall(UpdateService service, ApiClient api) async {
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
      service.state = 'The agent has no build to give (or the session expired).';
      return false;
    }
    if (res.statusCode >= 400) {
      service.state = 'Download failed (${res.statusCode}).';
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
        service.progress = received / total;
        service.bump();
      }
    }
    await sink.flush();
    await sink.close();

    if (total > 0 && received != total) {
      service.state = 'Download was cut short - not installing a partial build.';
      try { partial.deleteSync(); } catch (_) {}
      return false;
    }

    final file = File('${updates.path}/isconl-update.apk');
    if (file.existsSync()) file.deleteSync();
    await partial.rename(file.path);
    partial = null;

    service.state = 'Handing to installer...';
    service.bump();
    await PlatformBridge.instance.installApk(file.path);
    service.state = 'Installer launched.';
    return true;
  } on OfflineException {
    service.state = 'Offline - cannot download.';
    return false;
  } catch (e) {
    service.state = 'Update failed: $e';
    return false;
  } finally {
    if (partial != null) {
      try { partial.deleteSync(); } catch (_) {}
    }
  }
}
