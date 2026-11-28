import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/ui/views/ops_model.dart';

void main() {
  test('the three headline states parse from the server shape', () {
    expect(OpsHeadline.fromJson({'level': 'ok', 'text': 'VM healthy · 26 containers · 0 restarts in 24 h', 'target': null}).level, OpsLevel.ok);
    final amber = OpsHeadline.fromJson({'level': 'amber', 'text': 'xkeel-hold unhealthy', 'target': 'hold'});
    expect(amber.level, OpsLevel.amber);
    expect(amber.target, 'hold');
    final red = OpsHeadline.fromJson({'level': 'red', 'text': 'vault restarting', 'target': 'vault'});
    expect(red.level, OpsLevel.red);
    expect(red.text, 'vault restarting');
  });

  test('a failed call is amber and names the call', () {
    final h = OpsHeadline.failed(['status', 'vm-stats']);
    expect(h.level, OpsLevel.amber);
    expect(h.text, 'status and vm-stats call failed');
  });

  test('vm stats parse cores, swap, disks, containers and the headline', () {
    final vm = OpsVm.fromJson({
      'cpuCount': 4, 'cpuPct': 24.4, 'cpuPerCorePct': [10, 20, 30.5, 40],
      'loadAvg1': 0.67, 'loadAvg5': 0.75, 'loadAvg15': 0.65,
      'memTotalBytes': 25139412992, 'memUsedPct': 7.9,
      'swap': {'totalBytes': 0, 'usedBytes': 0, 'usedPct': 0},
      'disks': [{'mount': '/', 'usedPct': 75, 'usedBytes': 3e10, 'totalBytes': 4e10}],
      'uptimeSeconds': 90061,
      'net': {'rxBytes': 1000, 'txBytes': 2000},
      'containers': [{'service': 'hold', 'running': true, 'status': 'running', 'health': 'healthy', 'restartCount': 0, 'cpuPct': 1.5, 'memBytes': 2e7, 'memLimitBytes': 5e8}],
      'headline': {'level': 'ok', 'text': 'VM healthy · 1 containers · 0 restarts in 24 h'},
    });
    expect(vm.perCore.length, 4);
    expect(vm.disks.single.usedPct, 75);
    expect(vm.containers['hold']!.cpuPct, 1.5);
    expect(vm.headline!.level, OpsLevel.ok);
    expect(opsUptime(vm.uptimeSeconds), '1d 1h');
  });

  test('a missing headline and empty lists do not throw', () {
    final vm = OpsVm.fromJson({});
    expect(vm.headline, isNull);
    expect(vm.disks, isEmpty);
    expect(vm.containers, isEmpty);
  });

  test('byte formatting', () {
    expect(opsBytes(0), '0 B');
    expect(opsBytes(1536), '1.5 KB');
    expect(opsBytes(25139412992), '23.4 GB');
    expect(opsBytes(300 * 1048576), '300 MB');
  });

  test('service state: finished one-shot jobs are not stopped, and restart loops are red', () {
    expect(opsServiceState({'exists': true, 'running': false, 'exitCode': 0, 'status': 'exited'}), 'finished');
    expect(opsServiceLevel({'exists': true, 'running': false, 'exitCode': 0, 'status': 'exited'}), OpsLevel.ok);
    expect(opsServiceState({'exists': true, 'running': false, 'exitCode': 1, 'status': 'exited'}), 'stopped');
    expect(opsServiceLevel({'exists': true, 'running': false, 'exitCode': 1}), OpsLevel.red);
    expect(opsServiceState({'exists': true, 'running': true, 'status': 'restarting'}), 'restarting');
    expect(opsServiceState({'exists': true, 'running': true, 'health': 'healthy'}), 'running · healthy');
    expect(opsServiceLevel({'exists': true, 'running': true, 'health': 'unhealthy'}), OpsLevel.amber);
    expect(opsServiceState({'exists': false}), 'not deployed');
  });
}
