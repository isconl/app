import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../../app_scope.dart';
import '../../data/lesson_notes.dart';
import '../../data/mutations.dart' show MutationResult;
import '../../data/note_doc.dart';
import '../../theme.dart';
import '../views/study_notes_view.dart';
import 'common.dart';
import 'reader.dart';

/// Where the entry being typed stands, shown under the field.
enum _NoteState { idle, typing, savedLocal, sending, synced, waiting, refused }

/// BI26112301 (note taking v2, Sconl's study notes of 19 Nov): notes open in a floating card in the middle of the
/// screen, and while the keyboard is up the card's lower edge sits just above it. Save, Sync, New note and All notes
/// stay in one row at the top, so none of them needs the keyboard closed first.
///
/// A module holds several notes, each anchored to the paragraph it was opened from (long-press a paragraph, then
/// "Note on this paragraph"), or to no paragraph for a change of topic (New note). Each Save adds an entry with its
/// own time, so notes taken progressively read as a dated log.
///
/// What a reader can still count on (BI26111402): every pause in typing saves on the phone, a few seconds later it
/// goes to the server by itself, and closing the card keeps what was typed.
Future<void> openNoteCard(
  BuildContext context, {
  required String course,
  required String file,
  String? title,
  int? paragraph,
  String? paragraphText,
  LessonNotesRepository? repository,
}) {
  HapticFeedback.selectionClick();
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close notes',
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 160),
    transitionBuilder: (_, anim, __, child) => FadeTransition(
      opacity: anim,
      child: ScaleTransition(scale: Tween(begin: 0.97, end: 1.0).animate(anim), child: child),
    ),
    pageBuilder: (ctx, _, __) => NoteCardFrame(
      child: NoteCard(
        course: course,
        file: file,
        title: title,
        paragraph: paragraph,
        paragraphText: paragraphText,
        repository: repository,
      ),
    ),
  );
}

/// Centres the card, and lifts it so its bottom edge is just above the keyboard when the keyboard is up.
class NoteCardFrame extends StatelessWidget {
  const NoteCardFrame({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final kb = mq.viewInsets.bottom;
    return AnimatedPadding(
      key: const Key('note-card-frame'),
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      padding: EdgeInsets.fromLTRB(
        12,
        mq.padding.top + 12,
        12,
        kb > 0 ? kb + 8 : mq.padding.bottom + 12,
      ),
      child: Align(
        alignment: kb > 0 ? Alignment.bottomCenter : Alignment.center,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Material(
            color: C.panel,
            elevation: 12,
            shadowColor: Colors.black,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Sz.rLg),
              side: const BorderSide(color: C.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: child,
          ),
        ),
      ),
    );
  }
}

class NoteCard extends StatefulWidget {
  const NoteCard({
    super.key,
    required this.course,
    required this.file,
    this.title,
    this.paragraph,
    this.paragraphText,
    this.repository,
  });

  final String course;
  final String file;
  final String? title;

  /// The paragraph the card was opened from (block index), or null to open the note last written in.
  final int? paragraph;
  final String? paragraphText;
  final LessonNotesRepository? repository;

  @override
  State<NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends State<NoteCard> {
  static const _localDelay = Duration(milliseconds: 700);
  static const _sendDelay = Duration(seconds: 4);

  final _controller = TextEditingController();
  final _focus = FocusNode();
  NoteDoc _doc = NoteDoc();
  ModuleNote? _note;

  /// The entry the composer writes into: a draft for a new entry, or a saved entry being edited.
  NoteEntry? _entry;
  bool _loaded = false;
  String? _error;
  _NoteState _state = _NoteState.idle;
  DateTime? _syncedAt;
  Timer? _localTimer;
  Timer? _sendTimer;
  LessonNotesRepository? _repoRef;
  bool _syncing = false;

  /// The document as last written to the phone, so opening and closing the card without a change writes nothing.
  String _lastSaved = '';

  LessonNotesRepository get _repo => widget.repository ?? _repoRef ?? AppScope.of(context).lessonNotes;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _repoRef = widget.repository ?? AppScope.of(context).lessonNotes;
  }

  @override
  void dispose() {
    _localTimer?.cancel();
    _sendTimer?.cancel();
    // Closing the card keeps what was typed: the draft becomes an entry, and the module's notes are sent.
    final repo = _repoRef;
    if (repo != null && _loaded) {
      _absorbComposer();
      _finishDraft();
      if (_doc.serialize() != _lastSaved) unawaited(repo
          .saveNote(
            course: widget.course,
            file: widget.file,
            text: _doc.serialize(),
            anchor: _note?.anchor,
            title: widget.title,
          )
          .catchError((_) => MutationResult.queued()));
    }
    _controller.removeListener(_onChanged);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final note = await _repo.getNote(course: widget.course, file: widget.file);
      if (!mounted) return;
      _doc = note?.doc ?? NoteDoc();
      _syncedAt = note?.syncedAt;
      if (note != null && note.text.isNotEmpty) {
        _state = note.sync == NoteSync.synced ? _NoteState.synced : _NoteState.waiting;
      }
      final p = widget.paragraph;
      if (p != null) {
        final quote = paragraphQuote(widget.paragraphText ?? '');
        _note = _doc.forParagraph(p, quote) ?? _doc.add(anchor: p, quote: quote);
      } else {
        _note = _doc.latest ?? _doc.add();
      }
      _openComposerOn(_note!.draft);
      _lastSaved = _doc.serialize();
      setState(() => _loaded = true);
      _focus.requestFocus();
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load your notes ($e).');
    }
  }

  /// Points the composer at [entry] (null starts a fresh entry on the next keystroke).
  void _openComposerOn(NoteEntry? entry) {
    _entry = entry;
    _controller.removeListener(_onChanged);
    _controller.text = entry?.text ?? '';
    _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
    _controller.addListener(_onChanged);
  }

  /// Writes the composer's text into the document (creating the draft entry on the first word).
  void _absorbComposer() {
    final note = _note;
    if (note == null) return;
    final text = _controller.text;
    final now = DateTime.now();
    if (_entry == null) {
      if (text.trim().isEmpty) return;
      _entry = NoteEntry(id: newNoteId(), text: text, createdAt: now, draft: true);
      note.entries.add(_entry!);
    } else if (_entry!.text != text) {
      _entry!.text = text;
      _entry!.updatedAt = now;
    }
  }

  /// The draft becomes a saved entry; an empty one is dropped.
  void _finishDraft() {
    final note = _note;
    final e = _entry;
    if (note == null || e == null) return;
    if (e.text.trim().isEmpty) {
      note.entries.remove(e);
    } else {
      e.draft = false;
    }
  }

  void _onChanged() {
    if (!_loaded) return;
    if (_state != _NoteState.typing) setState(() => _state = _NoteState.typing);
    _localTimer?.cancel();
    _sendTimer?.cancel();
    _localTimer = Timer(_localDelay, _saveLocal);
  }

  Future<void> _saveLocal() async {
    if (!mounted) return;
    _absorbComposer();
    _lastSaved = _doc.serialize();
    await _repo.saveDraft(
      course: widget.course,
      file: widget.file,
      text: _lastSaved,
      anchor: _note?.anchor,
      title: widget.title,
    );
    if (!mounted) return;
    setState(() => _state = _NoteState.savedLocal);
    _sendTimer?.cancel();
    _sendTimer = Timer(_sendDelay, () => _send(quiet: true));
  }

  Future<void> _send({bool quiet = false}) async {
    if (!mounted) return;
    _localTimer?.cancel();
    _sendTimer?.cancel();
    setState(() => _state = _NoteState.sending);
    _lastSaved = _doc.serialize();
    final res = await _repo.saveNote(
      course: widget.course,
      file: widget.file,
      text: _lastSaved,
      anchor: _note?.anchor,
      title: widget.title,
    );
    if (!mounted) return;
    setState(() {
      if (!res.ok) {
        _state = _NoteState.refused;
        _error = res.error;
      } else if (res.queued) {
        _state = _NoteState.waiting;
      } else {
        _state = _NoteState.synced;
        _syncedAt = DateTime.now();
        _error = null;
      }
    });
    if (!quiet && !res.ok) toast(context, res.error!, error: true);
  }

  /// Save: the typed text becomes a timestamped entry, the field clears for the next one, and it is sent now.
  Future<void> _save() async {
    HapticFeedback.lightImpact();
    _absorbComposer();
    _finishDraft();
    _openComposerOn(null);
    await _send();
    if (mounted) _focus.requestFocus();
  }

  Future<void> _syncAll() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    _absorbComposer();
    await _send(quiet: true);
    final sent = await _repo.pushAll();
    if (!mounted) return;
    setState(() => _syncing = false);
    final left = _repo.waiting;
    toast(
      context,
      left == 0
          ? 'All notes synced'
          : '${sent > 0 ? '$sent sent, ' : ''}$left waiting for the server',
      error: left > 0,
    );
  }

  void _switchTo(ModuleNote note) {
    if (identical(note, _note)) return;
    _absorbComposer();
    _finishDraft();
    setState(() {
      _note = note;
      _openComposerOn(note.draft);
    });
    _focus.requestFocus();
  }

  /// New note: a fresh note on no paragraph, for a change of topic.
  void _newNote() {
    HapticFeedback.selectionClick();
    _absorbComposer();
    _finishDraft();
    _doc.notes.removeWhere((n) => n.isEmpty && !identical(n, _note));
    final fresh = _doc.add();
    setState(() {
      if (_note != null && _note!.isEmpty) _doc.notes.remove(_note);
      _note = fresh;
      _openComposerOn(null);
    });
    _focus.requestFocus();
  }

  void _editEntry(NoteEntry e) {
    _absorbComposer();
    _finishDraft();
    setState(() => _openComposerOn(e));
    _focus.requestFocus();
  }

  Future<void> _allNotes() async {
    _absorbComposer();
    await _send(quiet: true);
    if (!mounted) return;
    final nav = Navigator.of(context);
    nav.pop();
    openStudyNotes(nav.context);
  }

  String _clock(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.hour < 12 ? 'am' : 'pm'}';
  }

  (IconData, String, Color) get _status => switch (_state) {
        _NoteState.idle => (Icons.edit_note_rounded, 'Saves as you type', C.text3),
        _NoteState.typing => (Icons.more_horiz_rounded, 'Typing', C.text3),
        _NoteState.savedLocal => (Icons.phone_android_rounded, 'Saved on this phone', C.text2),
        _NoteState.sending => (Icons.cloud_upload_outlined, 'Sending', C.text2),
        _NoteState.synced => (
            Icons.cloud_done_rounded,
            _syncedAt == null ? 'Synced' : 'Synced ${_clock(_syncedAt!)}',
            C.green
          ),
        _NoteState.waiting => (Icons.cloud_off_rounded, 'Safe on this phone, sends when online', C.amber),
        _NoteState.refused => (Icons.error_outline_rounded, 'Not sent: ${_error ?? 'refused'}', C.red),
      };

  Widget _barButton({required Key key, required String tip, required Widget icon, VoidCallback? onTap}) => IconButton(
        key: key,
        tooltip: tip,
        onPressed: onTap,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
        padding: EdgeInsets.zero,
        icon: icon,
      );

  Widget _syncIcon() {
    if (_syncing || _state == _NoteState.sending) return const MiniSpinner();
    final waiting = _state == _NoteState.waiting || _state == _NoteState.refused || _state == _NoteState.savedLocal;
    return Icon(
      waiting ? Icons.cloud_upload_outlined : Icons.cloud_done_rounded,
      size: 20,
      color: waiting ? C.amber : C.green,
    );
  }

  Widget _header() {
    final note = _note;
    final module = (widget.title ?? '').trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 4, 4),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            if (module.isNotEmpty)
              Text(module.toUpperCase(),
                  style: T.label.copyWith(color: C.text3, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(note?.label ?? 'Notes',
                key: const Key('note-card-title'),
                style: T.body.copyWith(color: C.text, fontWeight: FontWeight.w600, fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ]),
        ),
        _barButton(
          key: const Key('note-save'),
          tip: 'Save entry',
          icon: Icon(Icons.check_rounded, size: 22, color: C.green),
          onTap: _loaded ? _save : null,
        ),
        _barButton(key: const Key('note-sync'), tip: 'Sync now', icon: _syncIcon(), onTap: _loaded ? _syncAll : null),
        _barButton(
          key: const Key('note-new'),
          tip: 'New note',
          icon: const Icon(Icons.add_comment_outlined, size: 20, color: C.text2),
          onTap: _loaded ? _newNote : null,
        ),
        _barButton(
          key: const Key('note-all'),
          tip: 'All my notes',
          icon: const Icon(Icons.notes_rounded, size: 20, color: C.text2),
          onTap: _loaded ? _allNotes : null,
        ),
      ]),
    );
  }

  /// The module's other notes, to move between them; shown once there is more than one.
  Widget? _switcher() {
    final notes = _doc.notes.where((n) => !n.isEmpty || identical(n, _note)).toList();
    if (notes.length < 2) return null;
    return SizedBox(
      height: 36,
      child: ListView.separated(
        key: const Key('note-switch'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: notes.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final n = notes[i];
          final on = identical(n, _note);
          return ChoiceChip(
            key: Key('note-tab-$i'),
            selected: on,
            onSelected: (_) => _switchTo(n),
            visualDensity: VisualDensity.compact,
            label: Text(
              n.anchor == null ? n.label : '¶ ${n.anchor! + 1}',
              style: T.tiny.copyWith(color: on ? Colors.black : C.text2),
            ),
            selectedColor: C.green,
            backgroundColor: C.surface,
            side: BorderSide(color: on ? C.green : C.border),
            showCheckmark: false,
          );
        },
      ),
    );
  }

  Widget _entryTile(NoteEntry e) {
    final editing = identical(e, _entry);
    return InkWell(
      key: Key('note-entry-${e.id}'),
      borderRadius: BorderRadius.circular(Sz.rSm),
      onTap: () => _editEntry(e),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            editing ? '${e.stamp()} · editing' : e.stamp(),
            key: const Key('note-entry-stamp'),
            style: T.tiny.copyWith(color: editing ? C.green : C.text3, fontSize: 11, letterSpacing: 0.2),
          ),
          const SizedBox(height: 2),
          Text(e.text.trim(), style: T.body2.copyWith(color: C.text2, height: 1.5)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final (icon, line, colour) = _status;
    final saved = _note?.saved ?? const <NoteEntry>[];
    final switcher = _switcher();
    final words = RegExp(r'\S+').allMatches(_controller.text).length;
    return Column(
      key: const Key('note-card'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(),
        if (switcher != null) ...[switcher, const SizedBox(height: 4)],
        const Divider(height: 1),
        if (_error != null && !_loaded)
          Padding(
            padding: const EdgeInsets.all(14),
            child: ErrorRetry(_error!, onRetry: () {
              setState(() => _error = null);
              _load();
            }),
          ),
        if (saved.isNotEmpty)
          Flexible(
            child: ListView(
              key: const Key('note-entries'),
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
              children: [for (final e in saved) _entryTile(e)],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: C.surface,
              borderRadius: BorderRadius.circular(Sz.rMd),
              border: Border.all(color: _focus.hasFocus ? C.greenDim : C.border),
            ),
            child: TextField(
              key: const Key('note-field'),
              controller: _controller,
              focusNode: _focus,
              enabled: _loaded,
              minLines: 3,
              maxLines: 7,
              textCapitalization: TextCapitalization.sentences,
              keyboardType: TextInputType.multiline,
              style: T.body.copyWith(fontSize: 15, height: 1.55, color: C.text),
              decoration: InputDecoration(
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                hintText: !_loaded
                    ? 'Loading your notes'
                    : saved.isEmpty
                        ? 'An idea, a question, what you would do with this.'
                        : 'Add to this note',
                hintStyle: T.body2.copyWith(color: C.text3, fontSize: 15),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 2, 14, 10),
          child: Row(children: [
            Icon(icon, size: 13, color: colour),
            const SizedBox(width: 6),
            Expanded(
              child: Text(line,
                  key: const Key('note-status'),
                  style: T.tiny.copyWith(color: colour),
                  overflow: TextOverflow.ellipsis),
            ),
            if (words > 0) Text('$words ${words == 1 ? 'word' : 'words'}', style: T.tiny.copyWith(color: C.text3)),
          ]),
        ),
      ],
    );
  }
}

/// The "Your notes" section at the foot of a module: this module's notes with their times, and Write to open the
/// card. It redraws whenever a note is saved, from the card or anywhere else.
class LessonNotes extends StatefulWidget {
  const LessonNotes({
    super.key,
    required this.course,
    required this.file,
    this.title,
    this.repository,
  });

  final String course;
  final String file;
  final String? title;
  final LessonNotesRepository? repository;

  @override
  State<LessonNotes> createState() => _LessonNotesState();
}

class _LessonNotesState extends State<LessonNotes> {
  LessonNotesRepository? _repo;
  NoteDoc _doc = NoteDoc();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repo = widget.repository ?? AppScope.of(context).lessonNotes;
    if (!identical(repo, _repo)) {
      _repo?.removeListener(_reload);
      _repo = repo;
      repo.addListener(_reload);
      _reload();
    }
  }

  @override
  void dispose() {
    _repo?.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final repo = _repo;
    if (repo == null) return;
    try {
      final doc = await repo.localDoc(course: widget.course, file: widget.file);
      if (mounted) setState(() => _doc = doc);
    } catch (_) {}
  }

  Future<void> _open() async {
    await openNoteCard(context,
        course: widget.course, file: widget.file, title: widget.title, repository: widget.repository);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final notes = _doc.notes.where((n) => !n.isEmpty).toList();
    return ReadingSection(
      label: 'Your notes',
      trailing: InkWell(
        key: const Key('note-write'),
        borderRadius: BorderRadius.circular(Sz.rSm),
        onTap: _open,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('Write', style: T.tiny.copyWith(color: C.green)),
            const SizedBox(width: 2),
            const Icon(Icons.edit_note_rounded, size: 16, color: C.green),
          ]),
        ),
      ),
      child: notes.isEmpty
          ? Text(
              'What you made of it. Long-press a paragraph to note on it, or tap Write. Saved as you type, kept on '
              'this phone until the server has it, and listed under All my notes.',
              style: T.body2.copyWith(color: C.text3, height: 1.6),
            )
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final n in notes) ...[
                Text(n.label,
                    style: T.small.copyWith(color: C.text, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                for (final e in n.entries.where((e) => e.text.trim().isNotEmpty)) ...[
                  Text(e.stamp(), style: T.tiny.copyWith(color: C.text3, fontSize: 11)),
                  Padding(
                    padding: const EdgeInsets.only(top: 2, bottom: 8),
                    child: Text(e.text.trim(), style: T.body2.copyWith(color: C.text2, height: 1.55)),
                  ),
                ],
                const SizedBox(height: 6),
              ],
            ]),
    );
  }
}
