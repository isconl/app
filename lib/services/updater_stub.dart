import '../api/client.dart';
import 'updater.dart';

/// Web has nothing to install itself into - there is no APK installer in a
/// browser. The web console gets its updates by reloading the page, same as
/// any other site; self-update is a native-app-only concept.
Future<bool> downloadAndInstall(UpdateService service, ApiClient api) async {
  service.state = 'Updates are not available in the web console.';
  return false;
}
