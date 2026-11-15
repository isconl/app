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
    // BI26111600 (Sconl, 15 Nov 2026): status and export on one row, each a small chip that changes itself when
    // tapped, with no separate Change buttons.
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          _ControlChip(
            key: const Key('course-status'),
            label: status,
            icon: status == 'active' ? Icons.play_circle_outline_rounded : Icons.pause_circle_outline_rounded,
            on: status == 'active',
            onTap: _busy ? null : () => _change(title: 'Course status', options: courseStatuses, current: status, path: '/api/learning/course/status', field: 'status', extra: {'courseId': widget.courseId}),
          ),
          const SizedBox(width: 6),
          Tooltip(
            message: allowed ? 'Export classification' : 'Only your own signed-in session can change this.',
            child: _ControlChip(
              key: const Key('course-export'),
              label: export,
              icon: export == 'publishable' ? Icons.public_rounded : Icons.lock_outline_rounded,
              on: export == 'publishable',
              onTap: (_busy || !allowed) ? null : () => _change(title: 'Export classification', options: exportClasses, current: export, path: '/api/learning/export/set', field: 'export', extra: {'course': widget.courseId}),
            ),
          ),
          if (_busy) ...[const SizedBox(width: 8), const MiniSpinner()],
        ],
      ),
    );
  }
}

/// One tappable control: an icon and its value, with a small caret when it can be changed.
class _ControlChip extends StatelessWidget {
  const _ControlChip({super.key, required this.label, required this.icon, required this.on, this.onTap});
  final String label;
  final IconData icon;
  final bool on;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = on ? C.green : C.text2;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: on ? C.greenBg : Colors.transparent,
          border: Border.all(color: on ? C.greenDim : C.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: c),
          const SizedBox(width: 5),
          Text(label, style: T.tiny.copyWith(color: c, fontWeight: FontWeight.w600)),
          if (onTap != null) ...[const SizedBox(width: 2), Icon(Icons.expand_more_rounded, size: 13, color: c)],
        ]),
      ),
    );
  }
}
