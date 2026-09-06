import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../widgets/common.dart';

/// BN26090609: a real chat interface -- WhatsApp/Signal-style. This screen
/// is the conversation list (one row per sender, grouped by PERSON_ID);
/// tapping one opens [InboxThreadView], that sender's messages only, as
/// chat bubbles. `scope/inbox.tsv` already carries PERSON_ID/CHANNEL/
/// DIRECTION/timestamps per message (BM26090503's chat-import work writes
/// exactly this shape) -- grouping is client-side over the same `/api/state`
/// feed this screen already read as a flat list, no backend change needed.
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
            final people = fmt.lm(fmt.m(services.store.circle.value)['people']);
            final nameFor = {for (final p in people) fmt.s(p['ID']): fmt.s(p['NAME'])};

            // Thread key: PERSON_ID when present, else the raw SENDER text,
            // else CHANNEL -- a message never vanishes from the list just
            // because it predates PERSON_ID being populated on every row.
            final Map<String, List<Map<String, dynamic>>> byThread = {};
            for (final item in feed) {
              final key = _threadKey(item);
              byThread.putIfAbsent(key, () => []).add(item);
            }
            final threads = byThread.entries.map((e) {
              final msgs = [...e.value]
                ..sort((a, b) => fmt.s(b['RECEIVED']).compareTo(fmt.s(a['RECEIVED'])));
              return (key: e.key, msgs: msgs, latest: msgs.first);
            }).toList()
              ..sort((a, b) =>
                  fmt.s(b.latest['RECEIVED']).compareTo(fmt.s(a.latest['RECEIVED'])));

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final t in threads)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _ConversationTile(
                      threadKey: t.key,
                      name: nameFor[t.key] ??
                          (fmt.s(t.latest['SENDER']).isNotEmpty
                              ? fmt.s(t.latest['SENDER'])
                              : fmt.s(t.latest['CHANNEL'])),
                      latest: t.latest,
                      unread: t.msgs.where((m) => fmt.s(m['STATUS']) == 'new').length,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => InboxThreadView(
                            title: nameFor[t.key] ??
                                (fmt.s(t.latest['SENDER']).isNotEmpty
                                    ? fmt.s(t.latest['SENDER'])
                                    : fmt.s(t.latest['CHANNEL'])),
                            messages: t.msgs,
                          ),
                        ),
                      ),
                    ),
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
            shape: const CircleBorder(),
            onPressed: () => _captureSheet(context),
            child: const Icon(Icons.add_rounded),
          ),
        ),
      ],
    );
  }

  static String _threadKey(Map<String, dynamic> item) {
    final personId = fmt.s(item['PERSON_ID']);
    if (personId.isNotEmpty && personId != '-') return personId;
    final sender = fmt.s(item['SENDER']);
    if (sender.isNotEmpty && sender != '-') return 'sender:$sender';
    return 'channel:${fmt.s(item['CHANNEL'])}';
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

/// One row in the conversation list: sender name, latest-message preview,
/// timestamp, unread count -- matches WhatsApp/Signal's own list
/// convention, per Sconl's explicit ask.
class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.threadKey,
    required this.name,
    required this.latest,
    required this.unread,
    required this.onTap,
  });

  final String threadKey;
  final String name;
  final Map<String, dynamic> latest;
  final int unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final preview = fmt.s(latest['TITLE']).isNotEmpty
        ? fmt.s(latest['TITLE'])
        : fmt.s(latest['BODY']);
    return Panel(
      padding: const EdgeInsets.all(12),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(color: C.surface, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: T.w600(T.body).copyWith(color: C.text2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(name.isEmpty ? 'Unknown' : name,
                          style: T.w600(T.body2), overflow: TextOverflow.ellipsis),
                    ),
                    Text(fmt.ago(latest['RECEIVED']), style: T.monoSmall),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Expanded(
                      child: Text(preview,
                          style: T.body2.copyWith(color: C.text2),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (unread > 0) ...[
                      const SizedBox(width: 6),
                      Badge2('$unread', color: C.greenDim, textColor: Colors.white),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Thread view: one conversation, chronological, chat bubbles -- inbound
/// (DIRECTION != 'out') left-aligned/surface-colored, outbound right-
/// aligned/green, same visual language chat-import already tags messages
/// with (`m.direction`, circle/lib/chat-import.js).
class InboxThreadView extends StatelessWidget {
  const InboxThreadView({super.key, required this.title, required this.messages});
  final String title;
  final List<Map<String, dynamic>> messages;

  @override
  Widget build(BuildContext context) {
    // Oldest first for a thread read top-to-bottom, the inverse of the
    // conversation list's newest-first ordering.
    final chrono = [...messages]
      ..sort((a, b) => fmt.s(a['RECEIVED']).compareTo(fmt.s(b['RECEIVED'])));
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        itemCount: chrono.length,
        itemBuilder: (context, i) => _Bubble(item: chrono[i]),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.item});
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final id = fmt.s(item['ID']);
    final outbound = fmt.s(item['DIRECTION']) == 'out';
    final text = fmt.s(item['BODY']).isEmpty ? fmt.s(item['TITLE']) : fmt.s(item['BODY']);
    return GestureDetector(
      onLongPress: () => _actions(context, services, id),
      child: Align(
        alignment: outbound ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
          decoration: BoxDecoration(
            color: outbound ? C.greenDim : C.surface,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(Sz.rMd),
              topRight: const Radius.circular(Sz.rMd),
              bottomLeft: Radius.circular(outbound ? Sz.rMd : 2),
              bottomRight: Radius.circular(outbound ? 2 : Sz.rMd),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (text.isNotEmpty)
                Text(text,
                    style: T.body2.copyWith(color: outbound ? Colors.white : C.text)),
              const SizedBox(height: 4),
              Text(fmt.ago(item['RECEIVED']),
                  style: T.monoSmall.copyWith(
                      color: outbound ? Colors.white70 : C.text3, fontSize: 9.5)),
            ],
          ),
        ),
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
