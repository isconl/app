import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_scope.dart';
import '../main.dart' show BrandMark;
import 'widgets/brand.dart' show BrandMotion;
import '../theme.dart';
import 'widgets/common.dart';

/// Token gate, mirroring the web overlay: probes /api/auth/methods,
/// prefers TOTP (6 digits, auto-submit, rotation countdown), falls back to
/// the static token. Also owns the "waking the server" first-contact UX.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.onAuthenticated});
  final VoidCallback? onAuthenticated;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _totp = TextEditingController();
  final _token = TextEditingController();
  final _pin = TextEditingController();
  final _server = TextEditingController();

  bool _probing = true;
  bool _waking = false;
  bool _submitting = false;
  bool? _totpAvailable;
  bool _useToken = false;
  bool _usePin = false;
  bool _editServer = false;
  String? _error;
  Timer? _tick;
  int _secondsLeft = 30;

  // The PIN door is hidden behind three taps on the wordmark, exactly as it is
  // on the web (/?pin, or tapping the wordmark three times). It is the weaker
  // credential, so it should take knowing about it to find.
  int _brandTaps = 0;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final left = 30 - (now % 30);
      if (left != _secondsLeft && mounted) {
        setState(() => _secondsLeft = left);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _probe());
  }

  @override
  void dispose() {
    _tick?.cancel();
    _totp.dispose();
    _token.dispose();
    _pin.dispose();
    _server.dispose();
    super.dispose();
  }

  Future<void> _probe() async {
    final services = AppScope.of(context);
    _server.text = services.session.serverUrl;
    setState(() {
      _probing = true;
      _waking = true;
      _error = null;
    });
    try {
      final methods = await services.session.authMethods();
      if (!mounted) return;
      setState(() {
        _totpAvailable = methods['totp'] == true;
        _useToken = methods['totp'] != true;
        _waking = false;
        _probing = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _totpAvailable = null;
        _waking = false;
        _probing = false;
        _error = 'Could not reach the agent. It may be waking up - retry in '
            'a few seconds, or check the server URL.';
      });
    }
  }

  Future<void> _submitTotp(String code) async {
    if (_submitting || code.length != 6) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final services = AppScope.of(context);
    final err = await services.session.loginTotp(code);
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _error = err;
    });
    if (err == null) {
      widget.onAuthenticated?.call();
    } else {
      _totp.clear();
      HapticFeedback.heavyImpact();
    }
  }

  Future<void> _submitPin() async {
    final pin = _pin.text.trim();
    if (_submitting || pin.length < 4) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final services = AppScope.of(context);
    final err = await services.session.loginPin(pin);
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _error = err;
    });
    if (err == null) {
      widget.onAuthenticated?.call();
    } else {
      _pin.clear();
      HapticFeedback.heavyImpact();
    }
  }

  Future<void> _submitToken() async {
    final token = _token.text.trim();
    if (_submitting || token.isEmpty) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final services = AppScope.of(context);
    final err = await services.session.loginToken(token);
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _error = err;
    });
    if (err == null) {
      widget.onAuthenticated?.call();
    } else {
      HapticFeedback.heavyImpact();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // The first thing seen on a cold launch, so it draws itself:
                  // the node travels one revolution and the loop appears behind
                  // it. One gesture, 1100ms, ending where it started.
                  const Center(
                      child: BrandMark(size: 52, motion: BrandMotion.drawing)),
                  const SizedBox(height: 18),
                  Center(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _tapBrand,
                      child: Text('iSconl',
                          style: T.headline.copyWith(
                              fontSize: 24, letterSpacing: -0.8)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: Text('Enter the Architect...',
                        style: T.small.copyWith(color: C.text3)),
                  ),
                  const SizedBox(height: 30),
                  if (_probing) ...[
                    const Center(child: MiniSpinner(size: 20)),
                    const SizedBox(height: 12),
                    Center(
                      child: Text(
                        _waking
                            ? 'Reaching the agent… free tier can take up to a minute to wake.'
                            : 'Checking…',
                        style: T.small.copyWith(color: C.text3),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ] else ...[
                    if (_usePin)
                      _pinForm()
                    else if (_totpAvailable == true && !_useToken)
                      _totpForm()
                    else
                      _tokenForm(),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!,
                          style: T.small.copyWith(color: C.red),
                          textAlign: TextAlign.center),
                      if (_totpAvailable == null)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: OutlinedButton(
                              onPressed: _probe, child: const Text('Retry')),
                        ),
                    ],
                    const SizedBox(height: 20),
                    if (_usePin)
                      Center(
                        child: TextButton(
                          onPressed: () => setState(() {
                            _usePin = false;
                            _error = null;
                          }),
                          child: Text(
                            _totpAvailable == true
                                ? 'Use authenticator code instead'
                                : 'Use access token instead',
                            style: T.small.copyWith(color: C.text3),
                          ),
                        ),
                      )
                    else if (_totpAvailable == true)
                      Center(
                        child: TextButton(
                          onPressed: () =>
                              setState(() => _useToken = !_useToken),
                          child: Text(
                            _useToken
                                ? 'Use authenticator code instead'
                                : 'Use static token instead',
                            style: T.small.copyWith(color: C.text3),
                          ),
                        ),
                      ),
                  ],
                  const SizedBox(height: 8),
                  _serverRow(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _totpForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('AUTHENTICATOR CODE', style: T.label),
        const SizedBox(height: 8),
        TextField(
          controller: _totp,
          autofocus: true,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 6,
          style: const TextStyle(
            fontFamily: 'JetBrains Mono',
            fontSize: 26,
            letterSpacing: 10,
            color: C.text,
          ),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(counterText: '', hintText: '······'),
          onChanged: (v) {
            if (v.length == 6) _submitTotp(v);
          },
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_submitting)
              const MiniSpinner()
            else ...[
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  value: _secondsLeft / 30,
                  strokeWidth: 2,
                  color: _secondsLeft <= 5 ? C.amber : C.green,
                  backgroundColor: C.surface,
                ),
              ),
              const SizedBox(width: 8),
              Text('code rotates in ${_secondsLeft}s',
                  style: T.monoSmall),
            ],
          ],
        ),
        const SizedBox(height: 14),
        // The promise, made where he is being asked to do the work. Typing a
        // rotating code is a small cost he will pay happily once and resent
        // every morning, so the screen should say which one this is.
        Text(
          'Once only. After this the session stays signed in and your '
          'fingerprint is all it asks for.',
          textAlign: TextAlign.center,
          style: T.tiny.copyWith(color: C.text3, height: 1.5),
        ),
      ],
    );
  }

  /// Three taps on the wordmark opens the PIN door. Reachable the same way
  /// the token form already is even when the server probe never succeeded
  /// (no server set yet, agent asleep, offline) - submitting still fails
  /// cleanly with the usual "No connection" message in that case, same as
  /// the token form does, rather than the gesture silently doing nothing.
  void _tapBrand() {
    if (_usePin) return;
    _brandTaps++;
    if (_brandTaps < 3) return;
    _brandTaps = 0;
    HapticFeedback.mediumImpact();
    setState(() {
      _usePin = true;
      _error = null;
    });
  }

  Widget _pinForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('QUICK PIN', style: T.label),
        const SizedBox(height: 8),
        TextField(
          controller: _pin,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 12,
          style: const TextStyle(
            fontFamily: 'JetBrains Mono',
            fontSize: 26,
            letterSpacing: 10,
            color: C.text,
          ),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(counterText: '', hintText: '····'),
          onSubmitted: (_) => _submitPin(),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _submitting ? null : _submitPin,
          child: _submitting
              ? const SizedBox(width: 16, height: 16, child: MiniSpinner())
              : const Text('Unlock'),
        ),
        const SizedBox(height: 10),
        Text(
          'A weaker proof, so it buys a shorter day. Your authenticator code '
          'is unaffected by PIN lockouts.',
          style: T.tiny,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _tokenForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('ACCESS TOKEN', style: T.label),
        const SizedBox(height: 8),
        TextField(
          controller: _token,
          autofocus: true,
          obscureText: true,
          style: T.mono.copyWith(color: C.text, fontSize: 13),
          decoration: const InputDecoration(hintText: 'paste token'),
          onSubmitted: (_) => _submitToken(),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _submitting ? null : _submitToken,
          child: _submitting
              ? const SizedBox(
                  width: 16, height: 16, child: MiniSpinner())
              : const Text('Unlock'),
        ),
      ],
    );
  }

  Widget _serverRow() {
    final services = AppScope.of(context);
    if (!_editServer) {
      return Center(
        child: TextButton(
          onPressed: () => setState(() => _editServer = true),
          child: Text(
            services.session.serverUrl
                .replaceFirst(RegExp(r'^https?://'), ''),
            style: T.monoSmall.copyWith(color: C.text3),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Field(
          label: 'Server URL',
          controller: _server,
          // The hint teaches. It used to read the Render address, which is a
          // layout instance holding demo data - so it taught the wrong thing.
          hint: 'http://192.168.1.10:8888',
          keyboardType: TextInputType.url,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => setState(() => _editServer = false),
              child: Text('Cancel', style: T.small.copyWith(color: C.text3)),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () async {
                await services.session.setServer(_server.text);
                if (!mounted) return;
                setState(() => _editServer = false);
                _probe();
              },
              child: const Text('Save & retry'),
            ),
          ],
        ),
      ],
    );
  }
}
