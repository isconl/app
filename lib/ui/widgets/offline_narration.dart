import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../services/audio_downloads.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;

/// The per-module offline control under the Listen bar: download the agent's
/// narration to the phone, see that it is there, or remove it.
class OfflineRow extends StatefulWidget {
  const OfflineRow({super.key, required this.downloads, required this.course, required this.file, required this.rev});
  final AudioDownloads downloads;
  final String course;
  final String file;
  final String rev;

  @override
  State<OfflineRow> createState() => _OfflineRowState();
}

class _OfflineRowState extends State<OfflineRow> {
  late Future<DownloadedAudio?> _have = widget.downloads.local(widget.course, widget.file, widget.rev);
  String? _message;

  Future<void> _download() async {
    setState(() => _message = null);
    try {
      await widget.downloads.download(course: widget.course, file: widget.file, rev: widget.rev);
    } on AudioDownloadException catch (e) {
      if (mounted) setState(() => _message = e.message);
    }
    if (mounted) {
      setState(() => _have = widget.downloads.local(widget.course, widget.file, widget.rev));
    }
  }

  Future<void> _remove() async {
    await widget.downloads.deleteModule(widget.course, widget.file, widget.rev);
    if (mounted) {
      setState(() => _have = widget.downloads.local(widget.course, widget.file, widget.rev));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.downloads,
        builder: (context, _) {
          final k = AudioDownloads.keyOf(widget.course, widget.file);
          final p = widget.downloads.progress[k];
          return FutureBuilder<DownloadedAudio?>(
            future: _have,
            builder: (context, snap) {
              final have = snap.data;
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    if (p != null) ...[
                      Expanded(child: LinearProgressIndicator(key: const Key('offline-progress'), minHeight: 2, value: p == 0 ? null : p)),
                    ] else if (have != null) ...[
                      Expanded(
                        child: Text('On this phone, ${prettyBytes(have.bytes)}. Plays with no signal.',
                            key: const Key('offline-have'), style: T.tiny.copyWith(color: C.greenBright)),
                      ),
                      TextButton(key: const Key('offline-remove'), onPressed: _remove, child: const Text('Remove')),
                    ] else ...[
                      Expanded(
                        child: Text('Download the narration to listen with no signal.', style: T.tiny),
                      ),
                      TextButton(
                          key: const Key('offline-download'), onPressed: _download, child: const Text('Download')),
                    ],
                  ]),
                  if (_message != null)
                    Text(_message!, key: const Key('offline-message'), style: T.tiny.copyWith(color: C.amber)),
                ]),
              );
            },
          );
        },
      );
}

/// Settings, Offline narration: what each course takes up, with the controls to
/// download a whole course, delete it, and choose Wi-Fi only or any connection.
class OfflineNarrationCard extends StatefulWidget {
  const OfflineNarrationCard({super.key});

  @override
  State<OfflineNarrationCard> createState() => _OfflineNarrationCardState();
}

class _OfflineNarrationCardState extends State<OfflineNarrationCard> {
  Future<Map<String, int>>? _usage;
  String? _message;
  bool _busy = false;

  AudioDownloads? get _dl => AppScope.of(context).narrator.downloads;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _usage ??= _dl?.usage();
  }

  void _reload() => setState(() => _usage = _dl?.usage());

  Future<void> _downloadCourse(String course) async {
    final services = AppScope.of(context);
    final dl = _dl!;
    final modules = <({String file, String rev})>[
      for (final m in services.modules.narrated.where((m) => m.course == course))
        (file: m.file, rev: fmt.s(services.modules.audioFor(m.course, m.file)?['rev'])),
    ];
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final n = await dl.downloadCourse(course, modules);
      _message = 'Downloaded $n module${n == 1 ? '' : 's'} of $course.';
    } on AudioDownloadException catch (e) {
      _message = e.message;
    }
    if (mounted) {
      setState(() => _busy = false);
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dl = _dl;
    if (dl == null) return Text('Offline narration is not available on this build.', style: T.small);
    final services = AppScope.of(context);
    final courses = {for (final m in services.modules.narrated) m.course};
    return FutureBuilder<Map<String, int>>(
      future: _usage,
      builder: (context, snap) {
        final usage = snap.data ?? const <String, int>{};
        final all = {...courses, ...usage.keys}.toList()..sort();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SwitchListTile(
            key: const Key('offline-wifi-only'),
            contentPadding: EdgeInsets.zero,
            title: Text('Download on Wi-Fi only', style: T.body),
            value: dl.wifiOnly,
            onChanged: (v) => setState(() => dl.wifiOnly = v),
          ),
          if (all.isEmpty) Text('No narrated courses yet.', style: T.small),
          for (final c in all)
            ListTile(
              key: Key('offline-course-$c'),
              contentPadding: EdgeInsets.zero,
              title: Text(c, style: T.body),
              subtitle: Text(
                  usage[c] == null ? 'Not downloaded' : '${prettyBytes(usage[c]!)} on this phone',
                  style: T.small),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                TextButton(
                  key: Key('offline-get-$c'),
                  onPressed: _busy ? null : () => _downloadCourse(c),
                  child: const Text('Download'),
                ),
                if (usage[c] != null)
                  TextButton(
                    key: Key('offline-delete-$c'),
                    onPressed: _busy
                        ? null
                        : () async {
                            await dl.deleteCourse(c);
                            _reload();
                          },
                    child: const Text('Delete'),
                  ),
              ]),
            ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_message!, key: const Key('offline-card-message'), style: T.small),
            ),
        ]);
      },
    );
  }
}
