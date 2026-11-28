import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:passkeys/authenticator.dart';
import 'package:passkeys/types.dart';

/// BI26100204: the phone's side of passkeys. The server speaks WebAuthn JSON (base64url fields), and the platform
/// package takes and returns the same shape, so this layer only hands the JSON over and turns the platform's failures
/// into plain messages. Everything above it (the session, the screens) talks to [PasskeyClient], so tests use a fake
/// and never touch the device.
abstract class PasskeyClient {
  /// True when this device can create and use a passkey. False on the web and on platforms we have not set up.
  Future<bool> available();

  /// Sign in with an existing passkey. [options] is the server's request options; the result is the assertion JSON
  /// the server verifies.
  Future<Map<String, dynamic>> authenticate(Map<String, dynamic> options);

  /// Create a passkey. [options] is the server's creation options; the result is the attestation JSON.
  Future<Map<String, dynamic>> register(Map<String, dynamic> options);
}

/// A passkey step that failed, with a sentence the screen can show as it is. [cancelled] is the user backing out,
/// which is not an error to report loudly.
class PasskeyFailure implements Exception {
  PasskeyFailure(this.message, {this.cancelled = false});
  final String message;
  final bool cancelled;
  @override
  String toString() => message;
}

/// What a new passkey is called until the user renames it: the phone's make and model ("Google Pixel 8"), or "My phone"
/// where that cannot be read.
Future<String> defaultPasskeyName() async {
  try {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final i = await DeviceInfoPlugin().androidInfo;
      final make = i.manufacturer.trim();
      final model = i.model.trim();
      if (model.isNotEmpty) {
        final cap = make.isEmpty ? '' : '${make[0].toUpperCase()}${make.substring(1)} ';
        return model.toLowerCase().startsWith(make.toLowerCase()) ? model : '$cap$model';
      }
    }
  } catch (_) {
    // Fall through to the generic name.
  }
  return 'My phone';
}

/// The failure message for each platform exception. Never includes the exception's own text, which can carry the
/// relying party or credential ids.
PasskeyFailure passkeyFailureFor(Object e) {
  if (e is PasskeyFailure) return e;
  if (e is PasskeyAuthCancelledException) return PasskeyFailure('Passkey cancelled.', cancelled: true);
  if (e is NoCredentialsAvailableException) return PasskeyFailure('No passkey for this app is on this phone. Use your PIN, or add one from Settings.');
  if (e is DomainNotAssociatedException) return PasskeyFailure('This build of the app is not linked to the server for passkeys yet. Use your PIN.');
  if (e is DeviceNotSupportedException || e is PasskeyUnsupportedException) return PasskeyFailure('This phone does not support passkeys. Use your PIN.');
  if (e is MissingGoogleSignInException) return PasskeyFailure('Sign in to a Google account on this phone to use passkeys.');
  if (e is ExcludeCredentialsCanNotBeRegisteredException) return PasskeyFailure('This phone already has a passkey for this app.');
  if (e is TimeoutException) return PasskeyFailure('The passkey prompt timed out. Try again.');
  if (e is MalformedBase64Url) return PasskeyFailure('The server sent a passkey request this app cannot read.');
  return PasskeyFailure('Passkey sign-in did not work. Use your PIN.');
}

/// The real client, on Android. Other platforms report unavailable, so the sign-in screen never offers a button it
/// cannot honour.
class PlatformPasskeyClient implements PasskeyClient {
  PlatformPasskeyClient({PasskeyAuthenticator? authenticator}) : _auth = authenticator;
  PasskeyAuthenticator? _auth;
  PasskeyAuthenticator get _a => _auth ??= PasskeyAuthenticator();

  @override
  Future<bool> available() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      // ignore: deprecated_member_use
      return await _a.canAuthenticate();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Map<String, dynamic>> authenticate(Map<String, dynamic> options) async {
    try {
      final r = await _a.authenticate(AuthenticateRequestType.fromJson(options));
      return r.toJson();
    } catch (e) {
      throw passkeyFailureFor(e);
    }
  }

  @override
  Future<Map<String, dynamic>> register(Map<String, dynamic> options) async {
    try {
      final r = await _a.register(RegisterRequestType.fromJson(options));
      return r.toJson();
    } catch (e) {
      throw passkeyFailureFor(e);
    }
  }
}
