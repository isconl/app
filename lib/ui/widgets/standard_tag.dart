import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../services/course_standard.dart';
import '../../theme.dart';
import '../../util/module_standard.dart';

/// BI26101601: the quiet line at the foot of a module, `standard 4.5`. Amber with `older standard` when the
/// module is below the current standard, and `standard unknown` when it carries no version. A tap on an
/// amber one says why in a sentence; there are no buttons.
class StandardTagLine extends StatefulWidget {
  const StandardTagLine({super.key, required this.version, this.compact = false});

  /// The module's own version (its frontmatter `version:`), or null.
  final String? version;

  /// The smaller form used on a module list row.
  final bool compact;

  @override
  State<StandardTagLine> createState() => _StandardTagLineState();
}

class _StandardTagLineState extends State<StandardTagLine> {
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final services = AppScope.of(context);
    CourseStandard.instance.ensureLoaded(services.api, services.db);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CourseStandard.instance,
      builder: (context, _) {
        final tag = standardTagFor(version: widget.version, current: CourseStandard.instance.current);
        final text = Text(
          tag.text,
          key: const Key('standard-tag'),
          style: T.monoSmall.copyWith(color: tag.amber ? C.amber : C.text3, fontSize: widget.compact ? 9.5 : null),
        );
        if (!tag.amber) return _wrap(text);
        return _wrap(GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(olderStandardSentence), duration: Duration(seconds: 3)),
          ),
          child: text,
        ));
      },
    );
  }

  Widget _wrap(Widget child) => Padding(
        padding: widget.compact ? const EdgeInsets.only(top: 2) : const EdgeInsets.only(top: 4, bottom: 16),
        child: widget.compact ? child : Center(child: child),
      );
}

/// The Settings switch behind the module-list tag.
class StandardOnListSwitch extends StatelessWidget {
  const StandardOnListSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    final db = AppScope.of(context).db;
    return ListenableBuilder(
      listenable: CourseStandard.instance,
      builder: (context, _) => Material(
        type: MaterialType.transparency,
        child: SwitchListTile(
          key: const Key('standard-on-list'),
          contentPadding: EdgeInsets.zero,
          title: Text('Show standard on module list', style: T.body2),
          subtitle: Text('A small tag on each module row, to spot a course written to an older standard.', style: T.tiny),
          value: CourseStandard.instance.showOnList,
          onChanged: (v) => CourseStandard.instance.setShowOnList(v, db),
        ),
      ),
    );
  }
}
