import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData, HapticFeedback;

import '../../app_scope.dart';
import '../../data/lesson_notes.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../shell.dart' show SecondaryScreen;
import '../widgets/common.dart';
import '../widgets/lesson_notes_editor.dart';

/// Opens the notes list as its own screen.
void openStudyNotes(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) =>
        const SecondaryScreen(title: 'Study notes', child: StudyNotesView()),
  ));
}

/// Every study note in one place (BI26111402): what is on this phone, whether
/// the server has it, and notes written elsewhere. From here a note can be
/// edited, copied or sent to the inbox, where the agent picks ideas up as
/// work; and all of them can be copied or sent at once as one markdown file.
class StudyNotesView extends StatefulWidget {
  const StudyNotesView({super.key});

  @override
  State<StudyNotesView> createState() => _StudyNotesViewState();
}

class _ServerNote {
  _ServerNote(this.course, this.courseTitle, this.file, this.title,
      this.preview, this.updatedAt);
  final String course, courseTitle, file, title, preview, updatedAt;
}

class _StudyNotesViewState extends State<StudyNotesView> {
  List<LessonNote> _local = [];
  List<_ServerNote> _elsewhere = [];
  final Map<String, String> _titles = {};
  bool _loaded = false;
  bool _busy = false;
  String? _expanded;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final services = AppScope.of(context);
    final local = await services.lessonNotes.allNotes();
    final elsewhere = <_ServerNote>[];
    try {
      final res = await services.api.getJson('/api/learning/notes/all');
      final keys = {for (final n in local) '${n.course}/${n.file}'};
      for (final n in fmt.lm(fmt.m(res)['notes'])) {
        final key = '${fmt.s(n['course'])}/${fmt.s(n['file'])}';
        _titles[key] = fmt.s(n['title']);
        if (!keys.contains(key)) {
          elsewhere.add(_ServerNote(
              fmt.s(n['course']),
              fmt.s(n['courseTitle']),
              fmt.s(n['file']),
              fmt.s(n['title']),
              fmt.s(n['preview']),
              fmt.s(n['updatedAt'])));
        }
      }
    } catch (_) {
      // Offline: the phone's own notes still show.
    }
    if (!mounted) return;
    setState(() {
      _local = local;
      _elsewhere = elsewhere;
      _loaded = true;
    });
  }

  Future<void> _syncNow() async {
    setState(() => _busy = true);
    final services = AppScope.of(context);
    final sent = await services.lessonNotes.pushAll();
    await _load();
    if (!mounted) return;
    setState(() => _busy = false);
    final left = services.lessonNotes.waiting;
    toast(
        context,
        left == 0
            ? (sent == 0 ? 'Everything is synced' : 'Sent $sent')
            : 'Sent $sent, $left still waiting for the server',
        error: left > 0);
  }

  Future<void> _copyAll() async {
    final md = await AppScope.of(context).lessonNotes.exportMarkdown();
    await Clipboard.setData(ClipboardData(text: md));
    if (mounted) toast(context, 'All notes copied as markdown');
  }

  Future<void> _toInbox(String title, String body) async {
    HapticFeedback.selectionClick();
    final res = await AppScope.of(context)
        .mutations
        .addInbox(body: body, title: title, sender: 'study-notes');
    if (!mounted) return;
    toast(
        context,
        !res.ok
            ? res.error!
            : res.queued
                ? 'Queued for the inbox'
                : 'In the inbox',
        error: !res.ok);
  }

  Future<void> _sendAll() async {
    final md = await AppScope.of(context).lessonNotes.exportMarkdown();
    final day = DateTime.now().toIso8601String().substring(0, 10);
    await _toInbox('Study notes, $day', md);
  }

  Future<void> _edit(String course, String file, String? title) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Sz.rXl)),
        side: BorderSide(color: C.border),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
            child: LessonNotes(
                course: course, file: file, title: title, inSheet: true),
          ),
        ),
      ),
    );
    await _load();
  }

  String _ago(DateTime? t) {
    if (t == null) return '';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    if (d.inDays < 7) return '${d.inDays} d ago';
    return t.toIso8601String().substring(0, 10);
  }

  Widget _chip(bool synced) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: synced ? C.greenBg : C.amberBg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(synced ? Icons.cloud_done_rounded : Icons.phone_android_rounded,
              size: 12, color: synced ? C.green : C.amber),
          const SizedBox(width: 4),
          Text(synced ? 'Synced' : 'On phone',
              style: T.tiny.copyWith(color: synced ? C.green : C.amber)),
        ]),
      );

  Widget _card(LessonNote n) {
    final key = '${n.course}/${n.file}';
    final open = _expanded == key;
    final title = (_titles[key] ?? '').isNotEmpty ? _titles[key]! : n.displayTitle;
    return Card(
      key: Key('note-$key'),
      color: C.panel,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Sz.rMd),
        side: const BorderSide(color: C.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(Sz.rMd),
        onTap: () => setState(() => _expanded = open ? null : key),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(title,
                      style: T.body.copyWith(
                          color: C.text, fontWeight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                _chip(n.sync == NoteSync.synced),
              ]),
              const SizedBox(height: 2),
              Text('${n.course} · ${_ago(n.updatedAt)}',
                  style: T.tiny.copyWith(color: C.text3)),
              const SizedBox(height: 8),
              Text(n.text.trim(),
                  maxLines: open ? null : 3,
                  overflow: open ? null : TextOverflow.ellipsis,
                  style: T.body2.copyWith(color: C.text2, height: 1.55)),
              if (open) ...[
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 4, children: [
                  OutlinedButton.icon(
                    onPressed: () => _edit(n.course, n.file, title),
                    icon: const Icon(Icons.edit_rounded, size: 16),
                    label: const Text('Edit'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _toInbox('Study note: $title',
                        '${n.text.trim()}\n\n(${n.course}/${n.file})'),
                    icon: const Icon(Icons.move_to_inbox_rounded, size: 16),
                    label: const Text('To inbox'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: n.text));
                      if (mounted) toast(context, 'Note copied');
                    },
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('Copy'),
                  ),
                ]),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.of(context).lessonNotes;
    if (!_loaded) return const Center(child: MiniSpinner(size: 20));
    return RefreshIndicator(
      onRefresh: _syncNow,
      color: C.green,
      backgroundColor: C.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          ListenableBuilder(
            listenable: repo,
            builder: (context, _) => Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: C.surface,
                borderRadius: BorderRadius.circular(Sz.rMd),
                border: Border.all(color: C.border),
              ),
              child: Row(children: [
                Icon(
                    repo.waiting == 0
                        ? Icons.cloud_done_rounded
                        : Icons.cloud_upload_outlined,
                    color: repo.waiting == 0 ? C.green : C.amber),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    key: const Key('notes-summary'),
                    '${_local.length} ${_local.length == 1 ? 'note' : 'notes'} on this phone'
                    '${repo.waiting == 0 ? ', all synced' : ', ${repo.waiting} waiting to sync'}',
                    style: T.body2.copyWith(color: C.text2),
                  ),
                ),
                if (repo.waiting > 0)
                  TextButton(
                    onPressed: _busy ? null : _syncNow,
                    child: _busy ? const MiniSpinner() : const Text('Sync now'),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _local.isEmpty ? null : _copyAll,
                icon: const Icon(Icons.copy_all_rounded, size: 16),
                label: const Text('Copy all'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                key: const Key('notes-send-all'),
                onPressed: _local.isEmpty ? null : _sendAll,
                icon: const Icon(Icons.move_to_inbox_rounded, size: 16),
                label: const Text('All to inbox'),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          if (_local.isEmpty && _elsewhere.isEmpty)
            const EmptyState(
              'No notes yet',
              'Open a module and tap the note button. Notes save as you type.',
              icon: Icons.edit_note_rounded,
            ),
          for (final n in _local) _card(n),
          if (_elsewhere.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('WRITTEN ELSEWHERE', style: T.label.copyWith(color: C.text3)),
            const SizedBox(height: 8),
            for (final s in _elsewhere)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(s.title.isEmpty ? s.file : s.title,
                    style: T.body.copyWith(color: C.text)),
                subtitle: Text('${s.courseTitle} · ${s.preview}',
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: T.tiny.copyWith(color: C.text3)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _edit(s.course, s.file, s.title),
              ),
          ],
        ],
      ),
    );
  }
}
