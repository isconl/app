import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:sqflite/sqflite.dart' show databaseFactory;
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import 'app_scope.dart';
import 'services/alerts.dart';
import 'services/branding.dart';
import 'services/platform.dart';
import 'theme.dart';
import 'ui/widgets/brand.dart' as brand;
import 'ui/widgets/brand.dart' show BrandMotion;
import 'ui/adaptive_shell.dart';
import 'ui/login.dart';
import 'ui/widgets/common.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // sqflite has no native web implementation; ffi-web backs the same Database
  // API with an IndexedDB-stored sqlite3 (wasm), so AppDb needs no rewrite -
  // see data/db.dart's kIsWeb branch for the other half of this.
  if (kIsWeb) {
    databaseFactory = databaseFactoryFfiWeb;
  }
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: C.panel,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  PlatformBridge.instance.init();
  final services = await AppServices.boot();
  await BrandingService.instance.load();
  runApp(IsconlApp(services: services));
}

class IsconlApp extends StatelessWidget {
  const IsconlApp({super.key, required this.services});
  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      services: services,
      child: MaterialApp(
        title: 'iSconl',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const RootGate(),
      ),
    );
  }
}

/// Decides what the user sees: biometric lock -> login -> shell.
class RootGate extends StatefulWidget {
  const RootGate({super.key});

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  bool _unlocked = false;
  bool _authInFlight = false;
  String? _pendingShare;

  @override
  void initState() {
    super.initState();
    AlertService.instance.init();
    PlatformBridge.instance.onSharedText = _captureShare;
    PlatformBridge.instance.getSharedText().then((text) {
      if (text != null && text.trim().isNotEmpty) _captureShare(text);
    });
  }

  Future<void> _captureShare(String text) async {
    if (!mounted) return;
    final services = AppScope.of(context);
    if (!services.session.authenticated) {
      _pendingShare = text;
      return;
    }
    final res = await services.mutations.addInbox(
      body: text.trim(),
      channel: 'mobile',
      sender: 'share-sheet',
    );
    if (!mounted) return;
    toast(
      context,
      res.queued
          ? 'Captured to inbox - queued for sync'
          : res.ok
              ? 'Captured to inbox'
              : 'Capture failed: ${res.error}',
      error: !res.ok,
    );
  }

  Future<void> _tryUnlock() async {
    if (_authInFlight) return;
    _authInFlight = true;
    try {
      final auth = LocalAuthentication();
      final can =
          await auth.canCheckBiometrics || await auth.isDeviceSupported();
      if (!can) {
        setState(() => _unlocked = true);
        return;
      }
      final ok = await auth.authenticate(
        localizedReason: 'Unlock iSconl',
        options: const AuthenticationOptions(stickyAuth: true),
      );
      if (ok && mounted) setState(() => _unlocked = true);
    } catch (_) {
      // Sensor unavailable: fail open on the user's own device rather than
      // locking him out of his own brain. The vault token stays encrypted.
      if (mounted) setState(() => _unlocked = true);
    } finally {
      _authInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return ListenableBuilder(
      listenable: services.session,
      builder: (context, _) {
        final session = services.session;
        if (!session.ready) {
          return const Scaffold(body: Center(child: MiniSpinner(size: 22)));
        }
        if (!session.authenticated) {
          _unlocked = false;
          return LoginScreen(onAuthenticated: () {
            final share = _pendingShare;
            _pendingShare = null;
            if (share != null) _captureShare(share);
          });
        }
        // biometricLock never becomes true on web (session.dart's
        // _armBiometricsIfUnchosen guards on kIsWeb) but the check is
        // repeated here so this gate doesn't depend on that invariant holding.
        if (session.biometricLock && !_unlocked && !kIsWeb) {
          return _LockScreen(onUnlock: _tryUnlock);
        }
        return const AdaptiveShell();
      },
    );
  }
}

class _LockScreen extends StatefulWidget {
  const _LockScreen({required this.onUnlock});
  final Future<void> Function() onUnlock;

  @override
  State<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<_LockScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onUnlock());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Orbiting, because this screen is an active wait rather than an
            // idle one - the agent is there, the door is not open yet.
            const BrandMark(size: 44, motion: BrandMotion.working),
            const SizedBox(height: 18),
            Text('Welcome back', style: T.title),
            const SizedBox(height: 6),
            // Not "Locked / Biometric unlock required". This is the everyday
            // door now, not an error state - the copy should read like being
            // let in, because that is what is happening. The session is still
            // signed in behind this screen; the fingerprint is the only step.
            Text('Unlock with your fingerprint', style: T.small),
            const SizedBox(height: 22),
            OutlinedButton.icon(
              onPressed: widget.onUnlock,
              icon: const Icon(Icons.fingerprint_rounded, size: 18),
              label: const Text('Unlock'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The brand mark, wrapped so a custom logo can override it.
///
/// The mark itself lives in ui/widgets/brand.dart - exact geometry, two
/// colours, and its own motion states. This wrapper exists only because
/// Settings lets ARCHITECT drop in his own image at runtime, and that image wins.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 26, this.motion = BrandMotion.rest});
  final double size;
  final BrandMotion motion;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: BrandingService.instance,
      builder: (context, _) {
        final bytes = BrandingService.instance.logoBytes;
        if (bytes != null) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(size * 0.25),
            child: Image.memory(bytes,
                width: size, height: size, fit: BoxFit.cover),
          );
        }
        return brand.BrandMark(size: size, motion: motion);
      },
    );
  }
}
