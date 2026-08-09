import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../widgets/common.dart';

/// Captured messages from every channel. The share sheet feeds this too.
class InboxView extends StatelessWidget {
  const InboxView({super.key});

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return Stack(
      children: [
        SnapshotView(
          snapshot: services.store.state,
          builder: (context, data) {
            final feed = fmt.lm(fmt.m(data)['feed']);
            if (feed.isEmpty) {
              return const EmptyState(
                'Inbox zero',
                'Share any text into iSconl from another app, or capture '
                    'a note below - it lands here and syncs to the vault.',
                icon: Icons.inbox_rounded,
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final item in feed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _InboxTile(item: item),
                  ),
              ],
            );
          },
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            backgroundColor: C.greenDim,
            foregroundColor: Colors.white,
            onPressed: () => _captureSheet(context),
            child: const Icon(Icons.add_rounded),
          ),
        ),
      ],
    );
  }

  Future<void> _captureSheet(BuildContext context) {
    final body = TextEditingController();
    final title = TextEditingController();
    final services = AppScope.of(context);
    return showFormSheet(
      context,
      title: 'Capture',
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Field(
              label: 'Note',
              controller: body,
              maxLines: 5,
              autofocus: true,
              hint: 'Anything - the agent will annotate and file it.'),
          Field(label: 'Title (optional)', controller: title),
          FilledButton(
            onPressed: () async {
              if (body.text.trim().isEmpty) return;
              Navigator.pop(ctx);
              final res = await services.mutations.addInbox(
                body: body.text.trim(),
                title: title.text.trim(),
                channel: 'mobile',
              );
              if (!context.mounted) return;
              if (!res.ok) {
                toast(context, res.error!, error: true);
              } else {
                toast(
                    context,
                    res.queued
                        ? 'Captured - queued for sync'
                        : 'Captured to inbox');
              }
            },
            child: const Text('Capture'),
          ),
        ],
      ),
    );
  }
}

class _InboxTile extends StatelessWidget {
  const _InboxTile({required this.item});
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final id = fmt.s(item['ID']);
    final status = fmt.s(item['STATUS']);
    return Panel(
      padding: const EdgeInsets.all(12),
      onLongPress: () => _actions(context, services, id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Badge2(fmt.s(item['CHANNEL']),
                  color: C.surface, textColor: C.text3),
              const SizedBox(width: 6),
              if (fmt.s(item['TAG']).isNotEmpty) Badge2(fmt.s(item['TAG'])),
              if (status.isNotEmpty && status != 'new') ...[
                const SizedBox(width: 6),
                Badge2(status,
                    color: status == 'done' ? C.greenBg : C.surface,
                    textColor: status == 'done' ? C.green : C.text3),
              ],
              const Spacer(),
              Text(fmt.ago(item['RECEIVED']), style: T.monoSmall),
            ],
          ),
          const SizedBox(height: 8),
          if (fmt.s(item['TITLE']).isNotEmpty) ...[
            Text(fmt.s(item['TITLE']), style: T.w600(T.body2)),
            const SizedBox(height: 3),
          ],
          Text(fmt.s(item['BODY']),
              style: T.body2.copyWith(color: C.text2),
              maxLines: 6,
              overflow: TextOverflow.ellipsis),
          if (fmt.s(item['SENDER']).isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('from ${fmt.s(item['SENDER'])}', style: T.monoSmall),
          ],
          if (fmt.s(item['AI_NOTE']).isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: C.greenBg2,
                borderRadius: BorderRadius.circular(Sz.rSm),
                border:
                    Border.all(color: C.greenDim.withValues(alpha: 0.35)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.auto_awesome_rounded,
                      size: 13, color: C.greenBright),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(fmt.s(item['AI_NOTE']),
                          style: T.small.copyWith(color: C.text2))),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _actions(BuildContext context, AppServices services, String id) {
    showModalBottomSheet(
      context: context,
      backgroundColor: C.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Sz.rXl)),
        side: BorderSide(color: C.border),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            for (final (label, status, icon) in [
              ('Mark done', 'done', Icons.check_rounded),
              ('Keep for later', 'kept', Icons.bookmark_rounded),
              ('Archive', 'archived', Icons.archive_rounded),
            ])
              ListTile(
                dense: true,
                leading: Icon(icon, size: 18),
                title: Text(label, style: T.body2),
                onTap: () async {
                  Navigator.pop(ctx);
                  final res = await services.mutations
                      .inboxUpdate(id, status: status);
                  if (!context.mounted) return;
                  if (!res.ok) toast(context, res.error!, error: true);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
