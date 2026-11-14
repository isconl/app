import 'package:flutter/foundation.dart';

import '../api/client.dart';
import '../util/fmt.dart' as fmt;
import 'db.dart';
import 'mutations.dart';

/// Where a note stands against the server.
enum NoteSync {
  /// The server has this exact text.
  synced,

  /// Saved on the phone; the next sync sends it.
  waiting,
}

class LessonNote {
  const LessonNote({
    required this.course,
    required this.file,
    required this.text,
    this.anchor,
    this.updatedAt,
    this.syncedAt,
    this.title,
  });

  final String course;
  final String file;
  final String text;
  final int? anchor;
  final DateTime? updatedAt;
  final DateTime? syncedAt;
  final String? title;

  NoteSync get sync => (syncedAt != null &&
          updatedAt != null &&
          !updatedAt!.isAfter(syncedAt!))
      ? NoteSync.synced
      : NoteSync.waiting;

  /// A readable name: the module title when known, else the file name tidied.
  String get displayTitle {
    final t = (title ?? '').trim();
    if (t.isNotEmpty) return t;
    var f = file.replaceAll(RegExp(r'\.md$', caseSensitive: false), '');
    f = f.replaceFirst(RegExp(r'^\d{8}_'), '');
    f = f.replaceAll(RegExp(r'_v\d+_\d+_\d+$'), '');
    final m = RegExp(r'module_(\d+)_(.*)$').firstMatch(f);
    if (m != null) f = 'Module ${int.parse(m.group(1)!)}: ${m.group(2)}';
    return f.replaceAll('_', ' ');
  }

  static LessonNote fromRow(Map<String, dynamic> r) {
    DateTime? at(Object? v) =>
        v is int ? DateTime.fromMillisecondsSinceEpoch(v) : null;
    return LessonNote(
      course: r['course'] as String,
      file: r['file'] as String,
      text: (r['text'] as String?) ?? '',
      anchor: r['anchor'] as int?,
      updatedAt: at(r['updated_at']),
      syncedAt: at(r['synced_at']),
      title: r['title'] as String?,
    );
  }
}

/// Repository for lesson notes (BI26092614, reworked BI26111402).
///
/// The phone is where a note is written, so the phone copy is the one that
/// counts until the server has it:
///  * every keystroke pause saves on the phone ([saveDraft]); nothing typed is
///    lost by closing the sheet, leaving the module or losing signal;
///  * a note is "waiting" until the server confirms that exact version, and
///    [pushAll] sends every waiting note, newest text only, so there is no
///    queue of stale copies and a retry is always safe;
///  * the server copy (spark, `learning/<course>/_notes/<file>` on engines) is
///    what the web console, the tutor and `_kit/bin/pull-study-notes.sh` read.
///
/// Storage stays behind this one class, so moving notes to deck later
/// changes only this file.
class LessonNotesRepository extends ChangeNotifier {
  LessonNotesRepository({
    required this.apiOf,
    required this.mutations,
    required this.db,
  });

  final ApiClient Function() apiOf;
  final Mutations mutations;
  final AppDb db;

  bool _pushing = false;
  int waiting = 0;
  String? lastError;

  Future<void> refreshWaiting() async {
    try {
      waiting = (await db.unsyncedLessonNotes())
          .where((r) => (r['text'] as String? ?? '').trim().isNotEmpty ||
              r['synced_at'] != null)
          .length;
    } catch (_) {}
    notifyListeners();
  }

  Future<LessonNote?> getNote({
    required String course,
    required String file,
  }) async {
    final local = await db.lessonNoteLocal(course: course, file: file);
    final localNote = local == null ? null : LessonNote.fromRow(local);

    // An unsent edit on the phone is newer than anything the server has.
    if (localNote != null && localNote.sync == NoteSync.waiting) {
      return localNote;
    }

    try {
      final res = await apiOf().getJson(
        '/api/learning/notes?course=${Uri.encodeQueryComponent(course)}'
        '&file=${Uri.encodeQueryComponent(file)}',
        // A cached answer could be older than the phone's synced copy.
        stored: false,
      );
      final serverText = fmt.s(fmt.m(res)['text']);
      if (serverText != (localNote?.text ?? '') && serverText.isNotEmpty) {
        // Written somewhere else (the web console): take it in.
        await db.adoptLessonNoteFromServer(
            course: course, file: file, text: serverText);
        final again = await db.lessonNoteLocal(course: course, file: file);
        return again == null ? null : LessonNote.fromRow(again);
      }
    } catch (_) {
      // Offline: the phone copy stands.
    }
    if (localNote == null) return null;
    if (localNote.text.isEmpty && localNote.anchor == null) return null;
    return localNote;
  }

  /// Saves on the phone only. Cheap; call it as the reader types.
  Future<void> saveDraft({
    required String course,
    required String file,
    required String text,
    int? anchor,
    String? title,
  }) async {
    await db.saveLessonNoteLocal(
        course: course, file: file, text: text, anchor: anchor, title: title);
    await refreshWaiting();
  }

  /// Saves on the phone, then tries to send it now.
  /// [MutationResult.sent] when the server has it, [MutationResult.queued]
  /// when it is safe on the phone and will go with the next sync, and
  /// [MutationResult.failed] only when the server refused it outright.
  Future<MutationResult> saveNote({
    required String course,
    required String file,
    required String text,
    int? anchor,
    String? title,
  }) async {
    await saveDraft(
        course: course, file: file, text: text, anchor: anchor, title: title);
    return pushOne(course: course, file: file);
  }

  Future<MutationResult> pushOne({
    required String course,
    required String file,
  }) async {
    final row = await db.lessonNoteLocal(course: course, file: file);
    if (row == null) return MutationResult.sent();
    final r = await _send(row);
    await refreshWaiting();
    return r;
  }

  Future<MutationResult> _send(Map<String, dynamic> row) async {
    final version = row['updated_at'] as int;
    final synced = row['synced_at'] as int?;
    if (synced != null && synced >= version) return MutationResult.sent();
    final course = row['course'] as String;
    final file = row['file'] as String;
    try {
      final res = await apiOf().postJson('/api/learning/notes', {
        'course': course,
        'file': file,
        'text': row['text'] ?? '',
      });
      await db.markLessonNoteSynced(
          course: course, file: file, version: version);
      lastError = null;
      return MutationResult.sent(res);
    } on OfflineException {
      lastError = 'offline';
      return MutationResult.queued();
    } on ApiException catch (e) {
      lastError = e.message;
      if (e.transient || (e.status == 404 && e.authSuspect)) {
        return MutationResult.queued();
      }
      return MutationResult.failed(e.message);
    } catch (e) {
      lastError = '$e';
      return MutationResult.queued();
    }
  }

  /// Sends every note the server does not have yet. Stops at the first sign
  /// the server is out of reach and leaves the rest waiting. Returns how many
  /// were delivered.
  Future<int> pushAll() async {
    if (_pushing) return 0;
    _pushing = true;
    var sent = 0;
    try {
      for (final row in await db.unsyncedLessonNotes()) {
        final text = (row['text'] as String? ?? '');
        // A note that was never sent and is still empty has nothing to say.
        if (text.trim().isEmpty && row['synced_at'] == null) continue;
        final r = await _send(row);
        if (r.queued) break;
        if (r.ok) sent++;
      }
    } finally {
      _pushing = false;
      await refreshWaiting();
    }
    return sent;
  }

  /// Every note on the phone that has any text, newest first.
  Future<List<LessonNote>> allNotes() async {
    final rows = await db.allLessonNotes();
    return rows
        .map(LessonNote.fromRow)
        .where((n) => n.text.trim().isNotEmpty)
        .toList();
  }

  /// One markdown document of every note, grouped by course, for sharing or
  /// pasting anywhere.
  Future<String> exportMarkdown({DateTime? now}) async {
    final notes = await allNotes();
    final stamp = (now ?? DateTime.now()).toIso8601String().substring(0, 10);
    final b = StringBuffer('# Study notes, $stamp\n\n');
    if (notes.isEmpty) {
      b.writeln('No notes yet.');
      return b.toString();
    }
    final byCourse = <String, List<LessonNote>>{};
    for (final n in notes) {
      byCourse.putIfAbsent(n.course, () => []).add(n);
    }
    for (final e in byCourse.entries) {
      b.writeln('## ${e.key}\n');
      for (final n in e.value) {
        final when = n.updatedAt?.toIso8601String().substring(0, 16).replaceFirst('T', ' ') ?? '';
        b.writeln('### ${n.displayTitle}\n');
        b.writeln('_${n.file}${when.isEmpty ? '' : ', $when'}_\n');
        b.writeln('${n.text.trim()}\n');
      }
    }
    return b.toString();
  }
}
