import 'package:flutter/material.dart';

import '../../api/client.dart' show ApiException, OfflineException;
import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import 'common.dart';

/// BI26101204: the course's status and export classification on the course detail, the same two controls as the hub web
/// console (BI26100109). Status is active, archived or disabled (`POST /api/learning/course/status`). Export is internal
/// or publishable (`POST /api/learning/export/set`) and is editable only for Sconl's own signed-in session: the screen
/// finds out the way the web does, by posting the course's current value back once and treating a 200 as allowed and a
/// 403 as not, and the control stays off otherwise. Both need the live server; a refusal shows the server's reason.

const courseStatuses = ['active', 'archived', 'disabled'];
const exportClasses = ['internal', 'publishable'];

/// The course's status as the server holds it; an empty or unknown value reads as active.
String courseStatusOf(Map<String, dynamic> course) {
  final s = fmt.s(course['STATUS'] ?? course['status']).toLowerCase();
  return courseStatuses.contains(s) ? s : 'active';
}

/// The export classification; anything other than publishable is internal, the safe reading.
String courseExportOf(Map<String, dynamic> course) => fmt.s(course['EXPORT'] ?? course['export']).toLowerCase() == 'publishable' ? 'publishable' : 'internal';

/// Why a write was refused, in the server's own words where it gave any.
String courseWriteReason(int status, Map<String, dynamic> body) {
  if (status == 403) return 'Only your own signed-in session can do this.';
  final errors = body['errors'];
  if (errors is List && errors.isNotEmpty) return errors.map((e) => fmt.s(e)).join(' ');
  final e = fmt.s(body['error']);
  return e.isEmpty ? 'It did not apply.' : e;
}

class CourseControls extends StatefulWidget {
  const CourseControls({super.key, required this.courseId, required this.course});
  final String courseId;
  final Map<String, dynamic> course;

  /// Whether this session may edit the export class, found once and kept for the app's run. Tests reset it.
  static bool? exportAllowed;

  @override
  State<CourseControls> createState() => _CourseControlsState();
}

class _CourseControlsState extends State<CourseControls> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _probe());
  }

  Future<void> _probe() async {
    if (CourseControls.exportAllowed != null || !mounted) return;
    final services = AppScope.of(context);
    if (!services.sync.online || widget.courseId.isEmpty) return;
    bool ok;
    try {
      // The course's current value, so a session that is allowed changes nothing and one that is not is refused.
      await services.api.postJson('/api/learning/export/set', {'course': widget.courseId, 'export': courseExportOf(widget.course)});
      ok = true;
    } on ApiException {
      ok = false;
    } on OfflineException {
      return;
    }
    CourseControls.exportAllowed = ok;
    if (mounted) setState(() {});
  }

  Future<String?> _post(String path, Map<String, dynamic> body) async {
    final services = AppScope.of(context);
    try {
      final r = fmt.m(await services.mutations.post(path, body));
      if (r['success'] == false || r['ok'] == false) return courseWriteReason(200, r);
      return null;
    } on ApiException catch (e) {
      return courseWriteReason(e.status, {'error': e.message});
    } on OfflineException {
      return 'This needs the live server - you are offline.';
    }
  }

  Future<void> _change({required String title, required List<String> options, required String current, required String path, required String field, required Map<String, dynamic> extra}) async {
    var chosen = current;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(title, style: T.title),
          content: Segmented(options: options, value: chosen, onChanged: (v) => setD(() => chosen = v)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: T.body2.copyWith(color: C.text3))),
            FilledButton(key: const Key('course-save'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (go != true || chosen == current || !mounted) return;
    setState(() => _busy = true);
    final err = await _post(path, {...extra, field: chosen});
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      toast(context, err, error: true);
      return;
    }
    toast(context, 'Saved');
    AppScope.of(context).store.learning.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final status = courseStatusOf(widget.course);
    final export = courseExportOf(widget.course);
    final allowed = CourseControls.exportAllowed == true;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Pill('status: $status', selected: status == 'active', key: const Key('course-status')),
          TextButton(
            key: const Key('course-status-change'),
            onPressed: _busy ? null : () => _change(title: 'Course status', options: courseStatuses, current: status, path: '/api/learning/course/status', field: 'status', extra: {'courseId': widget.courseId}),
            child: const Text('Change'),
          ),
          Pill('export: $export', selected: export == 'publishable', key: const Key('course-export')),
          Tooltip(
            message: allowed ? '' : 'Only your own signed-in session can change this.',
            child: TextButton(
              key: const Key('course-export-change'),
              onPressed: (_busy || !allowed) ? null : () => _change(title: 'Export classification', options: exportClasses, current: export, path: '/api/learning/export/set', field: 'export', extra: {'course': widget.courseId}),
              child: const Text('Change'),
            ),
          ),
        ],
      ),
    );
  }
}
