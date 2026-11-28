import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../../app_scope.dart';
import '../../data/lesson_notes.dart';
import '../../data/mutations.dart' show MutationResult;
import '../../data/note_entries.dart';
import '../../theme.dart';
import '../views/study_notes_view.dart';

/// BI26112301: the module's notes in a floating card instead of a bottom sheet.
///
///  * the card sits centred, and while the keyboard is up its lower edge rides just above the keyboard, so Save,
///    Sync and the notes list are always in sight;
///  * one row of actions: Save, Sync (with its state), New note, All notes;
///  * a module holds several notes, each anchored to the paragraph it was opened from (its index plus its first
///    words), and every entry carries its own time ("23 Nov, 08:41", "edited" once changed);
///  * as before, a pause in typing saves on the phone, a few seconds later it goes to the server, and closing the
///    card loses nothing.
Future<void> showNoteCard(
  BuildContext context, {
  required String course,
  required String file,
  String? title,
  int? anchor,
  String quote = '',
  LessonNotesRepository? repository,
}) {
  HapticFeedback.selectionClick();
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close notes',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (ctx, _, _) => NoteCard(
        course: course, file: file, title: title, anchor: anchor, quote: quote, repository: repository),
    transitionBuilder: (ctx, a, _, child) => FadeTransition(
      opacity: a,
      child: ScaleTransition(scale: Tween(begin: 0.97, end: 1.0).animate(a), child: child),
    ),
  );
}

enum NoteCardState { loading, idle, typing, savedLocal, sending, synced, waiting, refused }

class NoteCard extends StatefulWidget {
  const NoteCard({
    super.key,
    required this.course,
    required this.file,
    this.title,
    this.anchor,
    this.quote = '',
    this.repository,
    this.now,
  });

  final String course, file;
  final String? title;
  final int? anchor;
  final String quote;
  final LessonNotesRepository? repository;

  /// For tests: the clock.
  final DateTime Function()? now;

  @override
  State<NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends State<NoteCard> {
  static const _localDelay = Duration(milliseconds: 700);
  static const _sendDelay = Duration(seconds: 4);

  final _controller = TextEditingController();
  final _focus = FocusNode();
  List<NoteEntry> _entries = [];
  final Set<String> _savedBefore = {};
  late int? _anchor = widget.anchor;
  late String _quote = widget.quote;
  String? _currentId;
  String _savedText = '';
  NoteCardState _state = NoteCardState.loading;
  String? _error;
  Timer? _localTimer, _sendTimer;
  LessonNotesRepository? _repoRef;

  DateTime _now() => (widget.now ?? DateTime.now)();
  LessonNotesRepository _repo() => _repoRef ??= widget.repository ?? AppScope.of(context).lessonNotes;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _repo();
  }

  @override
  void dispose() {
    _localTimer?.cancel();
    _sendTimer?.cancel();
    final repo = _repoRef;
    if (repo != null && _state != NoteCardState.loading) {
      _applyField();
      final text = serializeNoteEntries(_entries);
      if (text != _savedText) {
        unawaited(repo
            .saveNote(course: widget.course, file: widget.file, text: text, anchor: _anchor, title: widget.title)
            .catchError((_) => MutationResult.queued()));
      } else if (_state == NoteCardState.savedLocal) {
        unawaited(repo.pushOne(course: widget.course, file: widget.file).catchError((_) => MutationResult.queued()));
      }
    }
    _controller.removeListener(_onChanged);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final note = await _repo().getNote(course: widget.course, file: widget.file);
      if (!mounted) return;
      _savedText = note?.text ?? '';
      _entries = parseNoteEntries(_savedText);
      _savedBefore.addAll(_entries.map((e) => e.id));
      final mine = _entriesHere();
      _currentId = mine.isEmpty ? null : mine.last.id;
      _controller.text = mine.isEmpty ? '' : mine.last.text;
      setState(() => _state = _savedText.isEmpty ? NoteCardState.idle : NoteCardState.synced);
      if (mine.isEmpty) _focus.requestFocus();
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = NoteCardState.idle;
          _error = 'Could not load this note: $e';
        });
      }
    }
  }

  /// The entries of the paragraph the card is on; a note written before anchors is shown everywhere.
  List<NoteEntry> _entriesHere() => _entries.where((e) => e.anchor == _anchor || e.id == 'legacy').toList();

  /// Puts what is in the field into the entry being edited, starting one if there is none yet.
  void _applyField() {
    final text = _controller.text;
    final i = _entries.indexWhere((e) => e.id == _currentId);
    if (i < 0) {
      if (text.trim().isEmpty) return;
      final now = _now();
      final e = NoteEntry(id: newNoteId(now), text: text, anchor: _anchor, quote: _quote, created: now);
      _entries = [..._entries, e];
      _currentId = e.id;
      return;
    }
    final old = _entries[i];
    if (old.text == text) return;
    final edited = _savedBefore.contains(old.id) ? _now() : old.edited;
    _entries = [..._entries]..[i] = old.copyWith(text: text, edited: edited);
  }

  void _onChanged() {
    if (_state == NoteCardState.loading) return;
    if (_state != NoteCardState.typing) setState(() => _state = NoteCardState.typing);
    _localTimer?.cancel();
    _sendTimer?.cancel();
    _localTimer = Timer(_localDelay, _saveLocal);
  }

  Future<void> _saveLocal() async {
    if (!mounted) return;
    _applyField();
    final text = serializeNoteEntries(_entries);
    await _repo().saveDraft(course: widget.course, file: widget.file, text: text, anchor: _anchor, title: widget.title);
    if (!mounted) return;
    setState(() => _state = NoteCardState.savedLocal);
    _sendTimer?.cancel();
    _sendTimer = Timer(_sendDelay, _send);
  }

  Future<void> _send() async {
    if (!mounted) return;
    _localTimer?.cancel();
    _sendTimer?.cancel();
    _applyField();
    final text = serializeNoteEntries(_entries);
    setState(() => _state = NoteCardState.sending);
    final res = await _repo().saveNote(course: widget.course, file: widget.file, text: text, anchor: _anchor, title: widget.title);
    if (!mounted) return;
    _savedText = text;
    setState(() {
      if (!res.ok) {
        _state = NoteCardState.refused;
        _error = res.error;
      } else {
        _state = res.queued ? NoteCardState.waiting : NoteCardState.synced;
        _error = null;
      }
    });
  }

  void _newNote() {
    _applyField();
    setState(() {
      _currentId = null;
      _controller.text = '';
    });
    _focus.requestFocus();
  }

  void _edit(NoteEntry e) {
    _applyField();
    setState(() {
      _currentId = e.id;
      _controller.text = e.text;
    });
    _focus.requestFocus();
  }

  void _goTo(int? anchor, String quote) {
    _applyField();
    final here = _entries.where((e) => e.anchor == anchor).toList();
    setState(() {
      _anchor = anchor;
      _quote = quote;
      _currentId = here.isEmpty ? null : here.last.id;
      _controller.text = here.isEmpty ? '' : here.last.text;
    });
  }

  ({IconData icon, String tip, Color color}) get _syncLook => switch (_state) {
        NoteCardState.synced => (icon: Icons.cloud_done_outlined, tip: 'Synced', color: C.greenBright),
        NoteCardState.sending => (icon: Icons.cloud_upload_outlined, tip: 'Sending', color: C.text2),
        NoteCardState.waiting => (icon: Icons.cloud_off_outlined, tip: 'On this phone, waiting for a connection', color: C.text2),
        NoteCardState.refused => (icon: Icons.error_outline, tip: 'The server refused it; tap to try again', color: Colors.orangeAccent),
        NoteCardState.savedLocal || NoteCardState.typing => (icon: Icons.sync, tip: 'Saved on this phone; tap to send now', color: C.text2),
        _ => (icon: Icons.sync, tip: 'Sync', color: C.text3),
      };

  Widget _bar() {
    final sync = _syncLook;
    final heading = (widget.title ?? '').trim().isEmpty ? 'Notes' : widget.title!.trim();
    final sub = _anchor == null ? 'Whole module' : (_quote.isEmpty ? 'Paragraph ${_anchor! + 1}' : '¶ ${_anchor! + 1} · "$_quote"');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 4),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(heading, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.small.copyWith(color: C.text, fontWeight: FontWeight.w600)),
            Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.tiny.copyWith(color: C.text3)),
          ]),
        ),
        IconButton(key: const Key('note-save'), tooltip: 'Save', icon: const Icon(Icons.check), color: C.greenBright, onPressed: _send),
        IconButton(key: const Key('note-sync'), tooltip: sync.tip, icon: Icon(sync.icon), color: sync.color, onPressed: _send),
        IconButton(key: const Key('note-new'), tooltip: 'New note', icon: const Icon(Icons.add), color: C.text2, onPressed: _newNote),
        PopupMenuButton<Object>(
          key: const Key('note-all'),
          tooltip: 'All notes',
          icon: const Icon(Icons.notes, color: C.text2),
          color: C.panel,
          onSelected: (v) {
            if (v == 'all') {
              Navigator.of(context).pop();
              Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const StudyNotesView()));
            } else if (v is NoteEntry) {
              _goTo(v.anchor, v.quote);
            }
          },
          itemBuilder: (_) {
            final byAnchor = <int?, NoteEntry>{};
            for (final e in _entries) {
              if (e.id != 'legacy') byAnchor[e.anchor] = e;
            }
            return [
              for (final e in byAnchor.values)
                PopupMenuItem<Object>(
                  value: e,
                  child: Text(e.anchor == null ? 'Whole module' : '¶ ${e.anchor! + 1}${e.quote.isEmpty ? '' : ' · ${e.quote}'}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: T.small),
                ),
              if (byAnchor.isNotEmpty) const PopupMenuDivider(),
              PopupMenuItem<Object>(value: 'all', child: Text('All my notes', style: T.small)),
            ];
          },
        ),
      ]),
    );
  }

  Widget _entry(NoteEntry e) {
    final head = [
      if (e.created != null) noteTime(e.created!) else 'earlier',
      if (e.edited != null) 'edited',
    ].join(' · ');
    return InkWell(
      onTap: () => _edit(e),
      borderRadius: BorderRadius.circular(Sz.rMd),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(head, style: T.tiny.copyWith(color: C.text3, letterSpacing: 0.3)),
          const SizedBox(height: 2),
          Text(e.text, style: T.body.copyWith(color: C.text, fontSize: 14, height: 1.5)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final inset = mq.viewInsets.bottom;
    final maxH = (mq.size.height - inset - mq.padding.top - 32).clamp(200.0, 640.0);
    final others = _entriesHere().where((e) => e.id != _currentId).toList();
    final current = _entries.where((e) => e.id == _currentId).toList();
    return SafeArea(
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 120),
        padding: EdgeInsets.fromLTRB(12, 12, 12, inset + 12),
        child: Align(
          alignment: inset > 0 ? Alignment.bottomCenter : Alignment.center,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 560, maxHeight: maxH),
            child: Material(
              key: const Key('note-card'),
              color: C.panel,
              elevation: 12,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Sz.rXl), side: const BorderSide(color: C.border)),
              clipBehavior: Clip.antiAlias,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _bar(),
                const Divider(height: 1, color: C.border),
                Flexible(
                  child: _state == NoteCardState.loading
                      ? const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
                      : ListView(
                          shrinkWrap: true,
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                          children: [
                            for (final e in others) _entry(e),
                            if (current.isNotEmpty && current.first.created != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                    [noteTime(current.first.created!), if (current.first.edited != null) 'edited'].join(' · '),
                                    style: T.tiny.copyWith(color: C.text3, letterSpacing: 0.3)),
                              ),
                            TextField(
                              key: const Key('note-field'),
                              controller: _controller,
                              focusNode: _focus,
                              minLines: 3,
                              maxLines: 10,
                              textCapitalization: TextCapitalization.sentences,
                              style: T.body.copyWith(fontSize: 15, height: 1.6, color: C.text),
                              decoration: InputDecoration(
                                hintText: _currentId == null ? 'A new note on this paragraph' : null,
                                border: InputBorder.none,
                                isDense: true,
                              ),
                            ),
                            if (_error != null) Text(_error!, style: T.tiny.copyWith(color: Colors.orangeAccent)),
                          ],
                        ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
