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
import 'cdm_source.dart';
import 'cdm_view.dart';

class CdmLessonBody extends StatefulWidget {
  const CdmLessonBody({
    super.key,
    required this.docId,
    required this.version,
    required this.fallback,
    this.courseId = '',
  });

  final String docId;
  final String version;
  final String courseId;

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
        return CdmView(
          doc,
          cache: services.db.cdm,
          imageFetch: _source!.fetchImage,
          courseId: widget.courseId,
          baseUrl: services.api.baseUrl,
          token: services.api.token,
        );
      },
    );
  }
}

/// The Listen bar for a module served as a deck document: it reads the same
/// cached document the body draws, so it works offline and costs no request.
class CdmListenBar extends StatefulWidget {
  const CdmListenBar({super.key, required this.docId, required this.version, required this.course, required this.file});
  final String docId;
  final String version;
  final String course;
  final String file;

  @override
  State<CdmListenBar> createState() => _CdmListenBarState();
}

class _CdmListenBarState extends State<CdmListenBar> {
  Future<String>? _text;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_text != null) return;
    final services = AppScope.of(context);
    final source = CdmSource(services.api, services.db.cdm);
    _text = source.open(widget.docId, widget.version).then((d) => d == null ? '' : cdmSpeakableMarkdown(d));
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
        future: _text,
        builder: (context, snap) {
          final md = snap.data ?? '';
          if (md.isEmpty) return const SizedBox.shrink();
          return ListenBar(course: widget.course, file: widget.file, markdown: md);
        },
      );
}
