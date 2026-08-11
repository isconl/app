import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../widgets/common.dart';

/// The Buffer desk: which channels exist, what is queued, what went out.
///
/// Publishing to the outside world is exactly the class of action the
/// constitution keeps behind a deliberate, online, confirmed gate - not a
/// thumb on a phone, which is why [compose] defaults to false and the mobile
/// Shell never passes true. The desktop web console IS the web desk the
/// original "composing stays on the web desk" comment meant, so
/// [DesktopShell] passes compose: true and gets the real control desk:
/// post, pause/resume channels, edit/delete/move queued posts.
class BufferView extends StatelessWidget {
  const BufferView({super.key, this.compose = false});
  final bool compose;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return SnapshotView(
      snapshot: services.store.buffer,
      builder: (context, data) {
        final map = fmt.m(data);

        if (fmt.b(map['connected']) == false) {
          return EmptyState(
            'Buffer is not connected',
            fmt.s(map['error']).isEmpty
                ? 'Add the Buffer access token in Settings on the web dashboard.'
                : fmt.s(map['error']),
            icon: Icons.share_rounded,
          );
        }

        final channels = fmt.lm(map['channels']);
        final queue = fmt.lm(map['queue']);
        final sent = fmt.lm(map['sent']);
        final rateHeld = fmt.b(map['rateHeld']);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (rateHeld)
              Panel(
                color: C.amberBg,
                borderColor: C.amber.withValues(alpha: 0.4),
                margin: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Icon(Icons.speed_rounded, size: 15, color: C.amber),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Holding under the Buffer rate limit. Showing the last '
                        'known channels.',
                        style: T.small.copyWith(color: C.amber),
                      ),
                    ),
                  ],
                ),
              ),

            if (compose) ...[
              _Composer(channels: channels),
              const SizedBox(height: 4),
            ],

            SectionLabel('Channels · ${channels.length}'),
            if (channels.isEmpty)
              const EmptyState('No channels', 'Nothing connected in Buffer yet.',
                  icon: Icons.link_off_rounded)
            else
              ...channels.map((c) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _ChannelTile(channel: c, compose: compose),
                  )),

            SectionLabel('Queued · ${queue.length}'),
            if (queue.isEmpty)
              const EmptyState('Queue is empty',
                  'Nothing scheduled to go out.', icon: Icons.schedule_rounded)
            else
              ...queue.take(25).map((p) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _PostTile(post: p, upcoming: true, compose: compose),
                  )),

            if (sent.isNotEmpty) ...[
              SectionLabel('Sent · ${sent.length}'),
              ...sent.take(15).map((p) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _PostTile(post: p, upcoming: false, compose: false),
                  )),
            ],
          ],
        );
      },
    );
  }
}

/// Text + channel multi-select + optional schedule time, posting via
/// POST /api/buffer/post (legacy-routed; see isconl-agent/server.js's
/// createPost mutation, one call per selected channel).
class _Composer extends StatefulWidget {
  const _Composer({required this.channels});
  final List<Map<String, dynamic>> channels;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final _text = TextEditingController();
  final _selected = <String>{};
  DateTime? _scheduleAt;
  bool _busy = false;

  int get _limit {
    // Strictest of the selected channels' limits, mirroring the dashboard's
    // composer meter. Twitter/X's 280 is the tightest Buffer supports;
    // everything else is materially longer, so it's a safe universal floor.
    final services = widget.channels
        .where((c) => _selected.contains(fmt.s(c['id'])))
        .map((c) => fmt.s(c['service']).toLowerCase());
    if (services.any((s) => s == 'twitter' || s == 'x')) return 280;
    return 3000;
  }

  Future<void> _post() async {
    final text = _text.text.trim();
    if (text.isEmpty || _selected.isEmpty || _busy) return;
    final services = AppScope.of(context);
    setState(() => _busy = true);
    try {
      final res = await services.mutations.post('/api/buffer/post', {
        'text': text,
        'profileIds': _selected.toList(),
        if (_scheduleAt != null) 'scheduledAt': _scheduleAt!.toIso8601String(),
      });
      if (!mounted) return;
      final map = fmt.m(res);
      final results = fmt.lm(map['results']);
      final ok = results.where((r) => r['id'] != null).length;
      if (map['success'] == true) {
        toast(context, '$ok/${results.length} channel(s) posted');
        _text.clear();
        setState(() {
          _selected.clear();
          _scheduleAt = null;
        });
        services.store.buffer.refresh();
      } else {
        final err = results
            .map((r) => fmt.s(r['error']))
            .firstWhere((e) => e.isNotEmpty, orElse: () => 'Post failed');
        toast(context, err, error: true);
      }
    } catch (e) {
      if (mounted) toast(context, 'Post failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final over = _text.text.length > _limit;
    return Panel(
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionLabel('Compose', padding: EdgeInsets.only(bottom: 6)),
          TextField(
            controller: _text,
            maxLines: 4,
            minLines: 2,
            style: T.body2.copyWith(color: C.text),
            decoration: const InputDecoration(hintText: "What's happening?"),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: Text('${_text.text.length}/$_limit',
                style: T.monoSmall.copyWith(color: over ? C.red : C.text3)),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in widget.channels)
                Pill(
                  fmt.s(c['displayName']).isEmpty
                      ? fmt.s(c['name'])
                      : fmt.s(c['displayName']),
                  selected: _selected.contains(fmt.s(c['id'])),
                  onTap: () => setState(() {
                    final id = fmt.s(c['id']);
                    _selected.contains(id)
                        ? _selected.remove(id)
                        : _selected.add(id);
                  }),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              TextButton.icon(
                onPressed: () async {
                  final now = DateTime.now();
                  final date = await showDatePicker(
                    context: context,
                    initialDate: _scheduleAt ?? now,
                    firstDate: now,
                    lastDate: now.add(const Duration(days: 365)),
                  );
                  if (date == null || !context.mounted) return;
                  final time = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(_scheduleAt ?? now),
                  );
                  if (time == null) return;
                  setState(() => _scheduleAt = DateTime(
                      date.year, date.month, date.day, time.hour, time.minute));
                },
                icon: const Icon(Icons.schedule_rounded, size: 15),
                label: Text(_scheduleAt == null
                    ? 'Add to queue'
                    : 'At ${fmt.shortDate(_scheduleAt!.toIso8601String())}'),
              ),
              if (_scheduleAt != null)
                IconButton(
                  tooltip: 'Clear schedule (queue immediately)',
                  icon: const Icon(Icons.close_rounded, size: 16),
                  onPressed: () => setState(() => _scheduleAt = null),
                ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _text.text.trim().isEmpty ||
                        _selected.isEmpty ||
                        over ||
                        _busy
                    ? null
                    : _post,
                icon: _busy
                    ? const MiniSpinner()
                    : const Icon(Icons.send_rounded, size: 15),
                label: const Text('Post'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({required this.channel, this.compose = false});
  final Map<String, dynamic> channel;
  final bool compose;

  static IconData _icon(String service) => switch (service.toLowerCase()) {
        'twitter' || 'x' => Icons.alternate_email_rounded,
        'linkedin' => Icons.business_center_rounded,
        'facebook' => Icons.thumb_up_rounded,
        'instagram' => Icons.photo_camera_rounded,
        'mastodon' => Icons.forum_rounded,
        'threads' => Icons.tag_rounded,
        _ => Icons.public_rounded,
      };

  Future<void> _togglePause(BuildContext context) async {
    final services = AppScope.of(context);
    final paused = fmt.b(channel['isQueuePaused']);
    final sure = await confirmDialog(
      context,
      paused ? 'Resume this channel?' : 'Pause this channel?',
      paused
          ? 'Queued posts will start going out again on schedule.'
          : 'Queued posts stop going out until resumed.',
      action: paused ? 'Resume' : 'Pause',
    );
    if (!sure || !context.mounted) return;
    try {
      await services.mutations.post('/api/buffer/channel/pause',
          {'channelId': channel['id'], 'pause': !paused});
      if (!context.mounted) return;
      toast(context, paused ? 'Resumed' : 'Paused');
      services.store.buffer.refresh();
    } catch (e) {
      if (context.mounted) toast(context, 'Failed: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final paused = fmt.b(channel['isQueuePaused']);
    final down = fmt.b(channel['isDisconnected']);
    final service = fmt.s(channel['service']);

    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Icon(_icon(service),
              size: 17, color: down ? C.red : (paused ? C.amber : C.cyan)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    fmt.s(channel['displayName']).isEmpty
                        ? fmt.s(channel['name'])
                        : fmt.s(channel['displayName']),
                    style: T.w500(T.body2.copyWith(color: C.text))),
                if (service.isNotEmpty) Text(service, style: T.monoSmall),
              ],
            ),
          ),
          if (down)
            const Badge2('disconnected', color: C.redBg, textColor: C.red)
          else if (paused)
            const Badge2('paused', color: C.amberBg, textColor: C.amber)
          else
            const Badge2('live', color: C.greenBg, textColor: C.greenBright),
          if (compose && !down) ...[
            const SizedBox(width: 8),
            IconButton(
              tooltip: paused ? 'Resume' : 'Pause',
              icon: Icon(
                  paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  size: 17),
              onPressed: () => _togglePause(context),
            ),
          ],
        ],
      ),
    );
  }
}

class _PostTile extends StatelessWidget {
  const _PostTile(
      {required this.post, required this.upcoming, this.compose = false});
  final Map<String, dynamic> post;
  final bool upcoming;
  final bool compose;

  Future<void> _manage(BuildContext context, String id, String action,
      {String? text, DateTime? dueAt}) async {
    final services = AppScope.of(context);
    try {
      final res = await services.mutations.post('/api/buffer/post/manage', {
        'id': id,
        'action': action,
        if (text != null) 'text': text,
        if (dueAt != null) 'dueAt': dueAt.toIso8601String(),
      });
      if (!context.mounted) return;
      final map = fmt.m(res);
      if (map['success'] == true) {
        toast(context, 'Done');
        services.store.buffer.refresh();
      } else {
        toast(context,
            fmt.s(map['error']).isEmpty ? 'Failed' : fmt.s(map['error']),
            error: true);
      }
    } catch (e) {
      if (context.mounted) toast(context, 'Failed: $e', error: true);
    }
  }

  void _actions(BuildContext context, Map<String, dynamic> p) {
    final id = fmt.s(p['id']);
    if (id.isEmpty) return;
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
            ListTile(
              dense: true,
              leading: const Icon(Icons.edit_outlined, size: 18),
              title: const Text('Edit text', style: T.body2),
              onTap: () async {
                Navigator.pop(ctx);
                final controller =
                    TextEditingController(text: fmt.s(p['text']));
                final ok = await showFormSheet<bool>(
                  context,
                  title: 'Edit post',
                  builder: (ctx) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Field(label: 'Text', controller: controller, maxLines: 5),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                );
                if (ok == true && context.mounted) {
                  await _manage(context, id, 'edit', text: controller.text);
                }
              },
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.delete_outline_rounded,
                  size: 18, color: C.red),
              title: const Text('Delete', style: T.body2),
              onTap: () async {
                Navigator.pop(ctx);
                final sure = await confirmDialog(context, 'Delete post?',
                    'Removes it from the Buffer queue. This cannot be undone.',
                    action: 'Delete', destructive: true);
                if (sure && context.mounted) await _manage(context, id, 'delete');
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Buffer's GraphQL nests the post under `node` in some shapes; tolerate both
    // rather than render an empty card if the server passes the edge through.
    final p = post['node'] is Map ? fmt.m(post['node']) : post;
    final text = fmt.s(p['text']).isEmpty ? fmt.s(p['notes']) : fmt.s(p['text']);
    final due = fmt.s(p['dueAt']).isEmpty ? fmt.s(p['sentAt']) : fmt.s(p['dueAt']);
    final status = fmt.s(p['status']);

    return Panel(
      onLongPress: compose && upcoming ? () => _actions(context, p) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (status.isNotEmpty)
                Badge2(status,
                    color: upcoming ? C.cyanBg : C.greenBg,
                    textColor: upcoming ? C.cyan : C.greenBright),
              const Spacer(),
              if (due.isNotEmpty)
                Text(fmt.shortDate(due), style: T.monoSmall),
              if (compose && upcoming) ...[
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'Manage',
                  icon: const Icon(Icons.more_horiz_rounded, size: 16),
                  onPressed: () => _actions(context, p),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
              ],
            ],
          ),
          if (text.isNotEmpty) ...[
            const SizedBox(height: 7),
            Text(fmt.truncate(text, 240),
                style: T.body2.copyWith(height: 1.5)),
          ],
        ],
      ),
    );
  }
}
