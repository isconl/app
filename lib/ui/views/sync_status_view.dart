import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_scope.dart';
import '../../data/store.dart';
import '../../data/sync.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../widgets/common.dart';

/// Sync status page: lists the last sync time per domain, queued outbox writes
/// with their age, and a "Sync now" button.
class SyncStatusView extends StatefulWidget {
  const SyncStatusView({super.key});

  @override
  State<SyncStatusView> createState() => _SyncStatusViewState();
}

class _SyncStatusViewState extends State<SyncStatusView> {
  List<Map<String, dynamic>> _outboxItems = [];
  bool _outboxLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadOutbox();
  }

  Future<void> _loadOutbox() async {
    final services = AppScope.of(context);
    final items = await services.outbox.history();
    if (!mounted) return;
    setState(() {
      _outboxItems = items.where((i) => fmt.s(i['status']) != 'sent').toList();
      _outboxLoaded = true;
    });
  }

  static String _domainLabel(Snapshot snap) {
    return switch (snap.key) {
      'state' => 'Core state',
      'signals' => 'Signals',
      'day' => 'Day blocks',
      'notifications' => 'Notifications',
      'orientation' => 'Orientation',
      'jira' => 'Jira issues',
      'calendar' => 'Calendar events',
      'dates' => 'Key dates',
      'finance' => 'Finance summary',
      'journal' => 'Journal',
      'learning' => 'Study & courses',
      'circle' => 'Circle',
      'spaces' => 'Spaces',
      'plans' => 'Planning',
      'projects' => 'Projects',
      'portfolio' => 'Portfolio',
      'github' => 'GitHub snapshot',
      'ventures' => 'Ventures',
      'ideas' => 'Ideas',
      'rhythm' => 'Rhythm',
      'insights' => 'Insights',
      'decisions' => 'Decisions & Risks',
      'corporate' => 'Corporate',
      'wishlist' => 'Wishlist',
      'chatThreads' => 'Chat threads',
      'articles' => 'Articles',
      'buffer' => 'Buffer',
      'hostedServices' => 'Hosted services',
      'ops' => 'Ops status',
      'backlog' => 'Backlog',
      'audit' => 'Audit log',
      'refs' => 'References',
      'tags' => 'Tags',
      'dataHealth' => 'Data health',
      _ => snap.key,
    };
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([
        services.sync,
        services.outbox,
        ...services.store.syncSet,
      ]),
      builder: (context, _) {
        final sync = services.sync;
        final isBusy = sync.phase != SyncPhase.idle;
        final pending = services.outbox.pending;

        return RefreshIndicator(
          onRefresh: () async {
            if (sync.online) await sync.fullSync();
            await _loadOutbox();
          },
          color: C.green,
          backgroundColor: C.surface,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 96),
            children: [
              // Top control panel: Status line, online state, and Sync now button
              Panel(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        StatusDot(
                          sync.online ? C.green : C.red,
                          glow: sync.online,
                          size: 9,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          sync.online ? 'Online' : 'Offline',
                          style: T.headline.copyWith(fontSize: 16),
                        ),
                        const Spacer(),
                        FilledButton.icon(
                          onPressed: (sync.online && !isBusy)
                              ? () async {
                                  HapticFeedback.selectionClick();
                                  await sync.fullSync();
                                  await _loadOutbox();
                                }
                              : null,
                          icon: isBusy
                              ? const MiniSpinner(size: 14)
                              : const Icon(Icons.sync_rounded, size: 16),
                          label: Text(isBusy ? 'Syncing…' : 'Sync now'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      sync.statusLine,
                      style: T.body2.copyWith(color: C.text2),
                    ),
                    if (sync.lastFullSync != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Last full sync: ${fmt.ago(sync.lastFullSync!.toIso8601String())}',
                        style: T.monoSmall.copyWith(color: C.text3),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Queued outbox writes section
              SectionLabel(
                pending > 0
                    ? 'Queued Outbox Writes ($pending)'
                    : 'Queued Outbox Writes',
              ),
              Panel(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: !_outboxLoaded
                    ? const Center(child: MiniSpinner(size: 18))
                    : _outboxItems.isEmpty
                        ? Text(
                            pending == 0
                                ? 'No pending writes. All changes delivered.'
                                : '$pending waiting to deliver.',
                            style: T.body2.copyWith(color: C.text3),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (var i = 0; i < _outboxItems.length; i++) ...[
                                if (i > 0) const Divider(height: 12),
                                _outboxItemRow(services, _outboxItems[i]),
                              ],
                            ],
                          ),
              ),
              const SizedBox(height: 18),

              // Domains section
              const SectionLabel('Cached Domains'),
              Panel(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    for (var i = 0; i < services.store.syncSet.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      _domainRow(services.store.syncSet[i]),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _outboxItemRow(AppServices services, Map<String, dynamic> item) {
    final status = fmt.s(item['status']);
    final created = item['created_at'];
    final ageStr = created != null
        ? fmt.ago(
            DateTime.fromMillisecondsSinceEpoch(fmt.i(created))
                .toIso8601String(),
          )
        : '';
    final label = fmt.s(item['label']).isNotEmpty
        ? fmt.s(item['label'])
        : '${fmt.s(item['method'])} ${fmt.s(item['path'])}';
    final (color, icon) = switch (status) {
      'failed' => (C.red, Icons.error_rounded),
      _ => (C.amber, Icons.schedule_rounded),
    };

    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: T.small.copyWith(color: C.text)),
              const SizedBox(height: 2),
              Text(
                [status, ageStr, if (fmt.s(item['error']).isNotEmpty) fmt.s(item['error'])].join(' · '),
                style: T.monoSmall.copyWith(
                  color: status == 'failed' ? C.red : C.text3,
                ),
              ),
            ],
          ),
        ),
        if (status == 'failed')
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 18),
            onPressed: () async {
              await services.outbox.retry(fmt.i(item['id']));
              if (services.sync.online) await services.sync.fullSync();
              await _loadOutbox();
            },
          ),
      ],
    );
  }

  Widget _domainRow(Snapshot snap) {
    final fetched = snap.fetchedAt;
    final ageStr = fetched != null ? fmt.ago(fetched.toIso8601String()) : 'Not synced';
    final label = _domainLabel(snap);

    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        snap.refresh();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: T.w500(T.body2)),
                  const SizedBox(height: 2),
                  Text(snap.path, style: T.monoSmall.copyWith(color: C.text3)),
                ],
              ),
            ),
            if (snap.loading)
              const MiniSpinner(size: 14)
            else ...[
              Text(
                ageStr,
                style: T.monoSmall.copyWith(
                  color: snap.error != null ? C.red : C.text2,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.refresh_rounded, size: 14, color: C.text3),
            ],
          ],
        ),
      ),
    );
  }
}
