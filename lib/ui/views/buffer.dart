import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../widgets/common.dart';

/// The Buffer desk: which channels exist, what is queued, what went out.
///
/// Read-only on purpose. Buffer is a live third-party API on a rate-limit
/// budget, and publishing to the outside world is exactly the class of action
/// the constitution keeps behind a deliberate, online, confirmed gate - not a
/// thumb on a phone. Composing stays on the web desk; this is the glance.
class BufferView extends StatelessWidget {
  const BufferView({super.key});

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

            SectionLabel('Channels · ${channels.length}'),
            if (channels.isEmpty)
              const EmptyState('No channels', 'Nothing connected in Buffer yet.',
                  icon: Icons.link_off_rounded)
            else
              ...channels.map((c) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _ChannelTile(channel: c),
                  )),

            SectionLabel('Queued · ${queue.length}'),
            if (queue.isEmpty)
              const EmptyState('Queue is empty',
                  'Nothing scheduled to go out.', icon: Icons.schedule_rounded)
            else
              ...queue.take(25).map((p) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _PostTile(post: p, upcoming: true),
                  )),

            if (sent.isNotEmpty) ...[
              SectionLabel('Sent · ${sent.length}'),
              ...sent.take(15).map((p) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _PostTile(post: p, upcoming: false),
                  )),
            ],
          ],
        );
      },
    );
  }
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({required this.channel});
  final Map<String, dynamic> channel;

  static IconData _icon(String service) => switch (service.toLowerCase()) {
        'twitter' || 'x' => Icons.alternate_email_rounded,
        'linkedin' => Icons.business_center_rounded,
        'facebook' => Icons.thumb_up_rounded,
        'instagram' => Icons.photo_camera_rounded,
        'mastodon' => Icons.forum_rounded,
        'threads' => Icons.tag_rounded,
        _ => Icons.public_rounded,
      };

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
        ],
      ),
    );
  }
}

class _PostTile extends StatelessWidget {
  const _PostTile({required this.post, required this.upcoming});
  final Map<String, dynamic> post;
  final bool upcoming;

  @override
  Widget build(BuildContext context) {
    // Buffer's GraphQL nests the post under `node` in some shapes; tolerate both
    // rather than render an empty card if the server passes the edge through.
    final p = post['node'] is Map ? fmt.m(post['node']) : post;
    final text = fmt.s(p['text']).isEmpty ? fmt.s(p['notes']) : fmt.s(p['text']);
    final due = fmt.s(p['dueAt']).isEmpty ? fmt.s(p['sentAt']) : fmt.s(p['dueAt']);
    final status = fmt.s(p['status']);

    return Panel(
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
