import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../widgets/common.dart';
import 'channels_dash_model.dart';
import 'channels_dashboard.dart';
import 'circle.dart' show PersonScreen;
import '../../util/snooze.dart';
import 'inbox_swipe.dart';
import 'inbox_threads.dart';

/// BI26092641: the Inbox is a people list, one row per person with every channel merged into one thread.
/// Tapping a person opens [InboxThreadView], the conversation as chat bubbles. Senders with no person yet
/// sit under Unknown, with Link to person and Create person. The grouping and the display rules live in
/// inbox_threads.dart so they are tested without a widget.
class InboxView extends StatefulWidget {
  const InboxView({super.key, this.onOpenView});

  /// Opens the Channels sub-tab that holds a nav view (jira, social, github, teams).
  final void Function(String view)? onOpenView;

  @override
  State<InboxView> createState() => _InboxViewState();
}

class _InboxViewState extends State<InboxView> {
  final _scroll = ScrollController();
  bool _pinned = false;

  /// Threads swiped away this session, hidden at once so the dismissed row leaves the tree
  /// before the server round-trip lands. Undo takes a key back out.
  final _hidden = <String>{};

  @override
  void initState() {
    super.initState();
    SnoozeStore.instance.addListener(_onSnooze);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) SnoozeStore.instance.ensureLoaded(AppScope.of(context).db);
    });
    _scroll.addListener(() {
      final past = _scroll.hasClients && _scroll.offset > 360;
      if (past != _pinned) setState(() => _pinned = past);
    });
  }

  void _onSnooze() {
    if (mounted) setState(() {});
  }

  /// Marks every open message in the thread done, and offers an undo that restores each status.
  void _done(BuildContext context, AppServices services, InboxThread t) {
    final prior = <String, String>{
      for (final m in t.messages)
        if (fmt.s(m['STATUS']) != 'done' && messageKind(m) != MessageKind.system) fmt.s(m['ID']): fmt.s(m['STATUS']),
    };
    setState(() => _hidden.add(t.key));
    for (final id in prior.keys) {
      services.mutations.inboxUpdate(id, status: 'done');
    }
    showUndoBar(context, 'Marked done', () {
      setState(() => _hidden.remove(t.key));
      for (final e in prior.entries) {
        services.mutations.inboxUpdate(e.key, status: e.value.isEmpty ? 'new' : e.value);
      }
    });
  }

  void _snooze(BuildContext context, AppServices services, InboxThread t, SnoozeChoice c) {
    setState(() => _hidden.add(t.key));
    SnoozeStore.instance.snooze(t.key, c.until, services.db);
    showUndoBar(context, 'Snoozed until ${c.label.toLowerCase()}', () {
      setState(() => _hidden.remove(t.key));
      SnoozeStore.instance.unsnooze(t.key, services.db);
    });
  }

  Widget _swipe(BuildContext context, AppServices services, InboxThread t, Widget tile) => SwipeThread(
        key: ValueKey('swipe-${t.key}'),
        onDone: () => _done(context, services, t),
        chooseSnooze: () => showSnoozeSheet(context, DateTime.now()),
        onSnooze: (c) => _snooze(context, services, t, c),
        child: tile,
      );

  @override
  void dispose() {
    SnoozeStore.instance.removeListener(_onSnooze);
    _scroll.dispose();
    super.dispose();
  }

  ChannelsDash _dash(AppServices services, List<Map<String, dynamic>> feed) => ChannelsDash.from(
        feed: feed,
        jiraIssues: fmt.lm(fmt.m(services.store.jira.value)['issues']),
        buffer: fmt.m(services.store.buffer.value),
        now: DateTime.now(),
      );

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return Stack(
      children: [
        SnapshotView(
          snapshot: services.store.state,
          controller: _scroll,
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
            final personById = {for (final p in people) fmt.s(p['ID']): p};
            final groups = groupThreads(feed);
            final snoozeNow = DateTime.now();
            bool shown(InboxThread t) =>
                !_hidden.contains(t.key) &&
                !SnoozeStore.instance.isSnoozed(t.key, snoozeNow) &&
                !t.messages.where((m) => messageKind(m) != MessageKind.system).every((m) => fmt.s(m['STATUS']) == 'done');
            final now = DateTime.now();

            String nameOf(InboxThread t) {
              final p = personById[t.key];
              final n = p == null ? '' : fmt.s(p['NAME']);
              if (n.isNotEmpty && n != '-') return n;
              final sender = fmt.s(t.latest['SENDER']);
              return sender.isNotEmpty && sender != '-' ? sender : sourceLabel(fmt.s(t.latest['CHANNEL']));
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListenableBuilder(
                  listenable: Listenable.merge([services.store.jira, services.store.buffer]),
                  builder: (context, _) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: ChannelsDashboard(dash: _dash(services, feed), onOpenView: widget.onOpenView),
                  ),
                ),
                for (final t in groups.people.where(shown))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _swipe(context, services, t, ConversationTile(
                      name: nameOf(t),
                      latest: t.latest,
                      unread: t.unread,
                      now: now,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => InboxThreadView(
                            title: nameOf(t),
                            messages: t.messages,
                            person: personById[t.key],
                          ),
                        ),
                      ),
                    )),
                  ),
                if (groups.unknown.where(shown).isNotEmpty) ...[
                  const SectionLabel('Unknown'),
                  for (final t in groups.unknown.where(shown))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _swipe(context, services, t, _UnknownTile(thread: t, name: nameOf(t), now: now, people: people)),
                    ),
                ],
              ],
            );
          },
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: ListenableBuilder(
            listenable: Listenable.merge([services.store.state, services.store.jira, services.store.buffer]),
            builder: (context, _) => ChannelsSummaryBar(
              dash: _dash(services, fmt.lm(fmt.m(services.store.state.value)['feed'])),
              visible: _pinned,
            ),
          ),
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

IconData sourceIcon(String channel) => switch (channel.toLowerCase()) {
      'whatsapp' => Icons.chat_rounded,
      'telegram' => Icons.send_rounded,
      'signal' => Icons.shield_rounded,
      'email' || 'gmail' || 'outlook' => Icons.mail_rounded,
      _ => Icons.edit_note_rounded,
    };

/// One row in the people list: initials avatar, name, a one-line preview, the last message's source icon,
/// the time in monospace and an unread badge.
class ConversationTile extends StatelessWidget {
  const ConversationTile({
    super.key,
    required this.name,
    required this.latest,
    required this.unread,
    required this.onTap,
    required this.now,
  });

  final String name;
  final Map<String, dynamic> latest;
  final int unread;
  final VoidCallback onTap;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final preview = messageText(latest);
    final channel = fmt.s(latest['CHANNEL']);
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
                    Icon(sourceIcon(channel), key: const Key('tile-source'), size: 12, color: C.text3),
                    const SizedBox(width: 5),
                    Text(listTime(latest, now), key: const Key('tile-time'), style: T.monoSmall),
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

/// An unlinked sender: opens read-only, and offers Link to person and Create person when circle has the handle.
class _UnknownTile extends StatelessWidget {
  const _UnknownTile({required this.thread, required this.name, required this.now, required this.people});
  final InboxThread thread;
  final String name;
  final DateTime now;
  final List<Map<String, dynamic>> people;

  Map<String, dynamic>? _handle(AppServices services) {
    final sender = fmt.s(thread.latest['SENDER']);
    for (final u in fmt.lm(fmt.m(services.store.inboxUnknown.value)['unknown'])) {
      if (fmt.s(u['sender']) == sender || fmt.s(u['value']) == sender) return u;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return ListenableBuilder(
      listenable: services.store.inboxUnknown,
      builder: (context, _) {
        final handle = _handle(services);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConversationTile(
              name: name,
              latest: thread.latest,
              unread: thread.unread,
              now: now,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => InboxThreadView(title: name, messages: thread.messages)),
              ),
            ),
            if (handle != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    TextButton(
                      key: const Key('unknown-link'),
                      onPressed: () => _linkSheet(context, services, handle),
                      child: const Text('Link to person'),
                    ),
                    TextButton(
                      key: const Key('unknown-create'),
                      onPressed: () => _create(context, services, handle),
                      child: const Text('Create person'),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _linkSheet(BuildContext context, AppServices services, Map<String, dynamic> handle) {
    final sorted = [...people]..sort((a, b) => fmt.s(a['NAME']).compareTo(fmt.s(b['NAME'])));
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: C.panel,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final p in sorted)
                ListTile(
                  dense: true,
                  title: Text(fmt.s(p['NAME']).isEmpty || fmt.s(p['NAME']) == '-' ? fmt.s(p['ID']) : fmt.s(p['NAME']), style: T.body2),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final res = await services.mutations.inboxLinkUnknown(
                      kind: fmt.s(handle['kind']),
                      value: fmt.s(handle['value']),
                      personId: fmt.s(p['ID']),
                    );
                    if (!context.mounted) return;
                    toast(context, res.ok ? 'Linked' : res.error!, error: !res.ok);
                    if (res.ok) services.store.inboxUnknown.refresh();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _create(BuildContext context, AppServices services, Map<String, dynamic> handle) {
    final nameCtl = TextEditingController(text: fmt.s(handle['sender']));
    return showFormSheet(
      context,
      title: 'Create person',
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Field(label: 'Name', controller: nameCtl, autofocus: true),
          FilledButton(
            onPressed: () async {
              final name = nameCtl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              final res = await services.mutations.inboxCreateUnknown(
                kind: fmt.s(handle['kind']),
                value: fmt.s(handle['value']),
                name: name,
              );
              if (!context.mounted) return;
              toast(context, res.ok ? 'Created $name' : res.error!, error: !res.ok);
              if (res.ok) {
                services.store.inboxUnknown.refresh();
                services.store.circle.refresh();
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

/// One conversation as chat bubbles, oldest at the top, opening on the newest message. Own messages sit on
/// the right in green, theirs on the left; each bubble carries its time and a source badge, and a day
/// separator marks each new day. Opening it marks the unread messages seen (queued, so it works offline).
class InboxThreadView extends StatefulWidget {
  const InboxThreadView({super.key, required this.title, required this.messages, this.person});
  final String title;
  final List<Map<String, dynamic>> messages;

  /// The person's circle row, when linked: the title opens their dossier.
  final Map<String, dynamic>? person;

  @override
  State<InboxThreadView> createState() => _InboxThreadViewState();
}

class _InboxThreadViewState extends State<InboxThreadView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final services = AppScope.of(context);
      var n = 0;
      for (final m in widget.messages) {
        if (fmt.s(m['STATUS']) != 'new' || fmt.s(m['DIRECTION']) == 'out' || n >= 50) continue;
        n++;
        services.mutations.inboxUpdate(fmt.s(m['ID']), status: 'seen');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final rows = threadRows(widget.messages);
    final now = DateTime.now();
    // Built oldest first, then reversed into a reverse list, so the newest message is what the screen opens on.
    final items = <Widget>[];
    DateTime? lastDay;
    for (final r in rows) {
      final t = r.time;
      if (t != null) {
        final day = DateTime(t.year, t.month, t.day);
        if (lastDay != day) {
          items.add(_DaySeparator(dayLabel(day, now)));
          lastDay = day;
        }
      }
      items.add(Bubble(row: r));
    }
    final person = widget.person;
    return Scaffold(
      appBar: AppBar(
        title: person == null
            ? Text(widget.title)
            : InkWell(
                key: const Key('thread-title'),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PersonScreen(person: person))),
                child: Text(widget.title),
              ),
      ),
      body: rows.isEmpty
          ? const EmptyState('No messages', 'Only platform notices in this thread.', icon: Icons.chat_bubble_outline_rounded)
          : ListView(
              reverse: true,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: items.reversed.toList(),
            ),
    );
  }
}

class _DaySeparator extends StatelessWidget {
  const _DaySeparator(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Center(child: Text(label, key: const Key('day-separator'), style: T.monoSmall.copyWith(color: C.text3))),
      );
}

class Bubble extends StatelessWidget {
  const Bubble({super.key, required this.row});
  final ThreadRow row;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final item = row.message;
    final id = fmt.s(item['ID']);
    final outbound = row.outbound;
    final channel = fmt.s(item['CHANNEL']);
    final text = messageText(item);
    final subject = isEmailChannel(channel) ? fmt.s(item['TITLE']).isNotEmpty ? fmt.s(item['TITLE']) : fmt.s(item['SUBJECT']) : '';
    final fg = outbound ? Colors.white : C.text;
    final soft = outbound ? Colors.white70 : C.text3;
    final links = {...linksIn(text), ...row.extraLinks}.toList();
    return GestureDetector(
      onLongPress: () => _actions(context, services, id),
      child: Align(
        alignment: outbound ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          key: Key(outbound ? 'bubble-out' : 'bubble-in'),
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
              if (subject.isNotEmpty && subject != text)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(subject, key: const Key('bubble-subject'), style: T.w600(T.body2).copyWith(color: fg)),
                ),
              if (text.isNotEmpty) Text(text, style: T.body2.copyWith(color: fg)),
              for (final url in links)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: InkWell(
                    onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
                    child: Container(
                      key: const Key('link-card'),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(Sz.rSm),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.link_rounded, size: 13, color: soft),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(Uri.tryParse(url)?.host ?? url,
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: T.small.copyWith(color: fg)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(sourceIcon(channel), key: const Key('bubble-source'), size: 10, color: soft),
                  const SizedBox(width: 4),
                  Text(sourceLabel(channel), style: T.monoSmall.copyWith(color: soft, fontSize: 9.5)),
                  const SizedBox(width: 8),
                  Text(clockOf(item), key: const Key('bubble-time'), style: T.monoSmall.copyWith(color: soft, fontSize: 9.5)),
                ],
              ),
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
                  final res = await services.mutations.inboxUpdate(id, status: status);
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
