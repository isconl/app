import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../widgets/common.dart';

/// Ops: the live control surface for the fleet + the OCI VM (BI26090502),
/// mobile port of the web's renderOps()/loadOpsStatus() (`PS26090501`
/// nav position). Status/VM-stats/deploy-status are read-only polls;
/// restart/stop/start/logs hit the ops engine through hub's existing
/// `/api/ops/*` proxy -- no backend work needed, the routes already exist
/// and the app already talks to the same base URL the web does.
///
/// Destroy is a real, destructive infrastructure control (stops and removes
/// a container -- image/data untouched, but the running instance is gone),
/// ported here WITH the same type-to-confirm guard the web version uses,
/// per Sconl's explicit call that complete parity includes it: the exact
/// service name must be typed into a dialog before the request fires, and
/// ops's own server re-checks the same match independently (`server.js`
/// line ~117), so a bug in this screen can't skip the guard.
///
/// Deliberately NOT cached through Store/Snapshot's offline-blob mechanism
/// (BN26090601's finding) -- live infrastructure state going stale in a
/// local cache would be actively misleading here, unlike a course list.
class OpsView extends StatefulWidget {
  const OpsView({super.key});

  @override
  State<OpsView> createState() => _OpsViewState();
}

class _OpsViewState extends State<OpsView> {
  List<Map<String, dynamic>> _services = [];
  List<Map<String, dynamic>> _deploy = [];
  Map<String, dynamic>? _vmStats;
  bool _loading = true;
  String? _error;
  String? _logsFor;
  String _logsText = '';
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = AppScope.of(context).api;
    setState(() {
      _loading = _services.isEmpty;
      _error = null;
    });
    try {
      final results = await Future.wait([
        api.getJson('/api/ops/status'),
        api.getJson('/api/ops/vm-stats'),
        api.getJson('/api/ops/deploy-status'),
      ]);
      if (!mounted) return;
      setState(() {
        _services = fmt.lm(fmt.m(results[0])['services']);
        _vmStats = fmt.m(results[1]);
        _deploy = fmt.lm(fmt.m(results[2])['services']);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _act(String name, String action) async {
    if (action == 'destroy') {
      final typed = await _typeToConfirm(name);
      if (typed != name) return;
    }
    if (!mounted) return;
    final api = AppScope.of(context).api;
    setState(() => _busy.add(name));
    try {
      final r = await api.postJson(
        '/api/ops/service/$action?service=${Uri.encodeQueryComponent(name)}',
        action == 'destroy' ? {'confirm': name} : {},
      );
      final data = fmt.m(r);
      if (data['ok'] == false && mounted) {
        toast(context, '$action $name failed: ${fmt.s(data['error']).isEmpty ? 'unknown error' : fmt.s(data['error'])}', error: true);
      }
    } catch (e) {
      if (mounted) toast(context, '$action $name failed: $e', error: true);
    }
    if (!mounted) return;
    setState(() => _busy.remove(name));
    _load();
  }

  Future<String?> _typeToConfirm(String name) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Destroy $name?', style: T.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This stops and removes the running container. Image and data '
              'are untouched -- the next start/deploy recreates it. Type the '
              'service name to confirm.',
              style: T.body2,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(hintText: name),
              style: T.monoSmall.copyWith(color: C.text),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: Text('Cancel', style: T.body2.copyWith(color: C.text3)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: C.red),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Destroy'),
          ),
        ],
      ),
    );
  }

  Future<void> _showLogs(String name) async {
    setState(() {
      _logsFor = name;
      _logsText = 'Loading…';
    });
    final api = AppScope.of(context).api;
    try {
      final r = await api.getJson('/api/ops/logs?service=${Uri.encodeQueryComponent(name)}&lines=200');
      if (!mounted) return;
      final log = fmt.s(fmt.m(r)['log']);
      setState(() => _logsText = log.isEmpty ? '(empty)' : log);
    } catch (e) {
      if (!mounted) return;
      setState(() => _logsText = 'Failed to load logs: $e');
    }
  }

  String _fmtBytes(num? n) {
    if (n == null || n == 0) return '0 B';
    var v = n.toDouble();
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i++;
    }
    return '${v.toStringAsFixed(1)} ${units[i]}';
  }

  String _fmtUptime(num? s) {
    if (s == null || s == 0) return '-';
    final total = s.toInt();
    final d = total ~/ 86400, h = (total % 86400) ~/ 3600, m = (total % 3600) ~/ 60;
    if (d > 0) return '${d}d ${h}h';
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      color: C.green,
      backgroundColor: C.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 96),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 120),
              child: Center(child: MiniSpinner(size: 22)),
            )
          else ...[
            if (_error != null) ErrorRetry(_error!, onRetry: _load),
            _vmCard(),
            const SizedBox(height: 10),
            _servicesCard(),
            if (_logsFor != null) ...[
              const SizedBox(height: 10),
              _logsCard(),
            ],
          ],
        ],
      ),
    );
  }

  Widget _vmCard() {
    final s = _vmStats;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('VM', style: T.title),
          const SizedBox(height: 6),
          Text(
            s == null
                ? 'Loading VM stats…'
                : '${fmt.s(s['cpuCount'])} CPU · load ${(s['loadAvg1'] is num) ? (s['loadAvg1'] as num).toStringAsFixed(2) : '-'} · '
                    'mem ${_fmtBytes((s['memTotalBytes'] as num?)?.toDouble().let((t) => t - ((s['memFreeBytes'] as num?)?.toDouble() ?? 0)))} / ${_fmtBytes(s['memTotalBytes'] as num?)} '
                    '(${fmt.s(s['memUsedPct'])}%) · '
                    'up ${_fmtUptime(s['uptimeSeconds'] as num?)}',
            style: T.small.copyWith(color: C.text2),
          ),
        ],
      ),
    );
  }

  Widget _servicesCard() {
    final deployByService = {for (final d in _deploy) fmt.s(d['service']): d};
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Services', style: T.title),
          const SizedBox(height: 8),
          if (_services.isEmpty)
            const EmptyState('No services reported', 'Pull down to refresh.')
          else
            for (final svc in _services) _serviceRow(svc, deployByService[fmt.s(svc['service'])]),
        ],
      ),
    );
  }

  Widget _serviceRow(Map<String, dynamic> svc, Map<String, dynamic>? dep) {
    final name = fmt.s(svc['service']);
    final running = svc['running'] == true;
    final exists = svc['exists'] == true;
    final busy = _busy.contains(name);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusDot(running ? C.green : C.red, glow: running, size: 7),
              const SizedBox(width: 8),
              Expanded(child: Text(name, style: T.w500(T.small))),
              Text(
                running ? 'running' : (exists ? 'stopped' : 'not deployed'),
                style: T.tiny.copyWith(color: C.text3),
              ),
            ],
          ),
          if (dep != null && fmt.s(dep['commit']).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 15, top: 2),
              child: Text(
                '${fmt.s(dep['commit'])} (${fmt.s(dep['branch']).isEmpty ? '?' : fmt.s(dep['branch'])})',
                style: T.monoSmall.copyWith(color: C.text3),
              ),
            ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _actionChip('Restart', () => _act(name, 'restart'), busy),
              _actionChip('Stop', () => _act(name, 'stop'), busy),
              _actionChip('Start', () => _act(name, 'start'), busy),
              _actionChip('Logs', () => _showLogs(name), busy),
              _actionChip('Destroy', () => _act(name, 'destroy'), busy, color: C.red),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionChip(String label, VoidCallback onTap, bool busy, {Color? color}) {
    return InkWell(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          border: Border.all(color: C.border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label, style: T.tiny.copyWith(color: busy ? C.text3 : (color ?? C.text2))),
      ),
    );
  }

  Widget _logsCard() {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('$_logsFor — last 200 lines', style: T.title)),
              InkWell(
                onTap: () => setState(() => _logsFor = null),
                child: Text('Close', style: T.small.copyWith(color: C.text3)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 400),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: C.bg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: C.border),
            ),
            child: SingleChildScrollView(
              child: Text(_logsText, style: T.monoSmall.copyWith(color: C.text2)),
            ),
          ),
        ],
      ),
    );
  }
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
