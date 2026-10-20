// BI26101514: the per-machine ops routes, their confirm text, and that a service action goes to the machine chosen.
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/api/client.dart';
import 'package:isconl/services/ops_machines.dart';

class _Rec extends ApiClient {
  _Rec(this.answers) : super(baseUrl: 'http://test', token: 'test');
  final Map<String, Object> answers;
  final gets = <String>[];
  final posts = <(String, Map<String, dynamic>)>[];

  @override
  Future<dynamic> getJson(String path, {bool cold = false}) async {
    gets.add(path);
    for (final e in answers.entries) {
      if (path.startsWith(e.key)) return e.value;
    }
    return {};
  }

  @override
  Future<dynamic> postJson(String path, Map<String, dynamic> body, {bool cold = false}) async {
    posts.add((path, body));
    for (final e in answers.entries) {
      if (path.startsWith(e.key)) return e.value;
    }
    return {'ok': true};
  }
}

void main() {
  test('the default machine keeps the original routes; another machine gets the machine routes with its id', () {
    expect(opsPath(null, 'status'), '/api/ops/status');
    expect(opsPath('', 'deploy-status'), '/api/ops/deploy-status');
    expect(opsPath('m1', 'status'), '/api/ops/machine/status?machine=m1');
    expect(opsPath('m 1', 'logs', query: {'service': 'hub', 'lines': '200'}), '/api/ops/machine/logs?machine=m+1&service=hub&lines=200');
    expect(opsPath(null, 'service/restart', query: {'service': 'hub'}), '/api/ops/service/restart?service=hub');
    expect(opsPath('m1', 'service/stop', query: {'service': 'x&y'}), '/api/ops/machine/service/stop?machine=m1&service=x%26y');
  });

  test('the confirm names the service and the machine', () {
    expect(opsConfirmText(action: 'restart', service: 'xkeel-hold', machineName: 'engines'), 'Restart xkeel-hold on engines?');
    expect(opsConfirmText(action: 'stop', service: 'hub', machineName: 'this machine'), 'Stop hub on this machine?');
    expect(opsConfirmText(action: 'destroy', service: 'hub', machineName: 'statics'), 'Destroy hub on statics?');
  });

  test('machines parse with their live state, and a view-only or misconfigured one says so', () async {
    final api = _Rec({
      '/api/ops/machines': {
        'machines': [
          {'id': 'engines', 'name': 'engines', 'provider': 'oci', 'declared': true, 'controllable': true, 'oci': {'lifecycleState': 'RUNNING', 'shape': 'VM.Standard.A1.Flex'}},
          {'id': 'ocid1.x', 'name': 'spare', 'provider': 'oci', 'declared': false, 'controllable': false, 'oci': {'lifecycleState': 'STOPPED', 'shape': 'VM.Standard.E2.1'}, 'configWarning': 'no OCI_INSTANCE_ID'},
        ]
      }
    });
    final ms = await HubOpsMachinesApi(api).machines();
    expect(ms.map((m) => m.id), ['engines', 'ocid1.x']);
    expect(ms.first.controllable, isTrue);
    expect(ms.first.line, 'oci · running · VM.Standard.A1.Flex');
    expect(ms.last.controllable, isFalse);
    expect(ms.last.declared, isFalse);
    expect(ms.last.warning, 'no OCI_INSTANCE_ID');
  });

  test('status, deploys and logs are asked of the machine chosen', () async {
    final api = _Rec({
      '/api/ops/machine/status': {'groups': {}},
      '/api/ops/machine/deploy-status': {'services': [{'service': 'hub', 'state': 'deployed'}]},
      '/api/ops/machine/logs': {'log': 'line one'},
    });
    final ops = HubOpsMachinesApi(api);
    await ops.status('engines');
    expect((await ops.deployStatus('engines')).single['service'], 'hub');
    expect(await ops.logs('engines', 'hub'), 'line one');
    expect(api.gets, [
      '/api/ops/machine/status?machine=engines',
      '/api/ops/machine/deploy-status?machine=engines',
      '/api/ops/machine/logs?machine=engines&service=hub&lines=200',
    ]);
  });

  test('a service action goes to the chosen machine; destroy carries the typed name, the others carry nothing', () async {
    final api = _Rec({});
    final ops = HubOpsMachinesApi(api);
    await ops.serviceAction('engines', 'hub', 'restart', confirm: 'hub');
    await ops.serviceAction(null, 'hub', 'destroy', confirm: 'hub');
    expect(api.posts[0].$1, '/api/ops/machine/service/restart?machine=engines&service=hub');
    expect(api.posts[0].$2, isEmpty, reason: 'only a destroy sends the typed confirmation');
    expect(api.posts[1].$1, '/api/ops/service/destroy?service=hub');
    expect(api.posts[1].$2, {'confirm': 'hub'});
  });

  test('a refusal from ops is an error in its own words', () async {
    final api = _Rec({'/api/ops/machine/service/stop': {'ok': false, 'error': 'machine is view only'}});
    await expectLater(HubOpsMachinesApi(api).serviceAction('spare', 'hub', 'stop'), throwsA(isA<ApiException>().having((e) => e.message, 'message', 'machine is view only')));
  });
}
