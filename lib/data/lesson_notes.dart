import '../api/client.dart';
import '../util/fmt.dart' as fmt;
import 'db.dart';
import 'mutations.dart';

class LessonNote {
  const LessonNote({
    required this.course,
    required this.file,
    required this.text,
    this.anchor,
    this.updatedAt,
  });

  final String course;
  final String file;
  final String text;
  final int? anchor;
  final DateTime? updatedAt;
}

/// Repository for lesson notes.
///
/// Keeps the notes widget behind one repository boundary so that when
/// storage moves to Canvas under the Study-on-Canvas architecture row,
/// that move changes only this one file.
class LessonNotesRepository {
  LessonNotesRepository({
    required this.apiOf,
    required this.mutations,
    required this.db,
  });

  final ApiClient Function() apiOf;
  final Mutations mutations;
  final AppDb db;

  Future<LessonNote?> getNote({
    required String course,
    required String file,
  }) async {
    final local = await db.lessonNoteLocal(course: course, file: file);
    final localAnchor = local?['anchor'] as int?;
    var text = local?['text'] as String? ?? '';
    final updatedAt = local?['updated_at'] != null
        ? DateTime.fromMillisecondsSinceEpoch(local!['updated_at'] as int)
        : null;

    try {
      final res = await apiOf().getJson(
        '/api/learning/notes?course=${Uri.encodeQueryComponent(course)}'
        '&file=${Uri.encodeQueryComponent(file)}',
      );
      final serverText = fmt.s(fmt.m(res)['text']);
      if (serverText.isNotEmpty || text.isEmpty) {
        text = serverText;
      }
    } catch (_) {
      // Offline fallback: keep local note if present.
    }

    if (text.isEmpty && localAnchor == null) return null;

    return LessonNote(
      course: course,
      file: file,
      text: text,
      anchor: localAnchor,
      updatedAt: updatedAt,
    );
  }

  Future<MutationResult> saveNote({
    required String course,
    required String file,
    required String text,
    int? anchor,
  }) async {
    await db.saveLessonNoteLocal(
      course: course,
      file: file,
      text: text,
      anchor: anchor,
    );
    return mutations.saveLessonNote(
      course: course,
      file: file,
      text: text,
    );
  }
}
