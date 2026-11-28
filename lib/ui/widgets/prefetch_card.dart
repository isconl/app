import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../services/audio_downloads.dart';
import '../../services/prefetch.dart';
import '../../services/prefetch_worker.dart';
import '../../theme.dart';

/// Settings, Prefetch: the on/off switch and the size cap for lessons fetched
/// quietly on Wi-Fi while charging.
class PrefetchCard extends StatefulWidget {
  const PrefetchCard({super.key, this.store, this.onChanged});

  /// Tests pass a fake store; the app reads its own database.
  final PrefetchStore? store;
  final Future<void> Function(PrefetchSettings s)? onChanged;

  @override
  State<PrefetchCard> createState() => _PrefetchCardState();
}

class _PrefetchCardState extends State<PrefetchCard> {
  static const caps = [100, 200, 500, 1000]; // MB
  Future<PrefetchSettings>? _settings;

  PrefetchStore get _store => widget.store ?? DbPrefetchStore(AppScope.of(context).db);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _settings ??= _store.settings();
  }

  Future<void> _save(PrefetchSettings s) async {
    await _store.saveSettings(s);
    await (widget.onChanged ?? syncPrefetchSchedule)(s);
    if (mounted) {
      setState(() {
        _settings = Future.value(s);
      });
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<PrefetchSettings>(
        future: _settings,
        builder: (context, snap) {
          final s = snap.data;
          if (s == null) return const SizedBox.shrink();
          final mb = (s.capBytes / (1024 * 1024)).round();
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SwitchListTile(
              key: const Key('prefetch-switch'),
              contentPadding: EdgeInsets.zero,
              title: Text('Prefetch lessons on Wi-Fi', style: T.body),
              subtitle: Text('Fetches the next two lessons of the courses you are studying, only on Wi-Fi and while charging.', style: T.small),
              value: s.enabled,
              onChanged: (v) => _save(PrefetchSettings(enabled: v, capBytes: s.capBytes)),
            ),
            if (s.enabled)
              Row(children: [
                Expanded(child: Text('Keep at most ${prettyBytes(s.capBytes)} of prefetched lessons', style: T.small)),
                DropdownButton<int>(
                  key: const Key('prefetch-cap'),
                  value: caps.contains(mb) ? mb : 200,
                  items: [for (final c in caps) DropdownMenuItem(value: c, child: Text('$c MB'))],
                  onChanged: (v) => v == null ? null : _save(PrefetchSettings(enabled: true, capBytes: v * 1024 * 1024)),
                ),
              ]),
          ]);
        },
      );
}
