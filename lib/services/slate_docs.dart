import 'package:flutter/material.dart';
import 'package:slate_ui/slate_ui.dart';

import '../api/client.dart';
import '../app_scope.dart';
import '../data/db.dart';
import '../data/lesson_notes.dart';
import '../data/mutations.dart' show MutationResult;
import '../ui/widgets/lesson_notes_editor.dart';
import '../ui/widgets/reader.dart' show ReadingBody;
import '../util/fmt.dart' as fmt;
import '../util/markdown.dart' show MarkdownAnchors, ParagraphHook;

/// BI26112340: iSconl's half of slate's docs screens (the screens themselves are in package:slate_ui, so slate's own
/// app can mount them later). Docs come from hub's `/api/slate/docs/<name>`; the phone keeps its last copy of each in
/// the snapshot store; annotations are the module notes card, written to slate as `NOTES.<name>` beside the doc.

/// Notes on slate docs are kept in the same table as module notes, under this course, and never go to spark.
const slateDocsCourse = 'slate:docs';

class HubSlateDocs implements SlateDocsClient {
  HubSlateDocs(this.api);
  final ApiClient api;

  @override
  Future<SlateDoc> doc(String key) async {
    final res = fmt.m(await api.getJson('/api/slate/docs/${Uri.encodeComponent(key)}', stored: false));
    return SlateDoc(key: fmt.s(res['key']).isEmpty ? key : fmt.s(res['key']), text: fmt.s(res['text']), etag: fmt.s(res['etag']));
  }
}

/// The phone's copies of slate docs, in the snapshot store, so a doc opened once reads with no signal.
class SnapshotDocStore implements SlateDocStore {
  SnapshotDocStore(this.db);
  final AppDb db;
  static String _k(String key) => 'slate-doc:$key';
  static const _recentKey = 'slate-doc-recents';

  @override
  Future<SlateDoc?> read(String key) async {
    final row = await db.getSnapshot(_k(key));
    if (row == null) return null;
    final m = fmt.m(row.$1);
    return SlateDoc(key: key, text: fmt.s(m['text']), etag: fmt.s(m['etag']), fetchedAt: row.$2);
  }

  @override
  Future<void> write(SlateDoc doc) => db.putSnapshot(_k(doc.key), {'text': doc.text, 'etag': doc.etag});

  @override
  Future<List<String>> recents() async {
    final row = await db.getSnapshot(_recentKey);
    return row == null ? <String>[] : fmt.l(row.$1).map((e) => fmt.s(e)).where((e) => e.isNotEmpty).toList();
  }

  @override
  Future<void> touch(String key) async {
    final r = await recents();
    r
      ..remove(key)
      ..insert(0, key);
    await db.putSnapshot(_recentKey, r.take(20).toList());
  }
}

/// Annotations on slate docs: the module notes repository, pointed at slate instead of spark.
class DocAnnotationsRepository extends LessonNotesRepository {
  DocAnnotationsRepository({required super.apiOf, required super.mutations, required super.db});

  static String notesDoc(String file) => 'NOTES.$file';

  @override
  bool owns(String course) => course.startsWith('slate:');

  @override
  Future<LessonNote?> getNote({required String course, required String file}) async {
    final local = await db.lessonNoteLocal(course: course, file: file);
    final localNote = local == null ? null : LessonNote.fromRow(local);
    if (localNote != null && localNote.sync == NoteSync.waiting) return localNote;
    try {
      final res = fmt.m(await apiOf().getJson('/api/slate/docs/${Uri.encodeComponent(notesDoc(file))}', stored: false));
      final serverText = fmt.s(res['text']);
      if (serverText.isNotEmpty && serverText != (localNote?.text ?? '')) {
        await db.adoptLessonNoteFromServer(course: course, file: file, text: serverText);
        final again = await db.lessonNoteLocal(course: course, file: file);
        return again == null ? null : LessonNote.fromRow(again);
      }
    } catch (_) {
      // No annotations in slate yet (404), or offline: the phone copy stands.
    }
    return localNote;
  }

  @override
  Future<MutationResult> pushOne({required String course, required String file}) async {
    final row = await db.lessonNoteLocal(course: course, file: file);
    if (row == null) return MutationResult.sent();
    final version = row['updated_at'] as int;
    final synced = row['synced_at'] as int?;
    if (synced != null && synced >= version) return MutationResult.sent();
    try {
      final res = await apiOf().postJson('/api/slate/docs/${Uri.encodeComponent(notesDoc(file))}', {'text': row['text'] ?? ''});
      await db.markLessonNoteSynced(course: course, file: file, version: version);
      lastError = null;
      await refreshWaiting();
      return MutationResult.sent(res);
    } on OfflineException {
      lastError = 'offline';
      return MutationResult.queued();
    } on ApiException catch (e) {
      lastError = e.message;
      if (e.transient || (e.status == 404 && e.authSuspect)) return MutationResult.queued();
      return MutationResult.failed(e.message);
    } catch (e) {
      lastError = '$e';
      return MutationResult.queued();
    }
  }

  @override
  Future<int> pushAll() async {
    var sent = 0;
    for (final row in await db.unsyncedLessonNotes()) {
      final course = row['course'] as String;
      if (!owns(course)) continue;
      final r = await pushOne(course: course, file: row['file'] as String);
      if (r.queued) break;
      if (r.ok) sent++;
    }
    await refreshWaiting();
    return sent;
  }
}

final Expando<DocAnnotationsRepository> _repos = Expando('slate-doc-notes');

/// One annotations repository per app, its sends added to the app's sync the first time it is asked for.
DocAnnotationsRepository docAnnotations(AppServices s) => _repos[s] ??= () {
      final r = DocAnnotationsRepository(apiOf: () => s.api, mutations: s.mutations, db: s.db);
      s.sync.pushers.add(r.pushAll);
      r.refreshWaiting();
      return r;
    }();

/// Everything slate's docs screens need from iSconl.
SlateDocsHost slateDocsHost(BuildContext context) {
  final s = AppScope.of(context);
  final notes = docAnnotations(s);
  return SlateDocsHost(
    client: HubSlateDocs(s.api),
    store: SnapshotDocStore(s.db),
    render: (ctx, md, hooks) => _DocBody(markdown: md, hooks: hooks),
    annotate: (ctx, key, {block, text, title}) => openNoteCard(ctx,
        course: slateDocsCourse, file: key, title: title, paragraph: block, paragraphText: text, repository: notes),
    annotations: (ctx, key, title) => LessonNotes(
      course: slateDocsCourse,
      file: key,
      title: title,
      repository: notes,
      label: 'Your annotations',
      blurb: 'Long-press a paragraph to annotate it, or tap Write. Saved on this phone at once and sent to slate '
          'beside the doc (NOTES.$key), so any session can read them.',
    ),
  );
}

/// The doc drawn with the module reader, so a doc reads exactly as a module does.
class _DocBody extends StatefulWidget {
  const _DocBody({required this.markdown, required this.hooks});
  final String markdown;
  final SlateDocHooks hooks;

  @override
  State<_DocBody> createState() => _DocBodyState();
}

class _DocBodyState extends State<_DocBody> {
  final _anchors = MarkdownAnchors();

  @override
  Widget build(BuildContext context) {
    widget.hooks.revealHeading = _anchors.revealAnchor;
    final s = AppScope.of(context);
    return ReadingBody(
      widget.markdown,
      anchors: _anchors,
      baseUrl: s.api.baseUrl,
      token: s.api.token,
      paragraphHook: ParagraphHook(
        onLongPress: widget.hooks.onParagraphLongPress,
        footer: (_, __) => const SizedBox.shrink(),
      ),
    );
  }
}
