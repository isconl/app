import 'package:flutter/material.dart';

import '../../services/close_feed.dart';
import '../../services/prefetch_worker.dart' show syncCloseFeedSchedule;
import '../../theme.dart';
import 'common.dart';

/// BI26101529: Settings > Notifications. The "Slate closes" switch (on by default), quiet hours that
/// follow the Protected and Rest blocks, and a mute for each project a close has come from.
class SlateClosesCard extends StatefulWidget {
  const SlateClosesCard({super.key, this.feed});

  /// For tests; the app uses the running feed.
  final CloseFeed? feed;

  @override
  State<SlateClosesCard> createState() => _SlateClosesCardState();
}

class _SlateClosesCardState extends State<SlateClosesCard> {
  CloseFeed? get _feed => widget.feed ?? activeCloseFeed;

  Future<void> _change(void Function(ClosePrefs p) edit) async {
    final feed = _feed;
    if (feed == null) return;
    edit(feed.prefs);
    setState(() {});
    await feed.savePrefs();
    await syncCloseFeedSchedule(feed.prefs.enabled);
    if (feed.prefs.enabled) {
      feed.start();
    } else {
      feed.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final feed = _feed;
    if (feed == null) return const SizedBox.shrink();
    final p = feed.prefs;
    final projects = (p.seenProjects.toList()..sort());
    return Panel(
      child: Material(
        type: MaterialType.transparency,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SwitchListTile(
            key: const Key('slate-closes-enabled'),
            contentPadding: EdgeInsets.zero,
            title: Text('Slate closes', style: T.body2),
            subtitle: Text('A notification each time a row is closed. Three or more at once become one.', style: T.tiny),
            value: p.enabled,
            onChanged: (v) => _change((p) => p.enabled = v),
          ),
          SwitchListTile(
            key: const Key('slate-closes-quiet'),
            contentPadding: EdgeInsets.zero,
            title: Text('Quiet hours', style: T.body2),
            subtitle: Text('Silent during the Protected and Rest blocks.', style: T.tiny),
            value: p.quietHours,
            onChanged: p.enabled ? (v) => _change((p) => p.quietHours = v) : null,
          ),
          if (projects.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Mute a project', style: T.small.copyWith(color: C.text3)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final project in projects)
                FilterChip(
                  key: Key('slate-closes-mute-$project'),
                  label: Text(project),
                  selected: p.muted.contains(project),
                  onSelected: p.enabled
                      ? (on) => _change((p) => on ? p.muted.add(project) : p.muted.remove(project))
                      : null,
                ),
            ]),
          ],
        ]),
      ),
    );
  }
}
