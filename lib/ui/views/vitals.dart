import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../shell.dart' show openNavRoute;
import '../widgets/common.dart';

/// BI26092630: Vitals, the data-health successor. The score is coloured with the signals tone
/// tokens (good 80 and above, soon 50 to 79, urgent below 50), the same constants the Hub strip uses.
Color vitalsToneColor(num score) => score >= 80 ? C.green : (score >= 50 ? C.amber : C.red);

Color vitalsStatusColor(String status) => switch (status) {
      'critical' => C.red,
      'warn' => C.amber,
      _ => C.green,
    };

/// Worst first: critical, then warn, then ok.
int vitalsSeverity(String status) => switch (status) {
      'critical' => 0,
      'warn' => 1,
      _ => 2,
    };

/// The worst `n` non-ok checks across every area, worst first (ties keep the server's order).
List<Map<String, dynamic>> worstChecks(dynamic vitals, {int n = 3}) {
  final v = fmt.m(vitals);
  final fromServer = fmt.lm(v['worst']);
  final all = fromServer.isNotEmpty
      ? fromServer
      : [for (final list in fmt.m(v['areas']).values) ...fmt.lm(list)];
  final bad = all.where((c) => fmt.s(c['status']) != 'ok').toList();
  final indexed = [for (var i = 0; i < bad.length; i++) (i, bad[i])];
  indexed.sort((a, b) {
    final s = vitalsSeverity(fmt.s(a.$2['status'])).compareTo(vitalsSeverity(fmt.s(b.$2['status'])));
    return s != 0 ? s : a.$1.compareTo(b.$1);
  });
  return indexed.take(n).map((e) => e.$2).toList();
}

/// A check's fix the app can run: a route to open, or a queued write. Null when it has none.
/// The only action hub names today, `POST /backup/run`, is `/api/vault/sync` on this side.
({String label, String? route, String? queuePath})? vitalsFix(Map<String, dynamic> check) {
  final f = fmt.m(check['fix']);
  if (f.isEmpty) return null;
  final label = fmt.s(f['label']).isEmpty ? 'Fix' : fmt.s(f['label']);
  final route = fmt.s(f['route']);
  if (route.isNotEmpty) return (label: label, route: route, queuePath: null);
  final action = fmt.s(f['action']);
  if (action == 'POST /backup/run') return (label: label, route: null, queuePath: '/api/vault/sync');
  return null;
}

class VitalsRow extends StatelessWidget {
  const VitalsRow({super.key, required this.check});
  final Map<String, dynamic> check;

  @override
  Widget build(BuildContext context) {
    final status = fmt.s(check['status']);
    final fix = vitalsFix(check);
    final threshold = fmt.s(check['threshold']);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: StatusDot(vitalsStatusColor(status)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(fmt.s(check['title']), style: T.w600(T.body2)),
                Text(
                  threshold.isEmpty ? fmt.s(check['value']) : '${fmt.s(check['value'])}  (target: $threshold)',
                  style: T.monoSmall,
                ),
              ],
            ),
          ),
          if (fix != null)
            TextButton(
              key: Key('vitals-fix-${fmt.s(check['id'])}'),
              onPressed: () => _runFix(context, fix),
              child: Text(fix.label),
            ),
        ],
      ),
    );
  }

  Future<void> _runFix(BuildContext context, ({String label, String? route, String? queuePath}) fix) async {
    if (fix.route != null) {
      openNavRoute(context, fix.route!);
      return;
    }
    final services = AppScope.of(context);
    await services.outbox.enqueue(path: fix.queuePath!, body: const {}, label: fix.label, view: 'vitals');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${fix.label}: queued')));
    }
  }
}

/// The Vitals page: every check grouped by area, worst first, with its fix.
class VitalsView extends StatelessWidget {
  const VitalsView({super.key});

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return SnapshotView(
      snapshot: services.store.vitals,
      builder: (context, data) {
        final v = fmt.m(data);
        final areas = fmt.m(v['areas']);
        final score = fmt.i(v['score']);
        final measured = fmt.s(v['measuredAt']);
        int worstOf(String k) =>
            fmt.lm(areas[k]).map((c) => vitalsSeverity(fmt.s(c['status']))).fold<int>(2, (m, s) => s < m ? s : m);
        final names = areas.keys.toList()
          ..sort((a, b) {
            final d = worstOf(a).compareTo(worstOf(b));
            return d != 0 ? d : a.compareTo(b);
          });
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Panel(
              child: Row(
                children: [
                  Text('$score', style: T.headline.copyWith(color: vitalsToneColor(score))),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      measured.isEmpty ? 'every engine reports its own checks' : 'measured ${fmt.ago(measured)}',
                      style: T.small.copyWith(color: C.text3),
                    ),
                  ),
                ],
              ),
            ),
            for (final name in names) ...[
              SectionLabel(name),
              Panel(
                child: Column(
                  children: [
                    for (final c in (fmt.lm(areas[name]).toList()
                      ..sort((a, b) => vitalsSeverity(fmt.s(a['status'])).compareTo(vitalsSeverity(fmt.s(b['status']))))))
                      VitalsRow(check: c),
                  ],
                ),
              ),
            ],
            if (names.isEmpty) const EmptyState('No checks yet', 'No engine has reported a check.'),
          ],
        );
      },
    );
  }
}
