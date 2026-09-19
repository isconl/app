import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../widgets/common.dart';

/// Every app/engine the owner runs, across every host -- the isconl engines,
/// Render-hosted apps, and not-yet-hosted services -- read from hub's native
/// `/services` registry. Scaffolding: shows what exists and whether it's up,
/// same shape as `IntegrationsSection`'s status grid. Actions (redeploy,
/// pause) are a later phase, once the registry backs real per-provider
/// control, not just a read-only catalogue.
class HostedServicesView extends StatelessWidget {
  const HostedServicesView({super.key});

  static const _providerLabel = {
    'oracle': 'Oracle',
    'render': 'Render',
    'planned': 'Not yet hosted',
  };

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return SnapshotView(
      snapshot: services.store.hostedServices,
      builder: (context, data) {
        final rows = fmt.lm(fmt.m(data)['services']);
        if (rows.isEmpty) {
          return const EmptyState(
            'No services registered',
            "The hub backend hasn't reported any services yet.",
            icon: Icons.dns_rounded,
          );
        }
        final byProvider = <String, List<Map<String, dynamic>>>{};
        for (final r in rows) {
          byProvider.putIfAbsent(fmt.s(r['provider']), () => []).add(r);
        }
        const order = ['oracle', 'render', 'planned'];

        return ListView(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 96),
          children: [
            for (final provider in order)
              if (byProvider[provider]?.isNotEmpty ?? false) ...[
                SectionLabel(_providerLabel[provider] ?? provider),
                Panel(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      for (final s in byProvider[provider]!) _row(s),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
          ],
        );
      },
    );
  }

  Widget _row(Map<String, dynamic> s) {
    final kind = fmt.s(s['kind']);
    final provider = fmt.s(s['provider']);
    final (label, color) = _status(s, kind, provider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        children: [
          StatusDot(color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(fmt.s(s['name']),
                    style: T.w500(T.body2.copyWith(color: C.text))),
                if (fmt.s(s['note']).isNotEmpty)
                  Text(fmt.s(s['note']), style: T.monoSmall),
              ],
            ),
          ),
          Badge2(label,
              color: color.withValues(alpha: 0.15), textColor: color),
        ],
      ),
    );
  }

  (String, Color) _status(Map<String, dynamic> s, String kind, String provider) {
    if (provider == 'planned') return ('not hosted', C.text3);
    if (kind == 'engine') {
      if (s['configured'] != true) return ('not configured', C.text3);
      if (s['up'] == null) return ('unknown', C.text3);
      return s['up'] == true ? ('up', C.greenBright) : ('down', C.red);
    }
    if (provider == 'render') {
      if (s['found'] != true) return ('not found', C.text3);
      final suspended = fmt.s(s['suspended']);
      return suspended == 'suspended'
          ? ('suspended', C.red)
          : ('live', C.greenBright);
    }
    return ('unknown', C.text3);
  }
}
