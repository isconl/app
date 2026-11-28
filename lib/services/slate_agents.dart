import '../api/client.dart';
import '../util/fmt.dart' as fmt;

/// BI26102102: slate's agent report through hub (GET /api/slate/agents): one entry per machine with its watched jobs.
/// Only what the API returned is shown. Log tails are plain text, never markup.
class AgentJob {
  const AgentJob({required this.id, this.alive = false, this.stalled = false, this.progress = '', this.label = '', this.row = '', this.logTail = const []});
  final String id, progress, label, row;
  final bool alive, stalled;
  final List<String> logTail;

  String get title => label.isNotEmpty ? label : (row.isNotEmpty ? row : id);

  static AgentJob from(Map<String, dynamic> m) => AgentJob(
        id: fmt.s(m['id']),
        alive: m['alive'] == true,
        stalled: m['stalled'] == true,
        progress: fmt.s(m['progress']),
        label: fmt.s(m['label']),
        row: fmt.s(m['row']),
        logTail: [for (final l in fmt.l(m['logTail'])) '$l'],
      );
}

class AgentMachine {
  const AgentMachine({
    required this.hostname,
    this.os = '',
    this.network = 'unknown',
    this.status = 'offline',
    this.ageSecs,
    this.memFreeMb,
    this.memTotalMb,
    this.diskFreeGb,
    this.jobs = const [],
  });
  final String hostname, os, network, status;
  final int? ageSecs, memFreeMb, memTotalMb;
  final double? diskFreeGb;
  final List<AgentJob> jobs;

  bool get offline => status == 'offline';

  static List<AgentMachine> fromList(List<Map<String, dynamic>> l) => [for (final m in l) from(m)];

  static AgentMachine from(Map<String, dynamic> m) => AgentMachine(
        hostname: fmt.s(m['hostname']).isEmpty ? fmt.s(m['machineId']) : fmt.s(m['hostname']),
        os: fmt.s(m['os']),
        network: fmt.s(m['network']).isEmpty ? 'unknown' : fmt.s(m['network']),
        status: fmt.s(m['status']).isEmpty ? 'offline' : fmt.s(m['status']),
        ageSecs: m['ageSecs'] is num ? (m['ageSecs'] as num).toInt() : null,
        memFreeMb: m['memFreeMb'] is num ? (m['memFreeMb'] as num).toInt() : null,
        memTotalMb: m['memTotalMb'] is num ? (m['memTotalMb'] as num).toInt() : null,
        diskFreeGb: m['diskFreeGb'] is num ? (m['diskFreeGb'] as num).toDouble() : null,
        jobs: [for (final j in fmt.lm(m['jobs'])) AgentJob.from(j)],
      );
}

/// "heard from 20s ago", "heard from 3h ago".
String heardLine(int? ageSecs) {
  if (ageSecs == null) return 'never heard from';
  if (ageSecs < 90) return 'heard from ${ageSecs}s ago';
  if (ageSecs < 5400) return 'heard from ${(ageSecs / 60).round()}m ago';
  if (ageSecs < 172800) return 'heard from ${(ageSecs / 3600).round()}h ago';
  return 'heard from ${(ageSecs / 86400).round()}d ago';
}

String vitalsLine(AgentMachine m) {
  final parts = <String>[
    if (m.memFreeMb != null && m.memTotalMb != null) 'memory ${(m.memFreeMb! / 1024).toStringAsFixed(1)} of ${(m.memTotalMb! / 1024).toStringAsFixed(1)} GB free',
    if (m.diskFreeGb != null) 'disk ${m.diskFreeGb!.toStringAsFixed(0)} GB free',
    if (m.network != 'unknown') m.network,
  ];
  return parts.join(' · ');
}

abstract class AgentsApi {
  Future<List<AgentMachine>> machines();
}

class HubAgentsApi implements AgentsApi {
  HubAgentsApi(this.api);
  final ApiClient api;
  @override
  Future<List<AgentMachine>> machines() async =>
      [for (final m in fmt.lm(fmt.m(await api.getJson('/api/slate/agents'))['machines'])) AgentMachine.from(m)];
}
