import 'platform.dart' show SharedFile;

/// BI26100159: what the share sheet does with what was shared into the app.
///
/// Everything goes through the outbox like any other write, so it works offline and syncs later. The hub has no
/// route yet that takes a file's bytes, so a shared photo or PDF is kept on this device (never lost) and its
/// record is saved with the file's name, type and size, and the sheet says so plainly.

enum ShareDestination { inbox, task, journal, files }

extension ShareDestinationLabel on ShareDestination {
  String get label => switch (this) {
        ShareDestination.inbox => 'Inbox',
        ShareDestination.task => 'Task',
        ShareDestination.journal => 'Journal',
        ShareDestination.files => 'Files',
      };
}

/// The most a shared file may be: the phone copies it to a cache folder at once.
const maxSharedFileBytes = 25 * 1024 * 1024;

class ShareItem {
  const ShareItem.text(this.text) : files = const [];
  const ShareItem.files(this.files) : text = '';
  final String text;
  final List<SharedFile> files;

  bool get hasFiles => files.isNotEmpty;

  /// A link when the whole text is one.
  Uri? get link {
    final t = text.trim();
    if (t.isEmpty || t.contains(RegExp(r'\s'))) return null;
    final u = Uri.tryParse(t);
    return u != null && (u.scheme == 'http' || u.scheme == 'https') && u.host.isNotEmpty ? u : null;
  }

  /// A line the sheet shows as the preview.
  String get preview {
    if (hasFiles) {
      if (files.length == 1) return '${files.first.name}, ${sizeLabel(files.first.size)}';
      return '${files.length} files, ${sizeLabel(files.fold(0, (n, f) => n + f.size))}';
    }
    final l = link;
    if (l != null) return l.host.startsWith('www.') ? l.host.substring(4) : l.host;
    final t = text.trim();
    return t.length > 140 ? '${t.substring(0, 140)}...' : t;
  }
}

String sizeLabel(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// The destinations that make sense for [item]: a file has no use as a bare task or journal text, but each may
/// carry its name, so all four stay, except that Files is for files only.
List<ShareDestination> destinationsFor(ShareItem item) =>
    [for (final d in ShareDestination.values) if (d != ShareDestination.files || item.hasFiles) d];

/// The text of the record for [item] with the reader's [note]: the note first, then what was shared.
String composeBody(ShareItem item, String note) {
  final parts = <String>[
    if (note.trim().isNotEmpty) note.trim(),
    if (item.hasFiles)
      for (final f in item.files) 'Shared file: ${f.name} (${f.mime}, ${sizeLabel(f.size)})${f.tooBig ? ', too big to keep' : ''}'
    else
      item.text.trim(),
  ];
  return parts.join('\n\n');
}

/// A task title: the note when there is one, otherwise the first line of what was shared, cut to fit.
String composeTaskTitle(ShareItem item, String note) {
  final base = note.trim().isNotEmpty
      ? note.trim()
      : item.hasFiles
          ? 'Look at ${item.files.first.name}${item.files.length > 1 ? ' and ${item.files.length - 1} more' : ''}'
          : (item.link != null ? 'Read ${item.preview}' : item.text.trim().split('\n').first);
  final one = base.split('\n').first.trim();
  return one.length > 90 ? '${one.substring(0, 87)}...' : one;
}

abstract class ShareSink {
  Future<bool> addInbox({required String body, String title});
  Future<bool> addTask({required String title});
  Future<bool> addJournal({required String body});

  /// Keeps a shared file somewhere that outlives the cache folder. Returns the new path.
  Future<String> keepFile(SharedFile f);
}

class ShareOutcome {
  const ShareOutcome(this.ok, this.message);
  final bool ok;
  final String message;
}

/// Saves [item] to [dest]. A file that was too big is refused first, saying so; kept files are named in the message.
Future<ShareOutcome> saveShare(ShareSink sink, ShareItem item, ShareDestination dest, String note) async {
  if (item.hasFiles && item.files.every((f) => f.tooBig)) {
    return ShareOutcome(false, 'Too big: files over ${maxSharedFileBytes ~/ (1024 * 1024)} MB are not taken. Nothing was saved.');
  }
  var kept = 0;
  if (item.hasFiles) {
    for (final f in item.files) {
      if (f.tooBig) continue;
      try {
        await sink.keepFile(f);
        kept++;
      } catch (_) {}
    }
  }
  final body = composeBody(item, note);
  final bool ok;
  switch (dest) {
    case ShareDestination.inbox:
    case ShareDestination.files:
      ok = await sink.addInbox(body: body, title: item.hasFiles ? composeTaskTitle(item, '') : '');
    case ShareDestination.task:
      ok = await sink.addTask(title: composeTaskTitle(item, note));
    case ShareDestination.journal:
      ok = await sink.addJournal(body: body);
  }
  if (!ok) return const ShareOutcome(false, 'Could not save it. Try again.');
  final where = dest == ShareDestination.files ? 'Inbox' : dest.label;
  return ShareOutcome(
    true,
    item.hasFiles
        ? 'Saved to $where. $kept ${kept == 1 ? 'file is' : 'files are'} kept on this phone; the hub cannot take file contents yet.'
        : 'Saved to $where.',
  );
}
