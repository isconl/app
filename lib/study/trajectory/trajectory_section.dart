import 'package:flutter/material.dart';

import '../../app_scope.dart';
import 'trajectory_model.dart';
import 'trajectory_view.dart';

/// A Trajectory module's sections inside the study reader. The learner's PROBE
/// number is kept on the phone per module (so it is there on return, offline) and
/// shown again; syncing it to the server follows once the module payload serves
/// the learner's saved number (trajectory reader 1/3).
class TrajectorySection extends StatefulWidget {
  const TrajectorySection({super.key, required this.course, required this.file, required this.trajectory});
  final String course;
  final String file;
  final Trajectory trajectory;

  @override
  State<TrajectorySection> createState() => _TrajectorySectionState();
}

class _TrajectorySectionState extends State<TrajectorySection> {
  Future<ProbeEntry?>? _saved;

  String get _key => 'probe:${widget.course}/${widget.file}';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _saved ??= AppScope.of(context).db.getSnapshot(_key).then((s) => ProbeEntry.fromJson(s?.$1));
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<ProbeEntry?>(
        future: _saved,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const SizedBox.shrink();
          return TrajectoryReader(
            trajectory: widget.trajectory,
            saved: snap.data,
            onSaveProbe: (pct) =>
                AppScope.of(context).db.putSnapshot(_key, ProbeEntry(pct, DateTime.now()).toJson()),
          );
        },
      );
}
