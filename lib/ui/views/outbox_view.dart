import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../widgets/common.dart';

/// Queued offline writes: what is waiting, what failed, what was delivered.
class OutboxView extends StatefulWidget {
  const OutboxView({super.key});

  @override
  State<OutboxView> createState() => _OutboxViewState();
}

class _OutboxViewState extends State<OutboxView> {
  List<Map<String, dynamic>> _items = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final services = AppScope.of(context);
    final items = await services.outbox.history();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return ListenableBuilder(
      listenable: services.outbox,
      builder: (context, _) {
        return RefreshIndicator(
          onRefresh: () async {
            if (services.sync.online) await services.sync.fullSync();
            await _load();
          },
          color: C.green,
          backgroundColor: C.surface,
          child: !_loaded
              ? const Center(child: MiniSpinner(size: 20))
              : _items.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        EmptyState(
                          'Outbox empty',
                          'Changes you make while offline queue here, then '
                              'deliver to the agent and on to OneDrive.',
                          icon: Icons.outbox_rounded,
                        ),
                      ],
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 96),
                      itemCount: _items.length + 1,
                      itemBuilder: (context, idx) {
                        if (idx == 0) {
                          final pending = services.outbox.pending;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Panel(
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      pending == 0
                                          ? 'All changes delivered.'
                                          : '$pending waiting to deliver.',
                                      style: T.body2,
                                    ),
                                  ),
                                  if (pending > 0 && services.sync.online)
                                    FilledButton(
                                      onPressed: () async {
                                        await services.sync.fullSync();
                                        await _load();
                                      },
                                      child: const Text('Deliver now'),
                                    ),
                                ],
                              ),
                            ),
                          );
                        }
                        final item = _items[idx - 1];
                        return _tile(services, item);
                      },
                    ),
        );
      },
    );
  }

  Widget _tile(AppServices services, Map<String, dynamic> item) {
    final status = fmt.s(item['status']);
    final (color, icon) = switch (status) {
      'sent' => (C.green, Icons.check_circle_rounded),
      'failed' => (C.red, Icons.error_rounded),
      _ => (C.amber, Icons.schedule_rounded),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Panel(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(fmt.s(item['label']), style: T.small),
                  const SizedBox(height: 2),
                  Text(
                    [
                      status,
                      fmt.ago(DateTime.fromMillisecondsSinceEpoch(
                              fmt.i(item['created_at']))
                          .toIso8601String()),
                      if (fmt.s(item['error']).isNotEmpty)
                        fmt.s(item['error']),
                    ].join(' · '),
                    style: T.monoSmall.copyWith(
                        color: status == 'failed' ? C.red : C.text3),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (status == 'failed') ...[
              IconButton(
                icon: const Icon(Icons.refresh_rounded,
                    size: 18, color: C.text2),
                onPressed: () async {
                  await services.outbox.retry(fmt.i(item['id']));
                  if (services.sync.online) await services.sync.fullSync();
                  await _load();
                },
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded,
                    size: 18, color: C.text3),
                onPressed: () async {
                  final sure = await confirmDialog(
                      context,
                      'Discard queued change?',
                      '"${fmt.s(item['label'])}" will never be delivered.',
                      action: 'Discard',
                      destructive: true);
                  if (!sure) return;
                  await services.outbox.discard(fmt.i(item['id']));
                  await _load();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
