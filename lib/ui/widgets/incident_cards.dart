import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import 'common.dart';

/// BI26100909: "why is it down?" on the Ops screen, from hub's `GET /api/ops/incidents`. An open incident (no
/// `resolvedAt`) is a card at the top with the service name, the three lines as plain paragraphs, and Restart and
/// Roll back; each asks for a confirm tap, shows the result in a toast and refreshes the list. Below, the last few
/// resolved incidents: service, how long, how it recovered and the first line. Live infrastructure state is never
/// cached (the same rule as the rest of the Ops screen), and a failed load shows nothing rather than stale news.
String incidentDuration(num? ms) {
  if (ms == null || ms <= 0) return 'under 1 min';
  final s = ms ~/ 1000;
  if (s < 60) return '${s}s';
  final m = s ~/ 60;
  if (m < 60) return '$m min';
  return '${m ~/ 60} h ${m % 60} min';
}

class IncidentCards extends StatefulWidget {
  const IncidentCards({super.key});

  @override
  State<IncidentCards> createState() => _IncidentCardsState();
}

class _IncidentCardsState extends State<IncidentCards> {
  List<Map<String, dynamic>> _open = [];
  List<Map<String, dynamic>> _past = [];
  String? _busy;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  bool _resolved(Map<String, dynamic> i) => fmt.s(i['resolvedAt']).isNotEmpty && i['resolvedAt'] != 0;

  Future<void> _load() async {
    try {
      final r = await AppScope.of(context).api.getJson('/api/ops/incidents');
      if (!mounted) return;
      final all = fmt.lm(fmt.m(r)['incidents']);
      setState(() {
        _open = all.where((i) => !_resolved(i)).toList();
        _past = all.where(_resolved).take(5).toList();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _open = [];
        _past = [];
      });
    }
  }

  Future<void> _act(String service, String action, String verb) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$verb $service?', style: T.title),
        content: Text(
          action == 'rollback'
              ? 'This puts the previous image back and starts it. Roll back only if the last deploy broke it.'
              : 'This restarts the service. It is briefly down while it comes back.',
          style: T.body2,
        ),
        actions: [
          TextButton(key: const Key('incident-cancel'), onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: T.body2.copyWith(color: C.text3))),
          FilledButton(key: const Key('incident-confirm'), onPressed: () => Navigator.pop(ctx, true), child: Text(verb)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = service);
    try {
      final r = await AppScope.of(context).api.postJson('/api/ops/service/$action?service=${Uri.encodeQueryComponent(service)}', {});
      final data = fmt.m(r);
      if (!mounted) return;
      if (data['ok'] == false) {
        final why = fmt.s(data['error']).isEmpty ? 'unknown error' : fmt.s(data['error']);
        toast(context, '$verb $service failed: $why', error: true);
      } else {
        toast(context, action == 'rollback' ? '$service rolled back' : '$service restarted');
      }
    } catch (e) {
      if (mounted) toast(context, '$verb $service failed: $e', error: true);
    }
    if (!mounted) return;
    setState(() => _busy = null);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_open.isEmpty && _past.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final i in _open)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Panel(
              color: C.redBg,
              borderColor: C.red,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${fmt.s(i['service'])} is down', key: Key('incident-open-${fmt.s(i['id'])}'), style: T.body.copyWith(fontWeight: FontWeight.w600, color: C.red)),
                  const SizedBox(height: 6),
                  for (final line in (i['lines'] is List ? i['lines'] as List : const []).map((e) => fmt.s(e)).where((s) => s.isNotEmpty).take(3))
                    Padding(padding: const EdgeInsets.only(bottom: 3), child: Text(line, style: T.small)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      FilledButton(
                        key: Key('incident-restart-${fmt.s(i['id'])}'),
                        onPressed: _busy == null ? () => _act(fmt.s(i['service']), 'restart', 'Restart') : null,
                        child: const Text('Restart'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        key: Key('incident-rollback-${fmt.s(i['id'])}'),
                        onPressed: _busy == null ? () => _act(fmt.s(i['service']), 'rollback', 'Roll back') : null,
                        child: const Text('Roll back'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        if (_past.isNotEmpty) ...[
          const SectionLabel('Past incidents'),
          for (final i in _past)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${fmt.s(i['service'])} · ${incidentDuration(i['durationMs'] is num ? i['durationMs'] as num : null)}'
                    '${fmt.s(i['recovery']).isEmpty ? '' : ' · ${fmt.s(i['recovery'])}'}',
                    style: T.small.copyWith(color: C.text2),
                  ),
                  if ((i['lines'] is List) && (i['lines'] as List).isNotEmpty) Text(fmt.s((i['lines'] as List).first), style: T.small.copyWith(color: C.text3)),
                ],
              ),
            ),
          const SizedBox(height: 4),
        ],
      ],
    );
  }
}
