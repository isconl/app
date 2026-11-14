import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../../app_scope.dart';
import '../../data/lesson_notes.dart';
import '../../data/mutations.dart' show MutationResult;
import '../../theme.dart';
import '../views/study_notes_view.dart';
import 'common.dart';
import 'reader.dart';

/// Where the note being edited stands, shown under the field.
enum _NoteState { idle, typing, savedLocal, sending, synced, waiting, refused }

/// Module notes (BI26092614, rebuilt BI26111402).
///
/// What a reader can count on:
///  * every pause in typing saves the note on the phone; closing the sheet,
///    leaving the module or killing the app loses nothing;
///  * a few seconds after typing stops, the note goes to the server by itself;
///  * the line under the field always says where the note is: on this phone,
///    sending, synced (with the time), or waiting for a connection;
///  * the button saves and sends now, and in the sheet it also closes it.
class LessonNotes extends StatefulWidget {
  const LessonNotes({
    super.key,
    required this.course,
    required this.file,
    this.anchor,
    this.title,
    this.inSheet = false,
    this.repository,
  });

  final String course;
  final String file;
  final int? anchor;
  final String? title;
  final bool inSheet;
  final LessonNotesRepository? repository;

  @override
  State<LessonNotes> createState() => _LessonNotesState();
}

class _LessonNotesState extends State<LessonNotes> {
  static const _localDelay = Duration(milliseconds: 700);
  static const _sendDelay = Duration(seconds: 4);

  final _controller = TextEditingController();
  final _focus = FocusNode();
  late bool _open = widget.inSheet;
  bool _loading = false;
  bool _loaded = false;
  String? _error;
  int? _anchor;
  String _savedText = '';
  _NoteState _state = _NoteState.idle;
  DateTime? _syncedAt;
  Timer? _localTimer;
  Timer? _sendTimer;
  LessonNotesRepository? _repoRef;

  LessonNotesRepository _repo(BuildContext context) =>
      widget.repository ?? AppScope.of(context).lessonNotes;

  bool get _dirty => _controller.text != _savedText;

  @override
  void initState() {
    super.initState();
    _anchor = widget.anchor;
    _controller.addListener(_onChanged);
    if (widget.inSheet) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _repoRef = _repo(context);
  }

  @override
  void dispose() {
    _localTimer?.cancel();
    _sendTimer?.cancel();
    // Whatever was typed and not yet saved is saved now, then sent.
    final repo = _repoRef;
    if (repo != null && _loaded && _dirty) {
      final text = _controller.text;
      unawaited(repo
          .saveNote(
            course: widget.course,
            file: widget.file,
            text: text,
            anchor: _anchor,
            title: widget.title,
          )
          .catchError((_) => MutationResult.queued()));
    } else if (repo != null && _state == _NoteState.savedLocal) {
      unawaited(repo
          .pushOne(course: widget.course, file: widget.file)
          .catchError((_) => MutationResult.queued()));
    }
    _controller.removeListener(_onChanged);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!_loaded || !_dirty) return;
    if (_state != _NoteState.typing) setState(() => _state = _NoteState.typing);
    _localTimer?.cancel();
    _sendTimer?.cancel();
    _localTimer = Timer(_localDelay, _saveLocal);
  }

  Future<void> _load() async {
    if (_loaded || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final note = await _repo(context).getNote(
        course: widget.course,
        file: widget.file,
      );
      if (!mounted) return;
      if (note != null) {
        _savedText = note.text;
        _controller.text = note.text;
        _anchor ??= note.anchor;
        _syncedAt = note.syncedAt;
        _state = note.text.isEmpty
            ? _NoteState.idle
            : note.sync == NoteSync.synced
                ? _NoteState.synced
                : _NoteState.waiting;
      }
      setState(() => _loaded = true);
      if (widget.inSheet && _controller.text.isEmpty) _focus.requestFocus();
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not load your note ($e).');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveLocal() async {
    if (!mounted || !_dirty) return;
    final text = _controller.text;
    await _repo(context).saveDraft(
      course: widget.course,
      file: widget.file,
      text: text,
      anchor: _anchor,
      title: widget.title,
    );
    if (!mounted) return;
    _savedText = text;
    setState(() => _state = _NoteState.savedLocal);
    _sendTimer?.cancel();
    _sendTimer = Timer(_sendDelay, () => _send(quiet: true));
  }

  Future<void> _send({bool quiet = false}) async {
    if (!mounted) return;
    _localTimer?.cancel();
    _sendTimer?.cancel();
    final repo = _repo(context);
    final text = _controller.text;
    setState(() => _state = _NoteState.sending);
    final res = await repo.saveNote(
      course: widget.course,
      file: widget.file,
      text: text,
      anchor: _anchor,
      title: widget.title,
    );
    if (!mounted) return;
    _savedText = text;
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

  Future<void> _done() async {
    HapticFeedback.lightImpact();
    await _send();
    if (!mounted) return;
    if (widget.inSheet && _state != _NoteState.refused) {
      Navigator.of(context).maybePop();
    }
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
        _NoteState.waiting => (
            Icons.cloud_off_rounded,
            'Safe on this phone, sends when the server answers',
            C.amber
          ),
        _NoteState.refused => (Icons.error_outline_rounded, 'Not sent: ${_error ?? 'refused'}', C.red),
      };

  int get _words =>
      RegExp(r'\S+').allMatches(_controller.text).length;

  Widget _button() {
    final busy = _state == _NoteState.sending;
    final synced = _state == _NoteState.synced && !_dirty;
    final label = busy
        ? 'Saving'
        : synced
            ? (widget.inSheet ? 'Done' : 'Saved and synced')
            : (widget.inSheet ? 'Save and close' : 'Save note');
    final icon = busy
        ? const MiniSpinner()
        : Icon(synced ? Icons.check_circle_rounded : Icons.check_rounded,
            size: 18);
    return SizedBox(
      height: 46,
      child: FilledButton.icon(
        key: const Key('note-save'),
        onPressed: busy ? null : _done,
        style: FilledButton.styleFrom(
          backgroundColor: synced ? C.greenBg2 : C.green,
          foregroundColor: synced ? C.greenBright : Colors.black,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Sz.rMd)),
          textStyle: T.body.copyWith(fontWeight: FontWeight.w600),
        ),
        icon: icon,
        label: Text(label),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final (icon, line, colour) = _status;
    final noteBody = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null && !_loaded)
          ErrorRetry(_error!, onRetry: () {
            _loaded = false;
            _load();
          }),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
          decoration: BoxDecoration(
            color: C.surface,
            borderRadius: BorderRadius.circular(Sz.rMd),
            border: Border.all(
                color: _focus.hasFocus ? C.greenDim : C.border),
          ),
          child: TextField(
            controller: _controller,
            focusNode: _focus,
            enabled: _loaded,
            maxLines: null,
            minLines: widget.inSheet ? 7 : 5,
            textCapitalization: TextCapitalization.sentences,
            keyboardType: TextInputType.multiline,
            style: T.body.copyWith(fontSize: 15, height: 1.62, color: C.text),
            onTap: () => setState(() {}),
            decoration: InputDecoration(
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              hintText: _loading
                  ? 'Loading your note'
                  : 'An idea, a question, what you would do with this.',
              hintStyle: T.body2.copyWith(color: C.text3, fontSize: 15),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(icon, size: 14, color: colour),
            const SizedBox(width: 6),
            Expanded(
              child: Text(line,
                  key: const Key('note-status'),
                  style: T.tiny.copyWith(color: colour),
                  overflow: TextOverflow.ellipsis),
            ),
            Text(
              [
                if (_anchor != null) 'Anchored to paragraph ${_anchor! + 1}',
                if (_words > 0) '$_words ${_words == 1 ? 'word' : 'words'}',
              ].join(' · '),
              style: T.tiny.copyWith(color: C.text3),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _button(),
        Align(
          alignment: Alignment.center,
          child: TextButton.icon(
            key: const Key('note-all'),
            onPressed: () => openStudyNotes(context),
            icon: const Icon(Icons.notes_rounded, size: 16),
            label: const Text('All my notes'),
            style: TextButton.styleFrom(foregroundColor: C.text2),
          ),
        ),
      ],
    );

    if (widget.inSheet) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('NOTES', style: T.label.copyWith(color: C.text2)),
              if (_loading) const MiniSpinner(),
            ],
          ),
          const SizedBox(height: 10),
          noteBody,
        ],
      );
    }

    return ReadingSection(
      label: 'Your notes',
      trailing: InkWell(
        borderRadius: BorderRadius.circular(Sz.rSm),
        onTap: () {
          setState(() => _open = !_open);
          if (_open) _load();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_loading) ...[const MiniSpinner(), const SizedBox(width: 8)],
              Text(_open ? 'Close' : 'Write',
                  style: T.tiny.copyWith(color: C.green)),
              Icon(
                  _open
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 16,
                  color: C.green),
            ],
          ),
        ),
      ),
      child: !_open
          ? Text(
              'What you made of it. Saved as you type, kept on this phone until '
              'the server has it, and listed under All my notes.',
              style: T.body2.copyWith(color: C.text3, height: 1.6),
            )
          : noteBody,
    );
  }
}
