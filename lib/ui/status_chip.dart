import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../data/sync.dart' show SyncPhase;
import '../theme.dart';
import '../util/fmt.dart' as fmt;
import '../util/equicycle.dart';
import 'views/backlog.dart';
import 'views/ops.dart';
import 'views/planning.dart';
import 'views/systems_dash_model.dart';
import 'widgets/common.dart';

/// BI26092622: one succinct, very subtle piece of status after a view's title in the app bar.
/// Tapping it opens a dedicated page for that status. A view declares its chip through a
/// [StatusChipSource], so the shell never needs to know a view's internals; no chip means no dot.

/// Opens a status page full screen under a title (the shell's secondary-screen route).
typedef OpenStatusPage = void Function(BuildContext context, String title, Widget page);

class StatusChip {
  const StatusChip(this.text, this.onTap);
  final String text;
  final void Function(BuildContext context) onTap;
}

abstract class StatusChipSource {
  /// Rebuilds the chip when this changes.
  Listenable get changes;

  /// The chip now, or null for none.
  StatusChip? current(BuildContext context);
}

/// `live`, `2m ago`, `offline` or `3 queued`, in that order of precedence: offline first, then
/// queued writes, then how long ago the last full sync was.
String freshnessText({
  required bool online,
  required int pending,
  required DateTime? lastSync,
  required DateTime now,
}) {
  if (!online) return 'offline';
  if (pending > 0) return '$pending queued';
  if (lastSync == null) return 'live';
  final d = now.difference(lastSync);
  if (d.inSeconds < 90) return 'live';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 48) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}

/// How many live backlog rows the cached `/api/backlog` snapshot holds, or null if it holds none yet.
int? backlogRowCount(dynamic snapshotValue) {
  final projects = fmt.lm(fmt.m(snapshotValue)['projects']);
  if (projects.isEmpty) return null;
  return projects.fold<int>(0, (n, p) => n + fmt.lm(p['rows']).length);
}

/// Command: `reap d12/28`, the cycle word in lower case and the day of the 28-day cycle, or `stillweek d3`.
/// The word is the default rotation; null when no year table covers today (first run, offline).
String? cycleChipText(EqPosition? p) {
  if (p == null) return null;
  const rotation = ['plant', 'push', 'climb', 'reap', 'dig', 'weave', 'mend', 'scout', 'scale', 'make', 'run', 'stock', 'audit'];
  if (p.stillweek) return 'stillweek d${p.stillweekDay}';
  return '${rotation[(p.cycle - 1).clamp(0, 12)]} d${p.day}/28';
}

/// Systems > Ops: `vm ok` when every engine is up, else `vm 2 down`; null before the first status.
String? opsChipText(dynamic opsStatusValue) {
  final engines = SystemsDash.enginesFrom(fmt.m(opsStatusValue));
  if (engines.isEmpty) return null;
  final down = engines.where((e) => !e.up).length;
  return down == 0 ? 'vm ok' : 'vm $down down';
}

/// Command: the cycle day, from the cached Equicycle year table. Opens Compass.
class CycleChipSource implements StatusChipSource {
  CycleChipSource(this.open, {EquicycleYears? years, DateTime Function()? clock})
      : _years = years ?? EquicycleYears.instance,
        _clock = clock ?? DateTime.now;
  final OpenStatusPage open;
  final EquicycleYears _years;
  final DateTime Function() _clock;

  @override
  Listenable get changes => _years;

  @override
  StatusChip? current(BuildContext context) {
    final text = cycleChipText(_years.positionFor(_clock()));
    if (text == null) return null;
    return StatusChip(text, (c) => open(c, 'Compass', const PlanningView()));
  }
}

/// Systems > Ops: `vm ok` or `vm N down`, from the cached ops status. It never fetches; the snapshot
/// is filled by the Systems landing and the Ops page. Opens Ops.
class OpsChipSource implements StatusChipSource {
  OpsChipSource(this.services, this.open);
  final AppServices services;
  final OpenStatusPage open;

  @override
  Listenable get changes => services.store.opsStatus;

  @override
  StatusChip? current(BuildContext context) {
    final text = opsChipText(services.store.opsStatus.value);
    if (text == null) return null;
    return StatusChip(text, (c) => open(c, 'Ops', const OpsView()));
  }
}

/// The default for every view: data freshness. Opens the Sync status page.
class FreshnessChipSource implements StatusChipSource {
  FreshnessChipSource(this.services, this.open, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;
  final AppServices services;
  final OpenStatusPage open;
  final DateTime Function() _clock;

  @override
  Listenable get changes => Listenable.merge([services.sync, services.outbox]);

  @override
  StatusChip? current(BuildContext context) => StatusChip(
        freshnessText(
          online: services.sync.online,
          pending: services.outbox.pending,
          lastSync: services.sync.lastFullSync,
          now: _clock(),
        ),
        (c) => open(c, 'Sync status', const SyncStatusView()),
      );
}

/// Systems > Backlog: `slate 298`, from the cached backlog snapshot. Opens the Backlog view.
class BacklogChipSource implements StatusChipSource {
  BacklogChipSource(this.services, this.open);
  final AppServices services;
  final OpenStatusPage open;

  @override
  Listenable get changes => services.store.backlog;

  @override
  StatusChip? current(BuildContext context) {
    final n = backlogRowCount(services.store.backlog.value);
    if (n == null) return null;
    return StatusChip('slate $n', (c) => open(c, 'Backlog', const BacklogView()));
  }
}

/// The chip a view shows: its own specific source if it has a chip, else the freshness default.
class ChipSelector implements StatusChipSource {
  ChipSelector(this.specific, this.fallback);
  final StatusChipSource? specific;
  final StatusChipSource fallback;

  @override
  Listenable get changes =>
      specific == null ? fallback.changes : Listenable.merge([specific!.changes, fallback.changes]);

  @override
  StatusChip? current(BuildContext context) => specific?.current(context) ?? fallback.current(context);
}

/// The chip, rendered after the title: ` · ` then the text in small monospace, secondary to the title.
class StatusChipLabel extends StatelessWidget {
  const StatusChipLabel({super.key, required this.source});
  final StatusChipSource source;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: source.changes,
      builder: (context, _) {
        final chip = source.current(context);
        if (chip == null) return const SizedBox.shrink();
        final text = chip.text.length > 18 ? '${chip.text.substring(0, 17)}…' : chip.text;
        return InkWell(
          onTap: () => chip.onTap(context),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 32),
            child: Align(
              alignment: Alignment.centerLeft,
              widthFactor: 1,
              child: Text(
                '  ·  $text',
                key: const Key('status-chip'),
                style: T.statusMono,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        );
      },
    );
  }
}

String _ago(DateTime? t, DateTime now) {
  if (t == null) return 'never';
  final d = now.difference(t);
  if (d.inSeconds < 90) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 48) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}

/// The page the freshness chip opens: connection, last sync per domain, queued writes and a Sync now button.
class SyncStatusView extends StatefulWidget {
  const SyncStatusView({super.key});

  @override
  State<SyncStatusView> createState() => _SyncStatusViewState();
}

class _SyncStatusViewState extends State<SyncStatusView> {
  List<Map<String, dynamic>> _queued = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadQueue());
  }

  Future<void> _loadQueue() async {
    final rows = await AppScope.of(context).db.pendingOutbox();
    if (mounted) setState(() => _queued = rows);
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final now = DateTime.now();
    return ListenableBuilder(
      listenable: Listenable.merge([services.sync, services.outbox]),
      builder: (context, _) {
        final sync = services.sync;
        final domains = services.store.snapshots.toList()..sort((a, b) => a.key.compareTo(b.key));
        return ListView(
          padding: const EdgeInsets.all(Sz.pad),
          children: [
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(sync.online ? 'Online' : 'Offline', style: T.w600(T.body2)),
                  const SizedBox(height: 4),
                  Text('Last full sync: ${_ago(sync.lastFullSync, now)}', style: T.small.copyWith(color: C.text2)),
                  if (sync.lastError != null) ...[
                    const SizedBox(height: 4),
                    Text(sync.lastError!, style: T.small.copyWith(color: C.amber)),
                  ],
                  const SizedBox(height: 10),
                  FilledButton(
                    key: const Key('sync-now'),
                    onPressed: sync.online && sync.phase == SyncPhase.idle
                        ? () async {
                            await sync.fullSync();
                            await _loadQueue();
                          }
                        : null,
                    child: Text(sync.phase == SyncPhase.idle ? 'Sync now' : 'Syncing'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const SectionLabel('Queued writes'),
            if (_queued.isEmpty)
              Text('Nothing is waiting.', style: T.small.copyWith(color: C.text3))
            else
              for (final r in _queued)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '${fmt.s(r['label'])} · ${fmt.s(r['status'])} · '
                    '${_ago(DateTime.fromMillisecondsSinceEpoch(fmt.i(r['created_at'])), now)}',
                    style: T.small.copyWith(color: C.text),
                  ),
                ),
            const SizedBox(height: 12),
            const SectionLabel('Last sync by domain'),
            if (domains.isEmpty)
              Text('No domain has been fetched yet.', style: T.small.copyWith(color: C.text3))
            else
              for (final s in domains)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Expanded(child: Text(s.key, style: T.monoSmall.copyWith(color: C.text2))),
                      Text(_ago(s.fetchedAt, now), style: T.monoSmall),
                    ],
                  ),
                ),
          ],
        );
      },
    );
  }
}
