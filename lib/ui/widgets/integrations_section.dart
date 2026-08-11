import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import 'common.dart';

/// Full service-credential management, ported from the legacy dashboard's
/// Settings page (dashboard/app.js renderSettings()/saveSettings(), ~lines
/// 2849-3282) - one POST /api/settings per section, same field names the
/// monolith's own handler expects (server.js ~line 6133) so this works
/// against that exact endpoint with zero backend changes. Desktop-only:
/// credential entry is deliberately not offered on the mobile Settings
/// screen (a phone typing a Jira API token is a bad afternoon).
class IntegrationsSection extends StatefulWidget {
  const IntegrationsSection({super.key});

  @override
  State<IntegrationsSection> createState() => _IntegrationsSectionState();
}

class _IntegrationsSectionState extends State<IntegrationsSection> {
  Future<void> _save(Map<String, dynamic> updates,
      {String label = 'Saved'}) async {
    final services = AppScope.of(context);
    final clean = {
      for (final e in updates.entries)
        if (e.value != null && e.value.toString().trim().isNotEmpty) e.key: e.value,
    };
    if (clean.isEmpty) return;
    try {
      await services.api.postJson('/api/settings', clean);
      if (!mounted) return;
      toast(context, label);
      services.store.state.refresh();
    } catch (e) {
      if (mounted) toast(context, 'Save failed: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return ListenableBuilder(
      listenable: services.store.state,
      builder: (context, _) {
        final state = fmt.m(services.store.state.value);
        final svc = fmt.m(state['services']);
        final jiraConfig = fmt.m(svc['jiraConfig']);
        final groqConfig = fmt.m(svc['groqConfig']);
        final msConfig = fmt.m(svc['msConfig']);
        final bufferConfig = fmt.m(svc['bufferConfig']);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionLabel('Integrations'),
            _ServiceCard(
              title: 'Jira Cloud',
              connected: fmt.b(jiraConfig['hasToken']) && fmt.s(jiraConfig['host']).isNotEmpty,
              hint: 'Board access for the Kanban view and task push.',
              onSave: () => _editJira(context, jiraConfig),
            ),
            _ServiceCard(
              title: 'Microsoft 365 / OneDrive / Outlook',
              connected: fmt.b(msConfig['hasCreds']),
              hint: 'Powers file sync, inbox mail import, and calendar events.',
              onSave: () => _editM365(context, msConfig),
              extraLabel: 'Start device login',
              onExtra: () => _startM365Login(context),
            ),
            _ServiceCard(
              title: 'Buffer · Social Media Scheduler',
              connected: fmt.b(bufferConfig['hasToken']),
              hint: 'Get an Access Token from buffer.com -> Settings -> Developer.',
              onSave: () => _editSingle(context, 'Buffer Access Token', 'bufferToken',
                  hint: bufferConfig['hasToken'] == true
                      ? 'Saved - enter to replace'
                      : 'Paste from buffer.com',
                  obscure: true),
            ),
            _ServiceCard(
              title: 'Anthropic Claude AI (Primary)',
              connected: fmt.s(svc['anthropic']) == 'connected',
              hint: 'Primary sovereign reasoning engine.',
              onSave: () => _editAnthropic(context, svc),
            ),
            _ServiceCard(
              title: 'Telegram Bot',
              connected: fmt.s(svc['telegram']) == 'connected',
              hint: 'Create a bot via @BotFather, paste its token and your chat ID.',
              onSave: () => _editTelegram(context, svc),
            ),
            _ServiceCard(
              title: 'Signal Messenger',
              connected: fmt.s(svc['signal']) == 'connected',
              hint: 'Registered phone number for the Signal CLI bridge.',
              onSave: () => _editSingle(
                  context, 'Signal Phone Number', 'signalNumber',
                  hint: '+1234567890'),
            ),
            _ServiceCard(
              title: 'Groq AI Engine (Fallback)',
              connected: fmt.b(groqConfig['hasKey']),
              hint: 'Optional fallback engine.',
              onSave: () => _editGroq(context, groqConfig),
            ),
            const SizedBox(height: 4),
            const SectionLabel('Service status'),
            Panel(
              child: Column(
                children: [
                  for (final row in _statusRows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          StatusDot(
                              fmt.s(svc[row.$2]) == 'connected'
                                  ? C.green
                                  : C.text3,
                              glow: fmt.s(svc[row.$2]) == 'connected'),
                          const SizedBox(width: 10),
                          Expanded(
                              child: Text(row.$1, style: T.small)),
                          Text(
                              fmt.s(svc[row.$2]) == 'connected'
                                  ? 'Connected'
                                  : 'Disconnected',
                              style: T.monoSmall.copyWith(
                                  color: fmt.s(svc[row.$2]) == 'connected'
                                      ? C.green
                                      : C.text3)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  static const _statusRows = [
    ('Anthropic Claude', 'anthropic'),
    ('Groq AI Engine', 'groq'),
    ('ElevenLabs Voice', 'elevenlabs'),
    ('GitHub CLI', 'github'),
    ('Jira Cloud', 'jira'),
    ('WhatsApp', 'whatsapp'),
    ('Microsoft 365 / OneDrive', 'msgraph'),
    ('Buffer Social', 'buffer'),
  ];

  Future<void> _editSingle(BuildContext context, String label, String key,
      {String? hint, bool obscure = false}) async {
    final controller = TextEditingController();
    final ok = await showFormSheet<bool>(
      context,
      title: label,
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Field(label: label, controller: controller, hint: hint, obscure: obscure),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (ok == true) await _save({key: controller.text.trim()}, label: '$label saved');
  }

  Future<void> _editJira(BuildContext context, Map<String, dynamic> cfg) async {
    final host = TextEditingController(text: fmt.s(cfg['host']));
    final project = TextEditingController(text: fmt.s(cfg['projectKey']));
    final email = TextEditingController(text: fmt.s(cfg['email']));
    final token = TextEditingController();
    final ok = await showFormSheet<bool>(
      context,
      title: 'Jira Cloud',
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Field(label: 'Host Domain', controller: host, hint: 'yourorg.atlassian.net'),
          Field(label: 'Project Key', controller: project, hint: 'WSRU'),
          Field(label: 'Email', controller: email, hint: 'your@email.com'),
          Field(
              label: 'API Token',
              controller: token,
              obscure: true,
              hint: fmt.b(cfg['hasToken'])
                  ? 'Saved - enter to replace'
                  : 'Paste from id.atlassian.com'),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save Jira Config')),
        ],
      ),
    );
    if (ok == true) {
      await _save({
        'jiraHost': host.text.trim(),
        'jiraProject': project.text.trim(),
        'jiraEmail': email.text.trim(),
        'jiraToken': token.text.trim(),
      }, label: 'Jira config saved');
    }
  }

  Future<void> _editM365(BuildContext context, Map<String, dynamic> cfg) async {
    final token = TextEditingController();
    final tenant = TextEditingController(text: fmt.s(cfg['tenantId']));
    final ok = await showFormSheet<bool>(
      context,
      title: 'Microsoft 365 (manual override)',
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Field(
              label: 'Access Token',
              controller: token,
              obscure: true,
              hint: fmt.b(cfg['hasCreds'])
                  ? 'Saved - enter to replace'
                  : 'Or paste access token directly'),
          Field(
              label: 'Tenant ID',
              controller: tenant,
              hint: 'Your Azure tenant ID (optional)'),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save Manual Config')),
        ],
      ),
    );
    if (ok == true) {
      await _save({
        'msAccessToken': token.text.trim(),
        'msTenantId': tenant.text.trim(),
      }, label: 'Microsoft 365 config saved');
    }
  }

  Future<void> _editAnthropic(
      BuildContext context, Map<String, dynamic> svc) async {
    final key = TextEditingController();
    var model = fmt.s(fmt.m(svc['anthropicConfig'])['model']);
    if (!_anthropicModels.contains(model)) model = _anthropicModels.first;
    final ok = await showFormSheet<Map<String, String>>(
      context,
      title: 'Anthropic Claude',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Field(
                label: 'Anthropic API Key',
                controller: key,
                obscure: true,
                hint: svc['anthropic'] == 'connected'
                    ? 'Saved - enter to replace'
                    : 'sk-ant-api...'),
            Segmented(
              label: 'Model',
              options: _anthropicModels,
              value: model,
              onChanged: (v) => setState(() => model = v),
            ),
            FilledButton(
                onPressed: () =>
                    Navigator.pop(ctx, {'key': key.text.trim(), 'model': model}),
                child: const Text('Save Claude Config')),
          ],
        ),
      ),
    );
    if (ok != null) {
      await _save({'anthropicKey': ok['key'], 'anthropicModel': ok['model']},
          label: 'Claude config saved');
    }
  }

  static const _anthropicModels = [
    'claude-3-5-sonnet-20241022',
    'claude-3-5-haiku-20241022',
  ];

  Future<void> _editTelegram(
      BuildContext context, Map<String, dynamic> svc) async {
    final token = TextEditingController();
    final chat = TextEditingController();
    final ok = await showFormSheet<bool>(
      context,
      title: 'Telegram Bot',
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Field(
              label: 'Telegram Bot Token',
              controller: token,
              obscure: true,
              hint: svc['telegram'] == 'connected'
                  ? 'Saved - enter to replace'
                  : '123456789:ABCdef...'),
          Field(
              label: 'Chat ID', controller: chat, hint: 'Your Telegram Chat ID'),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save Telegram Config')),
        ],
      ),
    );
    if (ok == true) {
      await _save({
        'telegramToken': token.text.trim(),
        'telegramChatId': chat.text.trim(),
      }, label: 'Telegram config saved');
    }
  }

  Future<void> _editGroq(BuildContext context, Map<String, dynamic> cfg) async {
    final key = TextEditingController();
    var model = fmt.s(cfg['model']);
    if (!_groqModels.contains(model)) model = _groqModels.first;
    final ok = await showFormSheet<Map<String, String>>(
      context,
      title: 'Groq (fallback)',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Field(
                label: 'Groq API Key',
                controller: key,
                obscure: true,
                hint: fmt.b(cfg['hasKey'])
                    ? 'Saved - enter to replace'
                    : 'Get free key at console.groq.com'),
            Segmented(
              label: 'Model',
              options: _groqModels,
              value: model,
              onChanged: (v) => setState(() => model = v),
            ),
            FilledButton(
                onPressed: () =>
                    Navigator.pop(ctx, {'key': key.text.trim(), 'model': model}),
                child: const Text('Save Groq Config')),
          ],
        ),
      ),
    );
    if (ok != null) {
      await _save({'groqKey': ok['key'], 'groqModel': ok['model']},
          label: 'Groq config saved');
    }
  }

  static const _groqModels = [
    'llama-3.1-70b-versatile',
    'llama-3.1-8b-instant',
    'mixtral-8x7b-32768',
  ];

  /// Device-code flow, same shape as dashboard/app.js's startM365DeviceLogin:
  /// POST /api/m365/auth/start for the user code, then poll
  /// /api/m365/auth/poll every 5s until success or a non-pending error.
  Future<void> _startM365Login(BuildContext context) async {
    final services = AppScope.of(context);
    dynamic data;
    try {
      data = fmt.m(await services.api.postJson('/api/m365/auth/start', {}));
    } catch (e) {
      if (context.mounted) {
        toast(context, 'Could not start Microsoft login: $e', error: true);
      }
      return;
    }
    final userCode = fmt.s(data['user_code']);
    final deviceCode = fmt.s(data['device_code']);
    final verifyUri = fmt.s(data['verification_uri']).isEmpty
        ? 'microsoft.com/devicelogin'
        : fmt.s(data['verification_uri']);
    if (userCode.isEmpty || deviceCode.isEmpty) {
      if (context.mounted) {
        toast(context,
            fmt.s(data['error_description']).isEmpty
                ? 'Microsoft did not return a device code'
                : fmt.s(data['error_description']),
            error: true);
      }
      return;
    }
    if (!context.mounted) return;

    var status = 'Waiting for you to enter the code...';
    Timer? poll;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          poll ??= Timer.periodic(const Duration(seconds: 5), (t) async {
            try {
              final pd = fmt.m(await services.api
                  .postJson('/api/m365/auth/poll', {'deviceCode': deviceCode}));
              if (pd['success'] == true) {
                t.cancel();
                setState(() => status = 'Microsoft 365 connected successfully!');
                services.store.state.refresh();
                await Future.delayed(const Duration(milliseconds: 900));
                if (ctx.mounted) Navigator.pop(ctx);
              } else if (fmt.s(pd['error']).isNotEmpty &&
                  !fmt.s(pd['error']).contains('authorization_pending')) {
                t.cancel();
                setState(() => status = fmt.s(pd['error_description']).isEmpty
                    ? fmt.s(pd['error'])
                    : fmt.s(pd['error_description']));
              }
            } catch (_) {
              // Transient network hiccup - keep polling, same as the dashboard.
            }
          });
          return AlertDialog(
            title: const Text('Microsoft 365 sign-in', style: T.title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('1. Copy this code:', style: T.small),
                const SizedBox(height: 4),
                SelectableText(userCode,
                    style: T.mono.copyWith(
                        fontSize: 18,
                        color: C.greenBright,
                        letterSpacing: 2)),
                const SizedBox(height: 10),
                Text('2. Open $verifyUri and enter it.', style: T.small),
                const SizedBox(height: 14),
                Text(status,
                    style: T.monoSmall.copyWith(color: C.amber)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  poll?.cancel();
                  Navigator.pop(ctx);
                },
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      ),
    );
    poll?.cancel();
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    required this.title,
    required this.connected,
    required this.hint,
    required this.onSave,
    this.extraLabel,
    this.onExtra,
  });

  final String title;
  final bool connected;
  final String hint;
  final VoidCallback onSave;
  final String? extraLabel;
  final VoidCallback? onExtra;

  @override
  Widget build(BuildContext context) {
    return Panel(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text(title, style: T.w600(T.body2.copyWith(color: C.text)))),
              Badge2(connected ? 'Connected' : 'Not configured',
                  color: connected ? C.greenBg : C.surface,
                  textColor: connected ? C.greenBright : C.text3),
            ],
          ),
          const SizedBox(height: 4),
          Text(hint, style: T.small.copyWith(color: C.text3)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(onPressed: onSave, child: const Text('Configure')),
              if (extraLabel != null)
                FilledButton(onPressed: onExtra, child: Text(extraLabel!)),
            ],
          ),
        ],
      ),
    );
  }
}
