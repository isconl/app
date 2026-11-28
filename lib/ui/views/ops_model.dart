import '../../util/fmt.dart' as fmt;

/// BI26101812: the live numbers OpSec shows, parsed once from `/api/ops/vm-stats` (ops 0.9.0+). Pure, so the three
/// headline states and the byte/percent formatting are tested from fixtures.
enum OpsLevel { ok, amber, red }

class OpsHeadline {
  const OpsHeadline(this.level, this.text, this.target);
  final OpsLevel level;
  final String text;
  /// The service name (or `disk`, `memory`, `vm`, `status`) the headline points at, so a tap can open it.
  final String? target;

  static OpsHeadline fromJson(Map<String, dynamic> j) {
    final lvl = switch (fmt.s(j['level'])) { 'red' => OpsLevel.red, 'amber' => OpsLevel.amber, _ => OpsLevel.ok };
    final t = fmt.s(j['target']);
    return OpsHeadline(lvl, fmt.s(j['text']), t.isEmpty ? null : t);
  }

  /// When the call itself failed there is no server headline, so the app says so in amber and names the call.
  static OpsHeadline failed(List<String> calls) =>
      OpsHeadline(OpsLevel.amber, '${calls.join(' and ')} call failed', null);
}

class OpsDisk {
  const OpsDisk(this.mount, this.usedPct, this.usedBytes, this.totalBytes);
  final String mount;
  final int usedPct;
  final double usedBytes;
  final double totalBytes;
}

class OpsContainer {
  const OpsContainer({required this.service, required this.running, required this.status, required this.health,
      required this.restartCount, required this.cpuPct, required this.memBytes, required this.memLimitBytes});
  final String service;
  final bool running;
  final String status;
  final String health;
  final int restartCount;
  final double? cpuPct;
  final double? memBytes;
  final double? memLimitBytes;
}

class OpsVm {
  const OpsVm({required this.cpuCount, required this.cpuPct, required this.perCore, required this.load1,
      required this.load5, required this.load15, required this.memTotal, required this.memUsedPct, required this.swapUsedPct,
      required this.swapTotal, required this.disks, required this.uptimeSeconds, required this.netRx, required this.netTx,
      required this.containers, required this.headline});
  final int cpuCount;
  final double? cpuPct;
  final List<double> perCore;
  final double load1, load5, load15;
  final double memTotal;
  final double memUsedPct;
  final double swapUsedPct;
  final double swapTotal;
  final List<OpsDisk> disks;
  final double uptimeSeconds;
  final double netRx, netTx;
  final Map<String, OpsContainer> containers;
  final OpsHeadline? headline;

  static OpsVm fromJson(Map<String, dynamic> j) {
    final swap = fmt.m(j['swap']);
    final net = fmt.m(j['net']);
    final containers = <String, OpsContainer>{};
    for (final c in fmt.lm(j['containers'])) {
      final name = fmt.s(c['service']);
      if (name.isEmpty) continue;
      containers[name] = OpsContainer(
        service: name,
        running: c['running'] == true,
        status: fmt.s(c['status']),
        health: fmt.s(c['health']),
        restartCount: fmt.i(c['restartCount']),
        cpuPct: fmt.dOrNull(c['cpuPct']),
        memBytes: fmt.dOrNull(c['memBytes']),
        memLimitBytes: fmt.dOrNull(c['memLimitBytes']),
      );
    }
    final head = fmt.m(j['headline']);
    return OpsVm(
      cpuCount: fmt.i(j['cpuCount']),
      cpuPct: fmt.dOrNull(j['cpuPct']),
      perCore: [for (final v in fmt.l(j['cpuPerCorePct'])) fmt.d(v)],
      load1: fmt.d(j['loadAvg1']),
      load5: fmt.d(j['loadAvg5']),
      load15: fmt.d(j['loadAvg15']),
      memTotal: fmt.d(j['memTotalBytes']),
      memUsedPct: fmt.d(j['memUsedPct']),
      swapUsedPct: fmt.d(swap['usedPct']),
      swapTotal: fmt.d(swap['totalBytes']),
      disks: [
        for (final d in fmt.lm(j['disks']))
          OpsDisk(fmt.s(d['mount']), fmt.i(d['usedPct']), fmt.d(d['usedBytes']), fmt.d(d['totalBytes'])),
      ],
      uptimeSeconds: fmt.d(j['uptimeSeconds']),
      netRx: fmt.d(net['rxBytes']),
      netTx: fmt.d(net['txBytes']),
      containers: containers,
      headline: head.isEmpty ? null : OpsHeadline.fromJson(head),
    );
  }
}

String opsBytes(num? n) {
  if (n == null || n <= 0) return '0 B';
  var v = n.toDouble();
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v >= 100 || i == 0 ? 0 : 1)} ${units[i]}';
}

String opsUptime(num? s) {
  if (s == null || s <= 0) return '-';
  final total = s.toInt();
  final d = total ~/ 86400, h = (total % 86400) ~/ 3600, m = (total % 3600) ~/ 60;
  if (d > 0) return '${d}d ${h}h';
  if (h > 0) return '${h}h ${m}m';
  return '${m}m';
}

/// The label for one service row. A one-shot job that exited cleanly reads "finished", not "stopped".
String opsServiceState(Map<String, dynamic> svc) {
  final running = svc['running'] == true;
  if (svc['exists'] != true) return 'not deployed';
  if (fmt.s(svc['status']) == 'restarting') return 'restarting';
  if (running) {
    final h = fmt.s(svc['health']);
    return h.isEmpty ? 'running' : 'running · $h';
  }
  if (fmt.i(svc['exitCode'], -1) == 0 && fmt.s(svc['health']).isEmpty) return 'finished';
  return 'stopped';
}

/// Red for down or restarting, amber for unhealthy, green for running or a finished job, grey for not deployed.
OpsLevel opsServiceLevel(Map<String, dynamic> svc) {
  if (svc['exists'] != true) return OpsLevel.ok;
  final state = opsServiceState(svc);
  if (state == 'restarting' || state == 'stopped') return OpsLevel.red;
  if (fmt.s(svc['health']) == 'unhealthy') return OpsLevel.amber;
  return OpsLevel.ok;
}
