import '../api/client.dart';
import '../util/fmt.dart' as fmt;

/// BI26101514: the per-machine ops routes, behind one class that alone knows them. A null machine id is the hub's
/// default machine and uses the original `/api/ops/*` routes unchanged.
///
/// Nothing here runs a service action on its own. The screen asks first, naming the machine and the service, and a
/// destroy asks for the service name to be typed.

class OpsMachine {
  const OpsMachine({required this.id, required this.name, this.provider = '', this.declared = true, this.controllable = false, this.state = '', this.shape = '', this.warning = ''});
  final String id, name, provider, state, shape, warning;
  final bool declared, controllable;

  String get line => [if (provider.isNotEmpty) provider, if (state.isNotEmpty) state.toLowerCase(), if (shape.isNotEmpty) shape].join(' · ');
}

/// The route for [leaf] (`status`, `deploy-status`, `logs`, `service/restart`...) on [machine], with the query
/// pairs encoded. The default machine keeps the original route.
String opsPath(String? machine, String leaf, {Map<String, String> query = const {}}) {
  final q = <String, String>{
    if (machine != null && machine.isNotEmpty) 'machine': machine,
    ...query,
  };
  final base = machine == null || machine.isEmpty ? '/api/ops/$leaf' : '/api/ops/machine/$leaf';
  if (q.isEmpty) return base;
  return '$base?${q.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&')}';
}

/// What a person is asked before a service action runs.
String opsConfirmText({required String action, required String service, required String machineName}) {
  final verb = switch (action) { 'restart' => 'Restart', 'start' => 'Start', 'stop' => 'Stop', 'destroy' => 'Destroy', _ => action };
  return '$verb $service on $machineName?';
}

abstract class OpsMachinesApi {
  Future<List<OpsMachine>> machines();
  Future<Map<String, dynamic>> status(String? machine);
  Future<List<Map<String, dynamic>>> deployStatus(String? machine);
  Future<Map<String, dynamic>> metrics(String machine);
  Future<String> logs(String? machine, String service, {int lines = 200});

  /// Runs restart, start, stop or destroy. [confirm] is the typed service name, sent for destroy only.
  Future<void> serviceAction(String? machine, String service, String action, {String confirm = ''});
}

class HubOpsMachinesApi implements OpsMachinesApi {
  HubOpsMachinesApi(this.api);
  final ApiClient api;

  @override
  Future<List<OpsMachine>> machines() async {
    final m = fmt.m(await api.getJson('/api/ops/machines'));
    return [
      for (final x in fmt.lm(m['machines']))
        OpsMachine(
          id: fmt.s(x['id']),
          name: fmt.s(x['name']).isEmpty ? fmt.s(x['id']) : fmt.s(x['name']),
          provider: fmt.s(x['provider']),
          declared: x['declared'] != false,
          controllable: fmt.b(x['controllable']),
          state: fmt.s(fmt.m(x['oci'])['lifecycleState']),
          shape: fmt.s(fmt.m(x['oci'])['shape']),
          warning: fmt.s(x['configWarning']),
        ),
    ];
  }

  @override
  Future<Map<String, dynamic>> status(String? machine) async => fmt.m(await api.getJson(opsPath(machine, 'status')));

  @override
  Future<List<Map<String, dynamic>>> deployStatus(String? machine) async => fmt.lm(fmt.m(await api.getJson(opsPath(machine, 'deploy-status')))['services']);

  @override
  Future<Map<String, dynamic>> metrics(String machine) async => fmt.m(await api.getJson(opsPath(machine, 'metrics')));

  @override
  Future<String> logs(String? machine, String service, {int lines = 200}) async =>
      fmt.s(fmt.m(await api.getJson(opsPath(machine, 'logs', query: {'service': service, 'lines': '$lines'})))['log']);

  @override
  Future<void> serviceAction(String? machine, String service, String action, {String confirm = ''}) async {
    final r = fmt.m(await api.postJson(opsPath(machine, 'service/$action', query: {'service': service}), action == 'destroy' ? {'confirm': confirm} : {}));
    if (r['ok'] == false) throw ApiException(0, fmt.s(r['error']).isEmpty ? 'unknown error' : fmt.s(r['error']));
  }
}
