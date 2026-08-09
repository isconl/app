import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../api/client.dart';

/// Auth + connection state. Tokens live in Android EncryptedSharedPreferences
/// via flutter_secure_storage - never in plain prefs.
class SessionService extends ChangeNotifier {
  SessionService();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  /* THERE IS NO DEFAULT SERVER, AND THAT IS THE POINT.
   *
   * This used to be 'https://isconl-agent.onrender.com'. That host is declared in
   * render.yaml as a layout instance - "FOR LOOKING AT THE INTERFACE, NOT FOR
   * HOLDING ANYTHING REAL" - with no Bitwarden token, no vault, and
   * ISCONL_DEMO_SEED=1 filling the board with invented placeholder tasks. So the
   * shipped app opened onto fabricated data and looked like it was working.
   *
   * A wrong default is worse than no default: it fails silently and plausibly.
   * An empty one fails immediately and says what it needs.
   *
   * ARCHITECT's instruction, 7 Aug 2026: "i especially do not want the client apps
   * relying on the render server, eliminate this completely". This is step one of
   * that - the client no longer carries the address of a box holding nothing.
   */
  static const defaultServer = '';

  late final ApiClient api =
      ApiClient(baseUrl: defaultServer)..onAuthFailure = _onAuthFailure;

  bool ready = false; // storage loaded
  bool authenticated = false;
  bool biometricLock = false;
  String serverUrl = defaultServer;
  Map<String, dynamic>? serverHealth;

  /// True when no agent address has been set yet. The shell uses it to ask for
  /// one rather than firing requests at an empty base URL and reporting them as
  /// network failures, which is what "no server" used to look like.
  bool get needsServer => serverUrl.trim().isEmpty;

  Future<void> load() async {
    serverUrl = await _storage.read(key: 'serverUrl') ?? defaultServer;
    final token = await _storage.read(key: 'token') ?? '';
    biometricLock = (await _storage.read(key: 'bioLock')) == '1';
    _bioChosen = (await _storage.read(key: 'bioChosen')) == '1';
    // Updates come from the agent now, so the GitHub PAT this app used to keep
    // has no remaining purpose. Delete it on sight rather than leave a live
    // credential sitting on the phone after the upgrade that stopped using it.
    await _storage.delete(key: 'ghPat');
    api.baseUrl = serverUrl;
    api.token = token;
    authenticated = token.isNotEmpty;
    ready = true;
    notifyListeners();
  }

  void _onAuthFailure() {
    // Static tokens stay valid; only TOTP session tokens expire. Either way
    // the server said 404 on a core route: force re-login.
    if (!authenticated) return;
    authenticated = false;
    notifyListeners();
  }

  Future<void> setServer(String url) async {
    serverUrl = url.trim().isEmpty ? defaultServer : url.trim();
    api.baseUrl = serverUrl;
    await _storage.write(key: 'serverUrl', value: serverUrl);
    notifyListeners();
  }

  /// True once HE has decided, either way, in Settings. Until then the lock is
  /// armed automatically - see _armBiometricsIfUnchosen.
  bool _bioChosen = false;

  Future<void> setBiometricLock(bool enabled) async {
    biometricLock = enabled;
    _bioChosen = true;
    await _storage.write(key: 'bioLock', value: enabled ? '1' : '0');
    await _storage.write(key: 'bioChosen', value: '1');
    notifyListeners();
  }

  /* ── ONE CODE, THEN A FINGERPRINT ────────────────────────────────────────
   *
   * ARCHITECT's instruction, 7 Aug 2026: "i would like just one login with the
   * code, after that, i would like the session to persist and to login with
   * just biometrics".
   *
   * The session already persisted - sliding tokens landed earlier. What did not
   * happen was the second half: biometricLock defaulted to FALSE and was an
   * opt-in buried in Settings, so after the code the app simply opened. The
   * device lock was the only thing standing between a picked-up phone and his
   * entire vault.
   *
   * So the lock ARMS ITSELF on the first successful login, on a device that can
   * actually do it. Deliberately not a prompt: he has already said he wants
   * this, and a dialog asking him to confirm a preference he stated is a worse
   * experience than the preference simply being true.
   *
   * It arms once and never fights him. The moment he touches the toggle in
   * Settings, `bioChosen` is set and this never runs again - turning it off
   * stays off, which is the whole difference between a default and a policy.
   */
  Future<void> _armBiometricsIfUnchosen() async {
    if (_bioChosen || biometricLock) return;
    try {
      final auth = LocalAuthentication();
      final can = await auth.canCheckBiometrics || await auth.isDeviceSupported();
      if (!can) return;   // no sensor: arming it would lock him out of his own brain
      biometricLock = true;
      await _storage.write(key: 'bioLock', value: '1');
      notifyListeners();
    } catch (_) {
      // A sensor that throws on probe is a sensor we do not trust to unlock.
    }
  }

  /// Which login methods the server offers.
  Future<Map<String, dynamic>> authMethods() async {
    final res = await api.getJson('/api/auth/methods', cold: true);
    return res is Map ? res.cast<String, dynamic>() : {};
  }

  /// Exchange a 6-digit TOTP code for a 12h session token.
  Future<String?> loginTotp(String code) async {
    try {
      final res = await api.postJson('/api/auth/totp', {'code': code}, cold: true);
      final map = res is Map ? res.cast<String, dynamic>() : <String, dynamic>{};
      if (map['success'] == true && map['token'] is String) {
        await _adopt(map['token'] as String);
        return null;
      }
      return (map['error'] as String?) ?? 'Invalid or expired code';
    } on ApiException catch (e) {
      return e.message;
    } on OfflineException {
      return 'No connection - check network or server URL';
    }
  }

  /// Exchange the quick PIN for a session. Deliberately weaker than TOTP and
  /// the server treats it so - a shorter session, its own lockout bucket - so
  /// this is the way in from a device with no Ente Auth app on it, not the
  /// everyday door.
  ///
  /// Unlike everywhere else in this client, a rejected PIN really is a 401
  /// rather than the usual 404: /api/auth/pin sits outside the gate, so it can
  /// afford to say what went wrong, including how many attempts are left.
  Future<String?> loginPin(String pin) async {
    try {
      final res = await api.postJson('/api/auth/pin', {'pin': pin}, cold: true);
      final map = res is Map ? res.cast<String, dynamic>() : <String, dynamic>{};
      if (map['success'] == true && map['token'] is String) {
        await _adopt(map['token'] as String);
        return null;
      }
      return (map['error'] as String?) ?? 'Incorrect PIN';
    } on ApiException catch (e) {
      return e.message;
    } on OfflineException {
      return 'No connection - check network or server URL';
    }
  }

  /// Use the static dashboard token directly.
  Future<String?> loginToken(String token) async {
    final previous = api.token;
    api.token = token.trim();
    try {
      await api.getJson('/api/state', cold: true);
      await _adopt(token.trim());
      return null;
    } on ApiException {
      api.token = previous;
      return 'Token rejected';
    } on OfflineException {
      api.token = previous;
      return 'No connection - check network or server URL';
    }
  }

  Future<void> _adopt(String token) async {
    api.token = token;
    await _storage.write(key: 'token', value: token);
    authenticated = true;
    notifyListeners();
    // After the code, the fingerprint. Awaited after notifying so the shell
    // paints immediately rather than waiting on a sensor probe.
    await _armBiometricsIfUnchosen();
  }

  Future<void> logout() async {
    try {
      await api.postJson('/api/auth/logout', {});
    } catch (_) {}
    api.token = '';
    await _storage.delete(key: 'token');
    authenticated = false;
    notifyListeners();
  }

  Future<void> probeHealth() async {
    serverHealth = await api.health();
    notifyListeners();
  }
}
