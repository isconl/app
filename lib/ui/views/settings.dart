import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../services/branding.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../widgets/common.dart';
import '../widgets/integrations_section.dart';

/// Connection, security, sync, update-on-cue, appearance, about.
///
/// [showIntegrations] adds the full service-credential management section
/// (Jira/M365/Buffer/Anthropic/Telegram/Signal/Groq + status grid) ported
/// from the legacy dashboard's Settings page - desktop-only, same reasoning
/// as Buffer's compose gate: a phone typing a Jira API token is a bad
/// afternoon. DesktopShell passes true; the mobile Shell's default is false.
class SettingsView extends StatefulWidget {
  const SettingsView({super.key, this.showIntegrations = false});
  final bool showIntegrations;

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final services = AppScope.of(context);
      if (services.sync.online) services.session.probeHealth();
    });
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 96),
      child: ListenableBuilder(
        listenable: Listenable.merge(
            [services.session, services.sync, services.updater]),
        builder: (context, _) {
          final session = services.session;
          final sync = services.sync;
          final updater = services.updater;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ---- automatic context ----
              const SectionLabel('Automatic context'),
              const SmsCard(),

              // ---- connection ----
              const SectionLabel('Connection'),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    KvRow('Server',
                        session.serverUrl
                            .replaceFirst(RegExp(r'^https?://'), ''),
                        mono: true),
                    KvRow(
                        'Status',
                        sync.online
                            ? 'online'
                            : 'offline - local mirror active',
                        vColor: sync.online ? C.green : C.amber),
                    if (session.serverHealth != null)
                      KvRow(
                          'Agent',
                          'v${fmt.s(session.serverHealth!['version'])} · ${fmt.s(session.serverHealth!['build'])}',
                          mono: true),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: () => _serverSheet(context),
                          child: const Text('Change server'),
                        ),
                        OutlinedButton(
                          onPressed: () async {
                            final sure = await confirmDialog(
                                context,
                                'Sign out?',
                                'The session token is discarded. Cached '
                                    'data stays on this device.',
                                action: 'Sign out');
                            if (sure) await session.logout();
                          },
                          child: const Text('Sign out'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (widget.showIntegrations) ...[
                const IntegrationsSection(),
              ],

              // ---- security ----
              const SectionLabel('Security'),
              Panel(
                child: Row(
                  children: [
                    const Icon(Icons.fingerprint_rounded,
                        size: 20, color: C.text2),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Biometric lock', style: T.body2),
                          // Says what is true rather than what the switch does.
                          // It arms itself after the first code, so the useful
                          // information is that turning it OFF is the decision.
                          Text(
                            session.biometricLock
                                ? 'On. You stay signed in - a fingerprint is all it asks for.'
                                : 'Off. The app opens without asking anything.',
                            style: T.tiny),
                        ],
                      ),
                    ),
                    Switch(
                      value: session.biometricLock,
                      onChanged: (v) => session.setBiometricLock(v),
                    ),
                  ],
                ),
              ),
              // ---- sync ----
              const SectionLabel('Sync'),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    KvRow('State', sync.statusLine),
                    ListenableBuilder(
                      listenable: services.outbox,
                      builder: (context, _) => KvRow(
                          'Queued',
                          services.outbox.pending == 0
                              ? 'nothing waiting'
                              : fmt.plural(
                                  services.outbox.pending, 'change')),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: sync.online
                              ? () => sync.fullSync()
                              : null,
                          icon: const Icon(Icons.sync_rounded, size: 16),
                          label: const Text('Sync now'),
                        ),
                        OutlinedButton.icon(
                          onPressed: sync.online
                              ? () async {
                                  try {
                                    await services.mutations
                                        .post('/api/vault/sync', {});
                                    if (context.mounted) {
                                      toast(context,
                                          'Vault -> OneDrive sync started');
                                    }
                                  } catch (_) {
                                    if (context.mounted) {
                                      toast(context, 'Could not start',
                                          error: true);
                                    }
                                  }
                                }
                              : null,
                          icon: const Icon(Icons.cloud_upload_rounded,
                              size: 16),
                          label: const Text('Push to OneDrive'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // ---- update on cue ----
              const SectionLabel('App update'),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    KvRow('Installed', 'v${updater.installedVersion}',
                        mono: true),
                    if (updater.latestVersion != null)
                      KvRow('Latest', 'v${updater.latestVersion}',
                          mono: true),
                    if (updater.state != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(updater.state!,
                            style: T.small.copyWith(color: C.text3)),
                      ),
                    if (updater.busy && updater.progress > 0) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                            value: updater.progress, minHeight: 5),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: updater.busy || !sync.online
                              ? null
                              : () async {
                                  final newer = await updater.check();
                                  if (newer != null && context.mounted) {
                                    final size = fmt.s(
                                        updater.available?['sizeLabel']);
                                    final go = await confirmDialog(
                                        context,
                                        'Update to v$newer?',
                                        'The agent hands over the signed build'
                                            '${size.isEmpty ? '' : ' ($size)'} '
                                            'and Android installs it over this '
                                            'version. Your data stays.',
                                        action: 'Update');
                                    if (go) await updater.downloadAndInstall();
                                  }
                                },
                          icon: updater.busy
                              ? const MiniSpinner()
                              : const Icon(Icons.system_update_rounded,
                                  size: 16),
                          label: const Text('Check for update'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Updates come from your own agent, not an app store and '
                      'not GitHub directly - so this phone holds no second '
                      'credential. Every build is signed with the same key, '
                      'which is what lets it install over the last one.',
                      style: T.tiny,
                    ),
                  ],
                ),
              ),
              // ---- appearance ----
              const SectionLabel('Appearance'),
              Panel(
                child: ListenableBuilder(
                  listenable: BrandingService.instance,
                  builder: (context, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'In-app logo. The launcher icon itself is baked per '
                        'build: drop branding/icon.png in the repo and the '
                        'next build adopts it.',
                        style: T.small.copyWith(color: C.text3),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () async {
                              final ok = await BrandingService.instance
                                  .pickAndSet();
                              if (context.mounted) {
                                toast(
                                    context,
                                    ok
                                        ? 'Logo updated'
                                        : 'No image chosen (max 2 MB)');
                              }
                            },
                            icon: const Icon(Icons.image_rounded, size: 16),
                            label: const Text('Choose logo'),
                          ),
                          if (BrandingService.instance.logoBytes != null)
                            OutlinedButton(
                              onPressed: () =>
                                  BrandingService.instance.reset(),
                              child: const Text('Reset to default'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              // ---- data ----
              const SectionLabel('Local data'),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'The local mirror is cache - the vault on the server '
                      'remains the single source of truth.',
                      style: T.small.copyWith(color: C.text3),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final sure = await confirmDialog(
                            context,
                            'Clear local mirror?',
                            'Cached snapshots are wiped and re-pulled on '
                                'the next sync. Queued changes are kept.',
                            action: 'Clear');
                        if (!sure) return;
                        await services.store.clearAll();
                        if (context.mounted) {
                          toast(context, 'Local mirror cleared');
                        }
                        if (sync.online) sync.fullSync();
                      },
                      icon: const Icon(Icons.cleaning_services_rounded,
                          size: 16),
                      label: const Text('Clear cached snapshots'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Center(
                child: Text(
                  'iSconl · native client v${updater.installedVersion}\n'
                  'offline-first · vault-backed · gate-armed',
                  textAlign: TextAlign.center,
                  style: T.monoSmall,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _serverSheet(BuildContext context) {
    final services = AppScope.of(context);
    final controller =
        TextEditingController(text: services.session.serverUrl);
    return showFormSheet(
      context,
      title: 'Server URL',
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Field(
              label: 'URL',
              controller: controller,
              hint: 'http://192.168.1.10:8888',
              keyboardType: TextInputType.url),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await services.session.setServer(controller.text);
              if (context.mounted) {
                toast(context, 'Server updated - sign in again if needed');
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

}

/// M-Pesa context from SMS.
///
/// Every number here is reported rather than implied, because "is this working"
/// deserves an answer that is not a feeling. The copy is explicit about scope:
/// only M-Pesa messages are ever read, his conversations are untouched, and the
/// app holds no permission to send an SMS at all.
class SmsCard extends StatefulWidget {
  const SmsCard({super.key});

  @override
  State<SmsCard> createState() => _SmsCardState();
}

class _SmsCardState extends State<SmsCard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppScope.of(context).sms.refreshPermission();
    });
  }

  @override
  Widget build(BuildContext context) {
    final sms = AppScope.of(context).sms;
    return ListenableBuilder(
      listenable: sms,
      builder: (context, _) => Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(sms.granted ? Icons.sms_rounded : Icons.sms_failed_rounded,
                    size: 17, color: sms.granted ? C.green : C.text3),
                const SizedBox(width: 10),
                Expanded(child: Text('M-Pesa from SMS', style: T.w600(T.body2))),
                if (sms.busy) const MiniSpinner(),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              sms.granted
                  ? 'Reading M-Pesa messages only. Every movement becomes a '
                    'transaction, and money moving to or from someone in your '
                    'circle also becomes a touchpoint.'
                  : 'Grant permission and every M-Pesa message becomes a ledger '
                    'entry automatically. Only messages from M-PESA are read - '
                    'your conversations are never touched, and the app cannot '
                    'send an SMS at all.',
              style: T.small.copyWith(color: C.text3, height: 1.5),
            ),
            if (sms.granted) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  _Stat('imported', '${sms.imported}'),
                  _Stat('duplicates skipped', '${sms.skippedDuplicate}'),
                  _Stat('not recognised', '${sms.unparsedCount}'),
                ],
              ),
              if (sms.lastRun != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('last read ${fmt.ago(sms.lastRun!.toIso8601String())}',
                      style: T.monoSmall),
                ),
            ],
            if (sms.lastError != null) ...[
              const SizedBox(height: 10),
              Text(sms.lastError!, style: T.tiny.copyWith(color: C.amber, height: 1.5)),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                if (!sms.granted)
                  FilledButton.icon(
                    onPressed: () async {
                      final ok = await sms.request();
                      if (!context.mounted) return;
                      if (ok) {
                        final n = await sms.run();
                        if (!context.mounted) return;
                        toast(context, n > 0
                            ? '$n movement${n == 1 ? '' : 's'} imported'
                            : 'Nothing new to import');
                      }
                    },
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: const Text('Allow and import'),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: sms.busy ? null : () async {
                      final n = await sms.run();
                      if (!context.mounted) return;
                      toast(context, n > 0
                          ? '$n movement${n == 1 ? '' : 's'} imported'
                          : 'Nothing new to import');
                    },
                    icon: const Icon(Icons.refresh_rounded, size: 15),
                    label: const Text('Import now'),
                  ),
                const Spacer(),
                if (sms.granted)
                  TextButton(
                    // Safe by construction: the agent deduplicates on the M-Pesa
                    // code, so a re-read reconciles rather than duplicates.
                    onPressed: sms.busy ? null : () async {
                      await sms.resetMark();
                      if (!context.mounted) return;
                      toast(context, 'Will re-read the last 90 days on the next import');
                    },
                    child: const Text('Re-read 90 days'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: T.mono.copyWith(color: C.text, fontSize: 15)),
          Text(label, style: T.tiny.copyWith(fontSize: 9.5)),
        ],
      ),
    );
  }
}
