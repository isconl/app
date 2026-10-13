/// BI26092620: the body of a lesson that is served as a deck document.
///
/// Opens `docId@version` from the on-device cache (zero network when it is there),
/// draws it with [CdmView], and hands over to [fallback] (the markdown reader)
/// when the document can be neither read nor fetched, so a module never opens
/// blank because the new path is unavailable.
library;

import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../ui/widgets/listen_bar.dart';
import 'cdm_model.dart';
import 'cdm_speech.dart';
import 'cdm_source.dart';
import 'cdm_view.dart';

class CdmLessonBody extends StatefulWidget {
  const CdmLessonBody({
    super.key,
    required this.docId,
    required this.version,
    required this.fallback,
    this.courseId = '',
    this.listenFile,
  });

  final String docId;
  final String version;
  final String courseId;

  /// The module file, when the lesson has no markdown of its own: the body then shows the Listen bar.
  final String? listenFile;

  /// Drawn when the document is unavailable.
  final Widget fallback;

  @override
  State<CdmLessonBody> createState() => _CdmLessonBodyState();
}

class _CdmLessonBodyState extends State<CdmLessonBody> {
  Future<CdmDoc?>? _doc;
  CdmSource? _source;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_doc != null) return;
    final services = AppScope.of(context);
    _source = CdmSource(services.api, services.db.cdm);
    _doc = _source!.open(widget.docId, widget.version);
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return FutureBuilder<CdmDoc?>(
      future: _doc,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: C.green)),
          );
        }
        final doc = snap.data;
        if (doc == null) return widget.fallback;
        final view = CdmView(
          doc,
          cache: services.db.cdm,
          imageFetch: _source!.fetchImage,
          courseId: widget.courseId,
          baseUrl: services.api.baseUrl,
          token: services.api.token,
        );
        final file = widget.listenFile;
        if (file == null) return view;
        // BI26101394: a module that is only a document gets its Listen bar from the document itself.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListenBar(course: widget.courseId, file: file, markdown: cdmSpeakableMarkdown(doc)),
            view,
          ],
        );
      },
    );
  }
}
