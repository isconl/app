import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../widgets/common.dart';
import '../widgets/incident_cards.dart';
import 'ops_model.dart';
import '../../services/ops_machines.dart';
import '../widgets/space_header.dart';

/// OpSec: the live control surface for the fleet + the OCI VM (BI26090502),
/// mobile port of the web's renderOps()/loadOpsStatus(). Status/VM-stats/
/// deploy-status are read-only polls; restart/stop/start/logs hit the ops
/// engine through hub's existing `/api/ops/*` proxy -- no backend work
/// needed, the routes already exist and the app already talks to the same
/// base URL the web does.
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
///
/// BG26091020: merged with the former standalone `SecurityView` into one
/// "Opsec" space -- Security's stub content (`PS26090501`, dead-hand remote
/// wipe + future hardening, still not yet scoped) now renders as a section
/// at the bottom of this same view instead of its own bottom-nav sub-tab,
/// matching the equivalent web-side merge into `renderOps()`. Class kept
/// named `OpsView` (not renamed to `OpsecView`) since the file/class rename
/// carries no functional weight and every other reference in this repo
/// already keys off the old name -- only the sub-tab label + nav wiring
/// (`shell.dart`) needed to change for this to read as "Opsec" everywhere
/// a user sees it.
class OpsView extends StatefulWidget {
  const OpsView({super.key});

  @override
  State<OpsView> createState() => _OpsViewState();
}

class _OpsViewState extends State<OpsView> {
  Map<String, List<Map<String, dynamic>>> _groups = {};
  List<Map<String, dynamic>> _ungrouped = [];
  bool _discoveryOk = true;
  String? _discoveryError;
  List<Map<String, dynamic>> _deploy = [];
  OpsVm? _vm;
  // Which of the three polls failed on the last refresh, by name, so the headline can say so (BI26101812).
  final List<String> _failed = [];
  final Map<String, String> _failMsg = {};
  Timer? _timer;
  bool _loading = true;

  // BI26101514: the machines ops knows, and the one on screen (null is the hub's default machine).
  OpsMachinesApi? _opsApi;
  List<OpsMachine> _machines = const [];
  String? _machine;
  OpsMachinesApi get _ops => _opsApi ??= HubOpsMachinesApi(AppScope.of(context).api);
  String get _machineName => _machine == null ? 'this machine' : (_machines.where((m) => m.id == _machine).firstOrNull?.name ?? _machine!);
  String? _error;
  String? _logsFor;
  String _logsText = '';
  final Set<String> _busy = {};

  bool get _hasAnyService => _groups.isNotEmpty || _ungrouped.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _load();
    // Live stats: refreshed every 15 s while the view is open (BI26101812).
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted && _busy.isEmpty) _load(quiet: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  /// One poll, tolerant of a single call failing: the other two still render, and the failing call is named.
  Future<Map<String, dynamic>?> _try(String name, String path) async {
    try {
      return fmt.m(await AppScope.of(context).api.getJson(path));
    } catch (e) {
      _failed.add(name);
      _failMsg[name] = e.toString().replaceAll(RegExp(r'\s+'), ' ');
      return null;
    }
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        _loading = !_hasAnyService;
        _error = null;
      });
    }
    _failed.clear();
    _failMsg.clear();
    if (_machines.isEmpty) {
      try {
        final ms = await _ops.machines();
        if (mounted) _machines = ms;
      } catch (_) {
        // A hub without the machines route still shows its default machine.
      }
    }
    final results = await Future.wait([
      _try('status', opsPath(_machine, 'status')),
      // The VM numbers are the default machine's; another machine shows its own status and deploys only.
      _machine == null ? _try('vm-stats', '/api/ops/vm-stats') : Future<Map<String, dynamic>?>.value(null),
      _try('deploy-status', opsPath(_machine, 'deploy-status')),
    ]);
    if (!mounted) return;
    final status = results[0];
    setState(() {
      if (status != null) {
        final rawGroups = fmt.m(status['groups']);
        _groups = {for (final e in rawGroups.entries) e.key: fmt.lm(e.value)};
        _ungrouped = fmt.lm(status['ungrouped']);
        _discoveryOk = status['discoveryOk'] != false;
        _discoveryError = fmt.s(status['discoveryError']).isEmpty ? null : fmt.s(status['discoveryError']);
      }
      if (results[1] != null) _vm = OpsVm.fromJson(results[1]!);
      if (results[2] != null) _deploy = fmt.lm(results[2]!['services']);
      _loading = false;
      _error = _failed.isEmpty ? null : _failed.map((n) => '$n: ${_failMsg[n]}').join('\n');
    });
  }

  Future<void> _act(String name, String action) async {
    if (action == 'destroy') {
      final typed = await _typeToConfirm(name);
      if (typed != name) return;
    } else {
      // BI26101514: restart, start and stop ask first, naming the machine and the service.
      final sure = await confirmDialog(context, opsConfirmText(action: action, service: name, machineName: _machineName),
          action == 'stop' ? 'The service stops until it is started again.' : 'Nothing else on $_machineName is touched.',
          action: action == 'restart' ? 'Restart' : action == 'start' ? 'Start' : 'Stop');
      if (!sure) return;
    }
    if (!mounted) return;
    setState(() => _busy.add(name));
    try {
      await _ops.serviceAction(_machine, name, action, confirm: name);
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
    _tabs.select(2);
    try {
      final log = await _ops.logs(_machine, name);
      if (!mounted) return;
      setState(() => _logsText = log.isEmpty ? '(empty)' : log);
    } catch (e) {
      if (!mounted) return;
      setState(() => _logsText = 'Failed to load logs: $e');
    }
  }

  final _tabs = SpaceTabController();

  @override
  Widget build(BuildContext context) {
    // BI26101802: OpSec wears the shared space header: the headline, a search over services and incidents, then three
    // tabs. Health: incidents and the VM. Services: every service with its actions. Logs: the log tail and security.
    Widget scroll(List<Widget> children) => RefreshIndicator(
          onRefresh: _load,
          color: C.green,
          backgroundColor: C.surface,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 96),
            physics: const AlwaysScrollableScrollPhysics(),
            children: _loading
                ? const [Padding(padding: EdgeInsets.only(top: 120), child: Center(child: MiniSpinner(size: 22)))]
                : children,
          ),
        );
    return SpaceView(
      space: 'opsec',
      searchHint: 'Search services and incidents',
      controller: _tabs,
      top: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_machinePicker(), _headlineBanner()]),
      hits: (_) => [
        for (final g in _groups.values)
          for (final svc in g)
            SpaceHit(title: fmt.s(svc['service']), subtitle: '${fmt.s(svc['group'])} · ${opsServiceState(svc)}', tab: 1),
        for (final svc in _ungrouped) SpaceHit(title: fmt.s(svc['service']), subtitle: opsServiceState(svc), tab: 1),
      ],
      tabs: [
        SpaceTab('Health', scroll([
          if (_error != null) ErrorRetry(_error!, onRetry: _load),
          const IncidentCards(),
          _vmCard(),
        ])),
        SpaceTab('Services', scroll([
          if (!_discoveryOk)
            _discoveryErrorCard()
          else if (!_hasAnyService)
            const Panel(child: EmptyState('Loading…', 'Pull down to refresh.'))
          else ...[
            for (final key in (_groups.keys.toList()..sort())) ...[
              _servicesCard(key, _groups[key]!),
              const SizedBox(height: 10),
            ],
            if (_ungrouped.isNotEmpty) _servicesCard('Ungrouped', _ungrouped),
          ],
        ])),
        SpaceTab('Logs', scroll([
          if (_logsFor != null)
            _logsCard()
          else
            const Panel(child: EmptyState('No logs open', 'Choose Logs on a service to read its last 200 lines here.', icon: Icons.article_outlined)),
          const SizedBox(height: 10),
          _securityCard(),
        ])),
      ],
    );
  }

  // BG26091020: folded in from the former standalone SecurityView -- same
  // placeholder content, now a section of Opsec rather than its own tab.
  Widget _securityCard() {
    return const Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Security', style: T.title),
          SizedBox(height: 6),
          EmptyState(
            'Coming later',
            'Flagship item: dead-hand remote wipe of data from any '
                'logged-in device. Needs its own design pass before this '
                'section has real content.',
            icon: Icons.shield_outlined,
          ),
        ],
      ),
    );
  }

  Color _levelColor(OpsLevel l) => switch (l) { OpsLevel.red => C.red, OpsLevel.amber => C.amber, OpsLevel.ok => C.green };

  /// The one line at the top: the server's headline, or amber naming the failed call when there is none.
  OpsHeadline? get _headline => _failed.isNotEmpty && _vm?.headline == null ? OpsHeadline.failed(_failed) : _vm?.headline;

  /// The machines ops knows. Hidden when there is only the default one.
  Widget _machinePicker() {
    if (_machines.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DropdownButton<String?>(
        key: const Key('ops-machine'),
        isExpanded: true,
        value: _machine,
        items: [
          const DropdownMenuItem<String?>(value: null, child: Text('This machine (default)')),
          for (final m in _machines)
            DropdownMenuItem<String?>(value: m.id, child: Text([m.name, if (!m.controllable) '(view only)', if (m.line.isNotEmpty) '· ${m.line}'].join(' '), overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (v) {
          setState(() {
            _machine = v;
            _groups = {};
            _ungrouped = [];
            _deploy = [];
            _logsFor = null;
          });
          _load();
        },
      ),
    );
  }

  Widget _headlineBanner() {
    final h = _headline;
    if (h == null) return const SizedBox.shrink();
    final color = _levelColor(h.level);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        // Tap opens the failing item: a service opens its logs, anything else scrolls nowhere and just stays visible.
        onTap: h.target != null && _isService(h.target!) ? () => _showLogs(h.target!) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            border: Border.all(color: color.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            StatusDot(color, glow: h.level != OpsLevel.ok, size: 8),
            const SizedBox(width: 10),
            Expanded(child: Text(h.text, style: T.w500(T.small))),
          ]),
        ),
      ),
    );
  }

  bool _isService(String name) =>
      _groups.values.any((l) => l.any((s) => fmt.s(s['service']) == name)) || _ungrouped.any((s) => fmt.s(s['service']) == name);

  Widget _bar(double pct, {Color? color}) {
    final c = color ?? (pct >= 90 ? C.red : (pct >= 75 ? C.amber : C.green));
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: LinearProgressIndicator(value: (pct / 100).clamp(0.0, 1.0), minHeight: 6, backgroundColor: C.border, valueColor: AlwaysStoppedAnimation(c)),
    );
  }

  Widget _meter(String label, double pct, String trailing) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(label, style: T.small.copyWith(color: C.text2))),
          Text(trailing, style: T.tiny.copyWith(color: C.text3)),
        ]),
        const SizedBox(height: 3),
        _bar(pct),
      ]),
    );
  }

  Widget _vmCard() {
    final s = _vm;
    if (s == null) {
      return Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('VM', style: T.title),
          const SizedBox(height: 6),
          Text(_failed.contains('vm-stats') ? 'VM stats unavailable (${_failMsg['vm-stats']})' : 'Loading VM stats…',
              style: T.small.copyWith(color: C.text2)),
        ]),
      );
    }
    final memUsed = s.memTotal * s.memUsedPct / 100;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('VM · engines', style: T.title),
          const SizedBox(height: 4),
          Text('${s.cpuCount} CPU · load ${s.load1.toStringAsFixed(2)} ${s.load5.toStringAsFixed(2)} ${s.load15.toStringAsFixed(2)} · up ${opsUptime(s.uptimeSeconds)}',
              style: T.small.copyWith(color: C.text2)),
          const SizedBox(height: 10),
          if (s.cpuPct != null) _meter('CPU', s.cpuPct!, '${s.cpuPct!.toStringAsFixed(1)}%'),
          if (s.perCore.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                for (var i = 0; i < s.perCore.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('core $i · ${s.perCore[i].toStringAsFixed(0)}%', style: T.tiny.copyWith(color: C.text3)),
                    const SizedBox(height: 2),
                    _bar(s.perCore[i]),
                  ])),
                ],
              ]),
            ),
          _meter('Memory', s.memUsedPct, '${opsBytes(memUsed)} / ${opsBytes(s.memTotal)} · ${s.memUsedPct.toStringAsFixed(1)}%'),
          if (s.swapTotal > 0) _meter('Swap', s.swapUsedPct, '${s.swapUsedPct.toStringAsFixed(1)}% of ${opsBytes(s.swapTotal)}'),
          for (final d in s.disks)
            _meter('Disk ${d.mount}', d.usedPct.toDouble(), '${opsBytes(d.usedBytes)} / ${opsBytes(d.totalBytes)} · ${d.usedPct}%'),
          Text('Network since container start: in ${opsBytes(s.netRx)} · out ${opsBytes(s.netTx)}', style: T.tiny.copyWith(color: C.text3)),
        ],
      ),
    );
  }

  Widget _discoveryErrorCard() {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Service discovery failed', style: T.title.copyWith(color: C.red)),
          const SizedBox(height: 6),
          Text(_discoveryError ?? 'docker compose config could not be read', style: T.small.copyWith(color: C.text2)),
        ],
      ),
    );
  }

  Widget _servicesCard(String label, List<Map<String, dynamic>> services) {
    final deployByService = {for (final d in _deploy) fmt.s(d['service']): d};
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: T.title),
          const SizedBox(height: 8),
          for (final svc in services) _serviceRow(svc, deployByService[fmt.s(svc['service'])]),
        ],
      ),
    );
  }

  Widget _serviceRow(Map<String, dynamic> svc, Map<String, dynamic>? dep) {
    final name = fmt.s(svc['service']);
    final running = svc['running'] == true;
    final exists = svc['exists'] == true;
    final controllable = svc['controllable'] == true;
    final busy = _busy.contains(name);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusDot(!exists ? C.text3 : _levelColor(opsServiceLevel(svc)), glow: running && opsServiceLevel(svc) == OpsLevel.ok, size: 7),
              const SizedBox(width: 8),
              Expanded(child: Text(name, style: T.w500(T.small))),
              Text(opsServiceState(svc), style: T.tiny.copyWith(color: C.text3)),
            ],
          ),
          if (_vm?.containers[name] != null) _statsLine(_vm!.containers[name]!),
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
              // BI26091501 follow-up: a service with no ops.control compose
              // label is read-only server-side now -- hide the write chips
              // rather than offer a tap the server will refuse anyway.
              if (controllable) ...[
                _actionChip('Restart', () => _act(name, 'restart'), busy),
                _actionChip('Stop', () => _act(name, 'stop'), busy),
                _actionChip('Start', () => _act(name, 'start'), busy),
                _actionChip('Destroy', () => _act(name, 'destroy'), busy, color: C.red),
              ] else
                Text('Read-only', style: T.tiny.copyWith(color: C.text3)),
              _actionChip('Logs', () => _showLogs(name), busy),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statsLine(OpsContainer c) {
    final parts = <String>[
      if (c.cpuPct != null) 'cpu ${c.cpuPct!.toStringAsFixed(1)}%',
      if (c.memBytes != null) 'mem ${opsBytes(c.memBytes)}${c.memLimitBytes != null && c.memLimitBytes! > 0 ? ' / ${opsBytes(c.memLimitBytes)}' : ''}',
      '${c.restartCount} restarts',
    ];
    return Padding(
      padding: const EdgeInsets.only(left: 15, top: 2),
      child: Text(parts.join(' · '), style: T.tiny.copyWith(color: C.text3)),
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
              Expanded(child: Text('$_logsFor (last 200 lines)', style: T.title)),
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
