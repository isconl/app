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
  String _selected = 'hub';
  late Widget _current = findNavItem('hub').builder();

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

  void _select(NavItem item) {
    setState(() {
      _selected = item.id;
      _current = item.builder();
    });
  }

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
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SidebarRail(
                selected: _selected,
                onSelect: _select,
                onCommandPalette: _openPalette,
              ),
              Expanded(
                child: Column(
                  children: [
                    _DesktopHeader(title: findNavItem(_selected).label),
                    OfflineBanner(services: services),
                    Expanded(child: _current),
                  ],
                ),
              ),
              const ChatRail(),
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
