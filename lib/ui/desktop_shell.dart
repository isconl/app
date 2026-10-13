import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_scope.dart';
import '../services/alerts.dart';
import '../theme.dart';
import '../util/fmt.dart' as fmt;
import 'shell.dart' show OfflineBanner, SyncIndicator;
import 'widgets/chat_rail.dart';
import 'widgets/command_palette.dart';
import 'widgets/sidebar_rail.dart';
import 'widgets/vault_sync_banner.dart';
import 'view_history.dart';

/// Desktop/wide-web chrome: sidebar | content | chat rail, matching
/// dashboard's 3-column grid (see ui/adaptive_shell.dart for when this picks
/// over the phone-shaped [Shell]). Every view rendered in the content pane
/// is one already built for [Shell]/[MenuSheet] - this is new chrome around
/// existing screens, not new screens.
class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key});

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  // BI26100157: on web a deep link (`#/inbox`) opens that view; anything else starts at the hub.
  static String _startView() {
    if (!kIsWeb) return 'hub';
    final id = viewFromFragment(Uri.base.fragment);
    return id != null && tryNavItem(id) != null ? id : 'hub';
  }

  late String _selected = _startView();
  late Widget _current = findNavItem(_selected).builder();
  late final ViewHistory _history = ViewHistory(_selected);
  // Ctrl/Cmd+. hides the sidebar and the chat rail, as the console's focus mode does.
  bool _focusMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final services = AppScope.of(context);
      services.sync.onNewAlerts =
          (fresh) => AlertService.instance.showAgentAlerts(fresh);
      services.sync.start();
      services.sync.fullSync(wake: true).then((_) async {
        await services.modules.check();
        await services.modules.prefetchAll();
        // M-Pesa SMS ingestion is mobile-only; sms.run() is already a safe
        // no-op on web (see services/sms_ingest.dart) but skip it outright
        // here so the boot sequence documents the platform boundary too.
        if (!kIsWeb) await services.sms.run();
      });
    });
  }

  void _show(NavItem item) {
    setState(() {
      _selected = item.id;
      _current = item.builder();
    });
    // On web the address bar follows the view, so it can be bookmarked or shared as `#/<view>`.
    if (kIsWeb) {
      SystemNavigator.routeInformationUpdated(uri: Uri(path: Uri.base.path, fragment: '/${item.id}'));
    }
  }

  void _select(NavItem item) {
    if (_history.open(item.id)) _show(item);
  }

  void _step(String? id) {
    final item = id == null ? null : tryNavItem(id);
    if (item != null) _show(item);
  }

  void _back() => _step(_history.back());
  void _forward() => _step(_history.forward());

  /// Escape steps back only when nothing is open over the shell (a dialog or the palette handles its own
  /// Escape first, because it holds the focus) and the focus is not in a text field.
  void _escape() {
    final focus = FocusManager.instance.primaryFocus?.context?.widget;
    if (focus is EditableText) return;
    _back();
  }

  void _toggleFocusMode() => setState(() => _focusMode = !_focusMode);

  void _openPalette() => showCommandPalette(context, _select);

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _openPalette,
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
            _openPalette,
        // BI26100157: the console's other keys (hub app.js): Alt+Left/Right back and forward, Escape
        // steps back with nothing open, Ctrl/Cmd+. toggles focus mode.
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): _back,
        const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): _forward,
        const SingleActivator(LogicalKeyboardKey.escape): _escape,
        const SingleActivator(LogicalKeyboardKey.period, control: true): _toggleFocusMode,
        const SingleActivator(LogicalKeyboardKey.period, meta: true): _toggleFocusMode,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_focusMode)
                SidebarRail(
                  selected: _selected,
                  onSelect: _select,
                  onCommandPalette: _openPalette,
                ),
              Expanded(
                child: Column(
                  children: [
                    _DesktopHeader(title: findNavItem(_selected).label),
                    const VaultSyncBanner(),
                    // BN26091004: banner now Settings-only -- every other
                    // nav item already shows connectivity via the header's
                    // own always-present SyncIndicator.
                    if (_selected == 'settings') OfflineBanner(services: services),
                    Expanded(child: _current),
                  ],
                ),
              ),
              if (!_focusMode) const ChatRail(),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopHeader extends StatelessWidget {
  const _DesktopHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: C.panel,
        border: Border(bottom: BorderSide(color: C.border)),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: T.headline.copyWith(fontSize: 18)),
              ListenableBuilder(
                listenable: services.store.state,
                builder: (context, _) {
                  final eq = fmt.m(fmt.m(services.store.state.value)['time']);
                  final line = fmt.s(eq['eqShort']);
                  return line.isEmpty
                      ? const SizedBox.shrink()
                      : Text(line, style: T.monoSmall);
                },
              ),
            ],
          ),
          const Spacer(),
          const SyncIndicator(),
        ],
      ),
    );
  }
}
