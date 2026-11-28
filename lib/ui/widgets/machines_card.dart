import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../services/slate_agents.dart';
import '../../theme.dart';
import 'common.dart';

/// BI26102102: each machine slate's agent reports, with its vitals and the jobs it is watching. Offline machines stay
/// listed (greyed, with when they were last heard from). Tap a job for its masked log tail, shown as plain text.
class MachinesCard extends StatefulWidget {
  const MachinesCard({super.key, this.api});
  final AgentsApi? api;
  @override
  State<MachinesCard> createState() => _MachinesCardState();
}

class _MachinesCardState extends State<MachinesCard> {
  Future<List<AgentMachine>>? _f;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _f ??= (widget.api ?? HubAgentsApi(AppScope.of(context).api)).machines();
  }

  Color _dot(String s) => switch (s) { 'online' => C.green, 'quiet' => C.amber, _ => C.text3 };

  @override
  Widget build(BuildContext context) => FutureBuilder<List<AgentMachine>>(
        future: _f,
        builder: (ctx, snap) {
          if (snap.connectionState != ConnectionState.done) return const SizedBox(height: 8);
          if (snap.hasError) return const SizedBox.shrink();
          final ms = snap.data ?? const <AgentMachine>[];
          if (ms.isEmpty) return const SizedBox.shrink();
          return Panel(
            key: const Key('machines-card'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Machines', style: T.title),
              for (final m in ms)
                Opacity(
                  opacity: m.offline ? 0.55 : 1,
                  child: Padding(
                    key: Key('machine-${m.hostname}'),
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Icon(Icons.circle, size: 10, color: _dot(m.status)),
                        const SizedBox(width: 6),
                        Expanded(child: Text('${m.hostname} · ${m.status}', style: T.body.copyWith(fontWeight: FontWeight.w700))),
                        Text(heardLine(m.ageSecs), style: T.tiny.copyWith(color: C.text3)),
                      ]),
                      if (vitalsLine(m).isNotEmpty) Text(vitalsLine(m), style: T.small.copyWith(color: C.text3)),
                      for (final j in m.jobs)
                        InkWell(
                          key: Key('job-${m.hostname}-${j.id}'),
                          onTap: () => _tail(ctx, m, j),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              '${j.title}${j.progress.isEmpty ? '' : ' · ${j.progress}'}${j.stalled ? ' · stalled' : ''}',
                              style: T.small.copyWith(color: j.stalled ? C.red : C.text2),
                            ),
                          ),
                        ),
                    ]),
                  ),
                ),
            ]),
          );
        },
      );

  void _tail(BuildContext context, AgentMachine m, AgentJob j) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${j.title} on ${m.hostname}', style: T.title),
            const SizedBox(height: 8),
            if (j.logTail.isEmpty)
              const Text('No log lines reported.', key: Key('job-tail-empty'))
            else
              Text(j.logTail.join('\n'), key: const Key('job-tail'), style: T.monoSmall), // plain text: untrusted input, never markup
          ]),
        ),
      );
}
