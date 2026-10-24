import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../widgets/common.dart';
import '../widgets/dashboard/dashboard.dart';
import '../shell.dart' show SecondaryScreen;
import 'slate.dart';
import 'systems_dash_model.dart';

/// BI26100131: the Systems landing as a dashboard. Engines marked down show
/// red and open Ops; the slate split opens the Slate view's Register tab. Figures with no source
/// yet (backup age, storage, closed today) say so instead of guessing.
class SystemsDashboard extends StatelessWidget {
  const SystemsDashboard({
    super.key,
    required this.dash,
    required this.outboxPending,
    required this.installedVersion,
    required this.updateState,
    required this.updateBusy,
    this.onOpenSub,
    this.onOpenSlate,
    this.latestVersion,
    this.updateAvailable = false,
  });
  final SystemsDash dash;
  final int outboxPending;
  final String installedVersion;

  /// The updater's own sentence, including its precise reason when no build is offered.
  final String? updateState;
  final bool updateBusy;
  final void Function(int sub)? onOpenSub;

  /// Opens the Slate view's Register tab; the default pushes it as a secondary screen.
  final VoidCallback? onOpenSlate;
  /// The newest build the agent offers, once the quiet check has run.
  final String? latestVersion;
  final bool updateAvailable;

  static const _typeColors = {
    'plan': C.violet,
    'build': C.green,
    'work': C.cyan,
    'light': C.amber,
    'content': C.callQuote,
    'hands': C.red,
  };

  @override
  Widget build(BuildContext context) {
    final syncTone = ageTone(dash.syncAge);
    return DashboardGrid(items: [
      DashItem(
        DashTile(
          label: 'Fleet health',
          onTap: onOpenSub == null ? null : () => onOpenSub!(2),
          child: dash.engines.isEmpty
              ? const DashEmpty(text: 'No engine status yet')
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${dash.healthy} of ${dash.engines.length} healthy',
                      style: T.title.copyWith(color: dash.healthy == dash.engines.length ? C.green : C.red, fontFeatures: kTabular)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 10, runSpacing: 4, children: [
                    for (final e in dash.engines)
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        StatusDot(e.up ? C.green : C.red, size: 8),
                        const SizedBox(width: 4),
                        Text(e.name, style: T.tiny.copyWith(color: e.up ? C.text3 : C.red)),
                      ]),
                  ]),
                ]),
        ),
        span: 2,
      ),
      DashItem(DashTile(
        label: 'Last sync',
        child: dash.syncAge == null
            ? const DashEmpty()
            : Text('${ageText(dash.syncAge!)} ago', style: T.title.copyWith(color: syncTone, fontFeatures: kTabular)),
      )),
      DashItem(StatTile(label: 'Outbox pending', value: '$outboxPending', delta: null)),
      const DashItem(StatTile(label: 'Vault backup', value: null)),
      const DashItem(StatTile(label: 'Storage', value: null)),
      DashItem(
        DashTile(
          label: 'Slate rows, live',
          onTap: onOpenSlate ?? () {
            SlateView.remembered = SlateTab.grid;
            Navigator.push(
              context,
              MaterialPageRoute<void>(
                  builder: (_) => const SecondaryScreen(title: 'Slate', child: SlateView())),
            );
          },
          child: BarStrip(segments: [
            for (final t in SystemsDash.types) BarSegment(t, (dash.byType[t] ?? 0).toDouble(), _typeColors[t]!),
          ]),
        ),
        span: 2,
      ),
      DashItem(
        DashTile(
          label: 'App',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(installedVersion.isEmpty ? 'version unknown' : 'v$installedVersion', style: T.title.copyWith(fontFeatures: kTabular)),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                updateBusy && latestVersion == null
                    ? 'Checking for a newer build...'
                    : latestVersion == null
                        ? (updateState ?? '')
                        : updateAvailable
                            ? 'v$latestVersion available: install it from Settings › Check for update'
                            : 'Up to date',
                style: updateAvailable ? T.tiny.copyWith(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600) : T.tiny,
              ),
            ),
          ]),
        ),
        span: 2,
      ),
    ]);
  }
}

/// Reads the ops status and backlog snapshots (hydrating them on first show)
/// and builds the dashboard from them, so SettingsView only adds one widget.
class SystemsDashboardHost extends StatefulWidget {
  const SystemsDashboardHost({super.key, this.onOpenSub});
  final void Function(int sub)? onOpenSub;

  @override
  State<SystemsDashboardHost> createState() => _SystemsDashboardHostState();
}

class _SystemsDashboardHostState extends State<SystemsDashboardHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // The App tile is state-aware on its own: a quiet look for a newer build,
      // shown as text. Installing stays in Settings (runUpdateFlow).
      AppScope.of(context).updater.refreshAvailability();
      final store = AppScope.of(context).store;
      for (final s in [store.opsStatus, store.backlog]) {
        s.hydrate().then((_) {
          if (mounted) s.refresh();
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final store = services.store;
    return ListenableBuilder(
      listenable: Listenable.merge([store.opsStatus, store.backlog, services.outbox, services.updater]),
      builder: (context, _) {
        final dash = SystemsDash.from(
          opsStatus: fmt.m(store.opsStatus.value),
          backlog: fmt.m(store.backlog.value),
          fetchTimes: [for (final s in store.snapshots) s.fetchedAt],
          now: DateTime.now(),
        );
        final u = services.updater;
        return SystemsDashboard(
          dash: dash,
          outboxPending: services.outbox.pending,
          installedVersion: u.installedVersion,
          updateState: u.state,
          updateBusy: u.busy,
          onOpenSub: widget.onOpenSub,
          latestVersion: u.latestVersion,
          updateAvailable: u.updateAvailable,
        );
      },
    );
  }
}
